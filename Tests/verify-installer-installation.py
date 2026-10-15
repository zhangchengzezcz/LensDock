"""Build and test the real installer in an owned temporary directory; never launch a host."""
from pathlib import Path
import json, plistlib, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''let resources=URL(fileURLWithPath:CommandLine.arguments[1]), original=URL(fileURLWithPath:CommandLine.arguments[2]), testDirectory=URL(fileURLWithPath:CommandLine.arguments[3])
do {
 let installer=try Installer(resources:resources)
 let installed=try installer.install(original,applicationsDirectory:testDirectory){print($0)}
 let info=try plist(installed.appendingPathComponent("Contents/Info.plist"))
 let payload=lensDigest(try Data(contentsOf:resources.appendingPathComponent("Payload/LensPanel.dylib")))
 let actual=lensDigest(try Data(contentsOf:installed.appendingPathComponent("Contents/Frameworks/LensPanel.dylib")))
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
