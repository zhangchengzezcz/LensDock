"""Package only LensDock and independent dependencies; never include a local host."""
from pathlib import Path
import subprocess,shutil,hashlib,json,zipfile,plistlib
import dmgbuild
from finalize_dmg_background import finalize
ROOT=Path(__file__).resolve().parents[1]
VERSION=json.loads((ROOT/'Version.json').read_text())
RELEASE=VERSION['version']+'-'+VERSION['channel']
def package():
 app=ROOT/'Build/LensDock.app';distribution=ROOT/'Distribution'/RELEASE;distribution.mkdir(parents=True,exist_ok=True)
 subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
 info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
 build=json.loads((ROOT/'Build/build-manifest.json').read_text())
 if info.get('CFBundleShortVersionString')!=VERSION['version'] or build.get('version')!=RELEASE:raise ValueError('Build the requested version before packaging')
 for name,digest in build['sha256'].items():
  if hashlib.sha256((app/name).read_bytes()).hexdigest()!=digest:raise ValueError('Built payload changed: '+name)
 source=distribution/f'LensDock-{RELEASE}-source.zip'
 dmg=distribution/f'LensDock-{RELEASE}-Retina.dmg'
 if source.exists() or dmg.exists():raise FileExistsError('Versioned assets already exist; use a new version or explicitly archive the candidate first')
 dirs=['Sources','Scripts','Resources','Vendor','Compatibility','Evidence','Tests','Documentation','.github']
 files=[ROOT/n for n in ['README.md','LICENSE','.gitignore','Version.json']]
 for name in dirs:
  files.extend(p for p in (ROOT/name).rglob('*') if p.is_file() and '__pycache__' not in p.parts and 'PrivateRAW' not in p.parts)
 with zipfile.ZipFile(source,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
  for p in sorted(files):archive.write(p,'LensDock/'+str(p.relative_to(ROOT)))
 stage=ROOT/'Build/DMG';stage.mkdir(exist_ok=True)
 # Staging is owned by this script and may be rebuilt. User-installed apps are never touched.
 for p in stage.iterdir():
  if p.is_dir() and not p.is_symlink():shutil.rmtree(p)
  else:p.unlink()
 shutil.copytree(app,stage/'LensDock.app',symlinks=True)
 guide=stage/'说明与源码';guide.mkdir(exist_ok=True)
 shutil.copy2(ROOT/'README.md',guide/'请先阅读.md');shutil.copytree(ROOT/'Documentation',guide/'Documentation');shutil.copy2(source,guide/source.name);shutil.copytree(ROOT/'Vendor/Licenses',guide/'Licenses');shutil.copy2(ROOT/'Vendor/NOTICE.md',guide/'Licenses/NOTICE.md')
 volume_name='LensDock Retina Preview'
 editable=ROOT/'Build/LensDock-editable.dmg';editable.unlink(missing_ok=True)
 dmgbuild.build_dmg(str(editable),volume_name,settings_file=str(ROOT/'Scripts/dmg_settings.py'),lookForHiDPI=False,defines={'stage':str(stage),'background':str(ROOT/'Resources/Artwork/DMG-background.pdf')})
 mount=ROOT/'Build/DMG-Mount';mount.mkdir(exist_ok=True)
 subprocess.run(['hdiutil','attach','-readwrite','-nobrowse','-noautoopen','-mountpoint',str(mount),str(editable)],check=True,stdout=subprocess.DEVNULL)
 try:
  background=finalize(mount,volume_name)
  subprocess.run(['codesign','--verify','--deep','--strict',str(mount/'LensDock.app')],check=True)
 finally:subprocess.run(['hdiutil','detach',str(mount)],check=True,stdout=subprocess.DEVNULL)
 # Versioned paths were checked before producing either asset.
 subprocess.run(['hdiutil','convert',str(editable),'-format','UDZO','-imagekey','zlib-level=9','-o',str(dmg)],check=True,stdout=subprocess.DEVNULL)
 subprocess.run(['hdiutil','verify',str(dmg)],check=True,stdout=subprocess.DEVNULL)
 (distribution/'background-manifest.json').write_text(json.dumps(background,indent=2)+'\n')
 outputs=[dmg,source];manifest={'version':RELEASE,'notarized':False,'sourceArchiveIncludesVendorPixelmator':False,'files':{p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in outputs}}
 (distribution/'release-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 shutil.copy2(ROOT/'Build/build-manifest.json',distribution/'build-manifest.json')
 (distribution/'SHA256SUMS.txt').write_text(''.join(manifest['files'][p.name]['sha256']+'  '+p.name+'\n' for p in outputs))
 print(json.dumps(manifest,indent=2))
if __name__=='__main__':package()
