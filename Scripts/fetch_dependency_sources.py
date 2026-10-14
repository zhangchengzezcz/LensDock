"""Fetch corresponding upstream sources; verify pinned SHA256 before packaging."""
from pathlib import Path
import hashlib,json,urllib.request,concurrent.futures
ROOT=Path(__file__).resolve().parents[1]
PACKAGES=[
 ('lensfun-0.3.4.tar.gz', 'https://codeload.github.com/lensfun/lensfun/tar.gz/101c745e847a5de4a1e569a94368ce2027198598', 'a11cbe6aeec657839540448b253217c25d20b7a45b6aebfef406f7239933c7a6'),
 ('glib-2.79.1.tar.xz','https://download.gnome.org/sources/glib/2.79/glib-2.79.1.tar.xz','b3764dd6e29b664085921dd4dd6ba2430fc19760ab6857ecfa3ebd4e8c1d114c'),
 ('gettext-0.22.4.tar.xz','https://ftp.gnu.org/gnu/gettext/gettext-0.22.4.tar.xz','29217f1816ee2e777fa9a01f9956a14139c0c23cc1b20368f06b2888e8a34116'),
 ('pcre2-10.47.tar.gz','https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.47/pcre2-10.47.tar.gz','c08ae2388ef333e8403e670ad70c0a11f1eed021fd88308d7e02f596fcd9dc16'),
]
def fetch(package):
 name,url,digest=package;path=ROOT/'Vendor/Sources'/name
 data=path.read_bytes() if path.exists() else urllib.request.urlopen(url,timeout=60).read()
 if hashlib.sha256(data).hexdigest()!=digest:raise ValueError('SHA256 mismatch: '+name)
 path.write_bytes(data);return dict(name=name,url=url,sha256=digest,bytes=len(data))
if __name__=='__main__':
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(fetch,PACKAGES))
 (ROOT/'Vendor/Sources/upstream-manifest.json').write_text(json.dumps(results,indent=2)+'\n')
 print('Verified',len(results),'dependency source archives')
