"""Build Apple Silicon native modules and the LensDock installer. Needs Xcode."""
from pathlib import Path
import subprocess,plistlib,shutil,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
VERSION=json.loads((ROOT/'Version.json').read_text())
RELEASE=VERSION['version']+'-'+VERSION['channel']
SOURCES=('LensPanel.m','LensProfilePicker.m','LensVignettingFilter.m','LensNativeDocument.m','LensNativeProfileEngine.m','LensCornerAssessment.m','LensNativeState.m','LensCorrectionSettings.m','LensLiveDocument.m','LensRecommendationPolicy.m','LensHostDiagnostics.m')
def call(*args):subprocess.run(list(args),check=True)
def build():
 native=ROOT/'Sources/Native';payload=ROOT/'Build/Payload';payload.mkdir(parents=True,exist_ok=True)
 call('xcrun','swiftc','-target','arm64-apple-macos26.0','-O','-emit-library','-module-name','LensLiveSource',str(native/'LensLiveSource.swift'),'-Xlinker','-undefined','-Xlinker','dynamic_lookup','-Xlinker','-install_name','-Xlinker','@rpath/LensLiveSource.dylib','-o',str(payload/'LensLiveSource.dylib'))
 call('xcrun','clang','-arch','arm64','-mmacosx-version-min=26.0','-O2','-Wno-deprecated-declarations','-dynamiclib','-fobjc-arc','-install_name','@rpath/LensPanel.dylib','-framework','Cocoa','-framework','CoreImage','-framework','ImageIO','-framework','UniformTypeIdentifiers','-lsqlite3',*[str(native/s) for s in SOURCES],'-o',str(payload/'LensPanel.dylib'))
 app=ROOT/'Build/LensDock.app';contents=app/'Contents';(contents/'MacOS').mkdir(parents=True,exist_ok=True);resources=contents/'Resources';resources.mkdir(exist_ok=True)
 call('xcrun','swiftc','-target','arm64-apple-macos26.0','-O',str(ROOT/'Sources/Installer/LensDock.swift'),'-o',str(contents/'MacOS/LensDock'))
 for src,dst in [(payload,resources/'Payload'),(ROOT/'Resources/LensBridge',resources/'Payload/LensBridge'),(ROOT/'Vendor/Lib',resources/'Payload/Lib'),(ROOT/'Vendor/Licenses',resources/'Licenses')]:shutil.copytree(src,dst,dirs_exist_ok=True)
 shutil.copy2(ROOT/'Resources/native-effects-template.json',resources/'Payload/native-effects-template.json');shutil.copy2(ROOT/'Compatibility/Pixelmator-4.3.json',resources/'Pixelmator-4.3.json')
 artwork=ROOT/'Resources/Artwork';artwork.mkdir(exist_ok=True)
 call('xcrun','swiftc','-target','arm64-apple-macos26.0',str(ROOT/'Scripts/render_assets.swift'),'-o',str(ROOT/'Build/render-assets'))
 call(str(ROOT/'Build/render-assets'),str(artwork))
 call('tiffutil','-cathidpicheck',str(artwork/'DMG-background.png'),str(artwork/'DMG-background@2x.png'),'-out',str(artwork/'DMG-background.tiff'))
 call('iconutil','-c','icns',str(artwork/'LensDock.iconset'),'-o',str(resources/'LensDock.icns'))
 info={'CFBundleIconFile':'LensDock','CFBundleIdentifier':'local.lensdock.installer','CFBundleName':'LensDock','CFBundleDisplayName':'LensDock','CFBundleExecutable':'LensDock','CFBundlePackageType':'APPL','CFBundleShortVersionString':VERSION['version'],'CFBundleVersion':VERSION['build'],'LSMinimumSystemVersion':'26.0','NSHighResolutionCapable':True}
 (contents/'Info.plist').write_bytes(plistlib.dumps(info))
 for dylib in (resources/'Payload').rglob('*.dylib'):call('codesign','--force','--sign','-',str(dylib))
 call('codesign','--force','--deep','--sign','-',str(app));call('codesign','--verify','--deep','--strict',str(app))
 result={'version':RELEASE,'deploymentTarget':'26.0','notarized':False,'redistributesVendorApp':False,'sha256':{str(p.relative_to(app)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [contents/'MacOS/LensDock',resources/'Payload/LensPanel.dylib',resources/'Payload/LensLiveSource.dylib']}}
 (ROOT/'Build/build-manifest.json').write_text(json.dumps(result,indent=2)+'\n');print(app)
if __name__=='__main__':build()
