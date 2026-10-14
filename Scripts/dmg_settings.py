from pathlib import Path
format='UDRW'
filesystem='HFS+'
stage=Path(defines['stage'])
files=[str(stage/'LensDock.app'),str(stage/'说明与源码')]
symlinks={'Applications':'/Applications'}
background=defines['background']
window_rect=((120,120),(760,512))
default_view='icon-view'
show_toolbar=False
show_status_bar=False
show_sidebar=False
show_pathbar=False
include_icon_view_settings=True
icon_size=96
text_size=14
icon_locations={'LensDock.app':(203,243),'Applications':(557,243),'说明与源码':(666,390)}
