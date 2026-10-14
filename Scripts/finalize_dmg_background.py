"""Store the picture inside the image and regenerate volume-relative Finder references.

Adapted workflow from the user's Planora example: editable image -> embedded
.background folder -> persisted Finder metadata -> final compressed image.
No Finder scripting and no references to a development-machine picture path.
"""
from pathlib import Path
from ds_store import DSStore
from mac_alias import Alias,Bookmark
from mac_alias.bookmark import kBookmarkPath,kBookmarkVolumePath,kBookmarkVolumeURL,kBookmarkVolumeName,URL
from urllib.parse import quote
import hashlib

def finalize(volume,volume_name):
 volume=Path(volume).resolve()
 candidates=[p for p in [volume/'.background.pdf',volume/'.background.tiff',volume/'.background.png'] if p.is_file()]
 if len(candidates)!=1:raise ValueError('Expected one embedded dmgbuild background')
 old=candidates[0];folder=volume/'.background';folder.mkdir(exist_ok=True)
 picture=folder/('installation'+old.suffix);old.rename(picture)
 alias=Alias.for_file(str(picture));bookmark=Bookmark.for_file(str(picture))
 # Preserve on-image CNIDs, volume UUID and creation dates. Target is volume-relative.
 # The canonical mount hint must never name a build directory or user home.
 canonical='/Volumes/'+volume_name
 alias.volume.posix_path=canonical
 alias.target.posix_path='/'+str(picture.relative_to(volume))
 for _,toc in bookmark.tocs:
  toc[kBookmarkVolumePath]=canonical
  toc[kBookmarkVolumeURL]=URL('file://'+quote(canonical,safe='/'))
  if toc[kBookmarkVolumeName]!=volume_name:raise ValueError('Background belongs to wrong volume')
  if toc[kBookmarkPath]!=['.background',picture.name]:raise ValueError('Background target is not inside image')
 with DSStore.open(str(volume/'.DS_Store'),'r+') as store:
  view=store['.']['icvp'];view['backgroundType']=2;view['backgroundImageAlias']=alias.to_bytes();store['.']['icvp']=view;store['.']['pBBk']=bookmark
 return dict(backgroundPath=str(picture.relative_to(volume)),sha256=hashlib.sha256(picture.read_bytes()).hexdigest(),aliasVolumeName=alias.volume.name.decode("utf-8") if isinstance(alias.volume.name,bytes) else alias.volume.name,aliasTarget=alias.target.posix_path,bookmarkPath=['.background',picture.name],externalPicturePathUsed=False)
