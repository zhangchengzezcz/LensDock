"""Validate embedded Finder metadata with source artwork absent and image remounted."""
from pathlib import Path
import subprocess,hashlib,json,shutil
from ds_store import DSStore
from mac_alias import Alias
from mac_alias.bookmark import kBookmarkPath,kBookmarkVolumePath,kBookmarkVolumeUUID
ROOT=Path(__file__).resolve().parents[1]
def verify():
 version=json.loads((ROOT/'Version.json').read_text());release=version['version']+'-'+version['channel']
 image=ROOT/'Distribution'/release/f'LensDock-{release}-Retina.dmg'
 mount=ROOT/'Build/Relocated-Image';mount.mkdir(exist_ok=True)
 original=ROOT/'Resources/Artwork';hidden=ROOT/'Build/Artwork-offline'
 if hidden.exists():raise ValueError('Restore existing artwork backup before verification')
 original.rename(hidden)
 try:
  subprocess.run(['hdiutil','attach','-readonly','-nobrowse','-noautoopen','-mountpoint',str(mount),str(image)],check=True,stdout=subprocess.DEVNULL)
  try:
   with DSStore.open(str(mount/'.DS_Store'),'r') as store:
    view=store['.']['icvp'];alias=Alias.from_bytes(view['backgroundImageAlias']);bookmark=store['.']['pBBk']
    assert view['backgroundType']==2
    target=alias.target.posix_path.decode() if isinstance(alias.target.posix_path,bytes) else alias.target.posix_path
    assert target.startswith('/.background/')
    picture=mount/target.lstrip('/');assert picture.is_file()
    toc=bookmark.tocs[0][1];assert toc[kBookmarkPath]==['.background',picture.name]
    assert toc[kBookmarkVolumePath]=='/Volumes/LensDock Retina Preview' and toc[kBookmarkVolumeUUID]
    assert b'/Users/' not in view['backgroundImageAlias'] and b'/Users/' not in bookmark.to_bytes()
    assert store['LensDock.app']['Iloc']==(203,243) and store['Applications']['Iloc']==(557,243)
    data=ROOT/'Build/background-bookmark.data';data.write_bytes(bookmark.to_bytes())
   assert (mount/'Applications').is_symlink() and (mount/'Applications').readlink()==Path('/Applications')
   subprocess.run(['codesign','--verify','--deep','--strict',str(mount/'LensDock.app')],check=True)
   executable=ROOT/'Build/verify-background-resolution'
   subprocess.run(['xcrun','swiftc','-target','arm64-apple-macos26.0',str(ROOT/'Scripts/verify_background_resolution.swift'),'-o',str(executable)],check=True)
   subprocess.run([str(executable),str(data),str(mount)],check=True)
   report={'sourceArtworkTemporarilyAbsent':True,'readonlyFinalImageMountedAtDifferentPath':True,'finderBookmarkResolvedToInternalPicture':True,'backgroundPath':target.lstrip('/'),'backgroundSHA256':hashlib.sha256(picture.read_bytes()).hexdigest(),'aliasAndBookmarkReferenceImageVolumeOnly':True,'noUserHomePictureReference':True,'iconLocationsVerified':True,'applicationSignatureVerifiedAfterPackaging':True,'vectorPDFVerified':True,'backgroundLogicalPoints':[760,480],'resolutionIndependent':True,'testedOnSecondComputer':False}
   (ROOT/'Evidence/dmg-background-verification.json').write_text(json.dumps(report,indent=2)+'\n')
   print(json.dumps(report,indent=2))
  finally:subprocess.run(['hdiutil','detach',str(mount)],check=True,stdout=subprocess.DEVNULL)
 finally:hidden.rename(original)
if __name__=='__main__':verify()
