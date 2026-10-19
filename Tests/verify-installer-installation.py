"""Build and test the real installer in an owned temporary directory; never launch a host."""
from pathlib import Path
import json, plistlib, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''func verifyVariantSeparation(_ resources: URL, _ root: URL) throws {
 let folder=root.appendingPathComponent("variant-fixtures"), source=folder.appendingPathComponent("source"), config=folder.appendingPathComponent("resources")
 try fm.createDirectory(at:config,withIntermediateDirectories:true)
 var record=try JSONSerialization.jsonObject(with:Data(contentsOf:resources.appendingPathComponent("Pixelmator-4.3.json"))) as! [String:Any]
 let paths=(record["fileSHA256"] as! [String:String]).keys.sorted()
 var first:[String:String]=[:],second:[String:String]=[:]
 func put(_ prefix: String, _ path: String) throws {
  let file=source.appendingPathComponent(path);try fm.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
  try Data((prefix+path).utf8).write(to:file)
 }
 for path in paths { first[path]=lensDigest(Data(("first:"+path).utf8));second[path]=lensDigest(Data(("second:"+path).utf8));try put("first:",path) }
 record["fileSHA256"]=first;record["sourceVariants"]=[["id":"second","fileSHA256":second]];record["arm64CodeSHA256"]=nil
 func candidate() throws -> Installer {
  try JSONSerialization.data(withJSONObject:record).write(to:config.appendingPathComponent("Pixelmator-4.3.json"))
  return try Installer(resources:config)
 }
 var installer=try candidate();guard try installer.verifiedSourceHashes(source)==first else {throw DockError("First complete variant rejected")}
 for path in paths {try put("second:",path)}
 guard try installer.verifiedSourceHashes(source)==second else {throw DockError("Second complete variant rejected")}
 func reject(_ installer: Installer) throws {
  var rejected=false;do {_ = try installer.verifiedSourceHashes(source)}catch{rejected=true}
  if !rejected {throw DockError("Mixed or damaged source variant accepted")}
 }
 try put("first:",paths[0]);try reject(installer)
 try put("tampered:",paths[0]);try reject(installer)
 for path in paths {try put("second:",path)}
 record["sourceVariants"]=[["id":"incomplete","fileSHA256":[String:String]()]];installer=try candidate();try reject(installer)
 var invalid=second;invalid[paths[0]]=String(repeating:"g",count:64)
 record["sourceVariants"]=[["id":"invalid-digest","fileSHA256":invalid]];installer=try candidate();try reject(installer)
 record["sourceVariants"]=nil;record["fileSHA256"]=second;installer=try candidate()
 guard try installer.verifiedSourceHashes(source)==second else {throw DockError("Legacy single-variant contract rejected")}
 print("Complete source variants accepted; mixed, modified, incomplete and malformed variants rejected; legacy contract accepted.")
}
func verifyCodeFingerprint(_ installer: Installer, _ original: URL, _ root: URL) throws {
 let expected=installer.compatibility.arm64CodeSHA256!
 func reject(_ image: Data) throws {
  var rejected=false;do {_ = try arm64CodeDigest(image)}catch{rejected=true}
  guard rejected else {throw DockError("Malformed Mach-O accepted")}
 }
 let fixture=root.appendingPathComponent("code-source"), config=root.appendingPathComponent("code-resources")
 try fm.createDirectory(at:config,withIntermediateDirectories:true)
 var record=try JSONSerialization.jsonObject(with:Data(contentsOf:installer.resources.appendingPathComponent("Pixelmator-4.3.json"))) as! [String:Any]
 // Impossible whole-file hashes force the production code-fingerprint fallback.
 record["fileSHA256"]=expected.mapValues{_ in String(repeating:"0",count:64)};record["sourceVariants"]=nil
 try JSONSerialization.data(withJSONObject:record).write(to:config.appendingPathComponent("Pixelmator-4.3.json"))
 let fallback=try Installer(resources:config)
 var images:[String:Data]=[:]
 for (path,digest) in expected {
  let input=try Data(contentsOf:original.appendingPathComponent(path)), thin=try arm64Image(input)
  guard try arm64CodeDigest(input)==digest, try arm64CodeDigest(thin)==digest else {throw DockError("Python and Swift code fingerprints differ")}
  var offset=32, sig=0, link=0
  for _ in 0..<Int(try machNumber(thin,16)) {
   let command=try machNumber(thin,offset), length=Int(try machNumber(thin,offset+4))
   if command==0x1d {sig=offset}
   if command==0x19 && Data(thin[offset+8..<offset+24])==Data(Array("__LINKEDIT".utf8)+Array(repeating:0,count:6)) {link=offset}
   offset+=length
  }
  func put(_ data: inout Data,_ value: UInt64,_ p: Int,_ width: Int) {for i in 0..<width {data[p+i]=UInt8(truncatingIfNeeded:value >> (i*8))}}
  var signed=thin
  signed.append(Data(repeating:0x5a,count:32768))
  put(&signed,try machNumber(thin,sig+12)+32768,sig+12,4)
  let linkSize=try machNumber(thin,link+48,8)+32768
  put(&signed,linkSize,link+48,8);put(&signed,(linkSize+16383) & ~UInt64(16383),link+32,8)
  guard try arm64CodeDigest(signed)==digest else {throw DockError("Signature-only size variation rejected")}
  // Signature contents are excluded, but all code, data and load commands are bound.
  var changed=signed;changed[32+Int(try machNumber(thin,20))+32] ^= 1
  guard try arm64CodeDigest(changed) != digest else {throw DockError("Changed payload accepted")}
  if path.hasPrefix("Contents/MacOS/") {
   guard try arm64CodeDigest(patchedExecutable(thin)) != digest else {throw DockError("Already injected source accepted")}
   var encrypted=thin;let end=32+Int(try machNumber(thin,20))
   put(&encrypted,0x2c,end,4);put(&encrypted,24,end+4,4);put(&encrypted,1,end+16,4)
   put(&encrypted,try machNumber(thin,16)+1,16,4);put(&encrypted,try machNumber(thin,20)+24,20,4)
   try reject(encrypted)
  }
  changed=signed;changed[24] ^= 1
  guard try arm64CodeDigest(changed) != digest else {throw DockError("Changed header accepted")}
  changed=signed;put(&changed,try machNumber(signed,link+32,8)+16384,link+32,8);try reject(changed)
  changed=signed;put(&changed,0,sig+12,4);try reject(changed)
  try reject(Data(signed.dropLast()));try reject(Data(signed.prefix(31)))
  // Rewrap the unchanged arm64 slice in a FAT64 container.
  var fat=Data(repeating:0,count:4096)
  func big(_ value: UInt64,_ p: Int,_ width: Int) {for i in 0..<width {fat[p+i]=UInt8(truncatingIfNeeded:value >> ((width-1-i)*8))}}
  big(0xcafebabf,0,4);big(1,4,4);big(0x100000c,8,4);big(0,12,4);big(4096,16,8);big(UInt64(signed.count),24,8);big(12,32,4)
  fat.append(signed)
  guard try arm64CodeDigest(fat)==digest else {throw DockError("FAT64 wrapper rejected")}
  big(2,4,4);big(0x100000c,40,4);big(4096,48,8);big(UInt64(signed.count),56,8);big(12,64,4)
  try reject(fat)
  images[path]=signed
  let file=fixture.appendingPathComponent(path);try fm.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true);try signed.write(to:file)
 }
 _ = try fallback.verifiedSourceHashes(fixture)
 let path=expected.keys.sorted()[0];var damaged=images[path]!;damaged[24] ^= 1;try damaged.write(to:fixture.appendingPathComponent(path))
 var refused=false;do {_ = try fallback.verifiedSourceHashes(fixture)}catch{refused=true}
 guard refused else {throw DockError("Four-file fallback accepted a changed member")}
 print("Four production fingerprints match independent Python results; signature/size/thin/FAT64 variations accepted; changed code/header/VM sizes, truncated and overlapping inputs rejected.")
}
func verifyGenericEligibility(_ installer: Installer,_ original: URL) throws {
 for version in ["4.3","4.3.1","4.4","5","10.0"] {guard hostVersionSupported(version) else {throw DockError("Future version eligibility rejected")}}
 for version in ["4.2.99","4.3beta","","4..3","-4.3"] {guard !hostVersionSupported(version) else {throw DockError("Invalid version accepted")}}
 for (path,symbols) in installer.compatibility.requiredHostSymbols! {
  let data=try Data(contentsOf:original.appendingPathComponent(path))
  guard try hostExports(data,required:symbols),try !hostExports(data,required:["$sLensDockMissingInterface"]) else {throw DockError("Static export eligibility failed")}
 }
 // A fully stripped image can still expose a well-formed export trie.
 let name=Data("_$sDemo\0".utf8);var trie=Data([0,1]);trie.append(name);trie.append(UInt8(trie.count+1));trie.append(contentsOf:[2,0,1,0])
 var image=Data(repeating:0,count:48)
 func put(_ value: UInt32,_ offset: Int){for i in 0..<4{image[offset+i]=UInt8(truncatingIfNeeded:value >> (i*8))}}
 put(0xfeedfacf,0);put(0x100000c,4);put(6,12);put(1,16);put(16,20);put(0x80000033,32);put(16,36);put(48,40);put(UInt32(trie.count),44);image.append(trie)
 guard try hostExports(image,required:["$sDemo"]),try !hostExports(image,required:["$sMissing"]) else {throw DockError("Export-trie lookup failed")}
 image[48+2+name.count]=0
 var rejected=false;do {_ = try hostExports(image,required:["$sDemo"])}catch{rejected=true}
 guard rejected else {throw DockError("Cyclic export trie accepted")}
 guard try installer.verifiedEligibleSource(original).values.sorted()==installer.verifiedSourceHashes(original).values.sorted() else {throw DockError("Source provenance differs under generic policy")}
 print("4.3 and later eligibility, current required exports, missing export rejection, stripped export trie and cycle rejection passed; no exact code hash gate used for installation.")
}
let resources=URL(fileURLWithPath:CommandLine.arguments[1]), original=URL(fileURLWithPath:CommandLine.arguments[2]), testDirectory=URL(fileURLWithPath:CommandLine.arguments[3])
do {
 try verifyVariantSeparation(resources,testDirectory)
 let installer=try Installer(resources:resources)
 try verifyCodeFingerprint(installer,original,testDirectory)
 try verifyGenericEligibility(installer,original)
 let installed=try installer.install(original,applicationsDirectory:testDirectory){print($0)}
 let info=try plist(installed.appendingPathComponent("Contents/Info.plist"))
 let payload=lensDigest(try Data(contentsOf:resources.appendingPathComponent("Payload/LensPanel.dylib")))
 let actual=lensDigest(try Data(contentsOf:installed.appendingPathComponent("Contents/Frameworks/LensPanel.dylib")))
 guard let copiedSource=info["LensDockSourceFileSHA256"] as? [String:String], copiedSource == (try installer.verifiedEligibleSource(original)) else {throw DockError("Installed source provenance missing or incorrect")}
 guard info["LensDockCompatibilityPolicy"] as? String == "capability-check-v1",try Data(contentsOf:installed.appendingPathComponent("Contents/Resources/LensDock-HostInterfaces.json")) == Data(contentsOf:resources.appendingPathComponent("Pixelmator-4.3.json")) else {throw DockError("Runtime compatibility contract missing")}
 guard installedHostIsCurrent(info,version:previewVersion,expectedHash:payload,actualHash:actual) else {throw DockError("Freshly signed host not recognized")}
 _ = try installer.validate(original)
 print("Isolated full installation, signed module recognition, strict signature and unchanged vendor verified.")
} catch {fputs(error.localizedDescription+"\n",stderr);exit(1)}
'''

def verify():
    app = ROOT / 'Build/LensDock.app'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    subprocess.run([str(app/'Contents/MacOS/LensDock'), '--verify-installation-state'], check=True)
    # The prefix is the exact production Installer, before the UI entrypoint.
    source = (ROOT/'Sources/Installer/LensDock.swift').read_text().split('final class DockApp:')[0]
    version = json.loads((ROOT/'Version.json').read_text())['version']
    with tempfile.TemporaryDirectory(prefix='installer-check-', dir=ROOT/'Build') as owned:
        root = Path(owned)
        contents = root/'InstallerProbe.app/Contents'
        (contents/'MacOS').mkdir(parents=True)
        (contents/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.lensdock.installer-probe','CFBundleExecutable':'InstallerProbe','CFBundleShortVersionString':version,'CFBundlePackageType':'APPL'}))
        swift = root/'InstallerProbe.swift'
        swift.write_text(source+HARNESS)
        executable = contents/'MacOS/InstallerProbe'
        subprocess.run(['xcrun','swiftc','-target','arm64-apple-macos26.0','-O',str(swift),'-o',str(executable)],check=True)
        subprocess.run([str(executable),str(app/'Contents/Resources'),'/Applications/Pixelmator Pro Creator Studio.app',str(root/'isolated-applications')],check=True,cwd=ROOT)

if __name__ == '__main__':
    verify()
