# Third-party provenance and licenses

LensDock's own implementation is MIT. Dependencies retain the following terms.

| Component | Version / source | License |
| --- | --- | --- |
| Lensfun C library and header | 0.3.4 / commit 101c745e847a5de4a1e569a94368ce2027198598 | LGPL-3.0-or-later; GPL and LGPL texts included |
| Lensfun database | Public version_1 DB at commit 43f9e001ab66c4fcdd4f400463f13b72f94b2288 | CC BY-SA 3.0; attribution preserved in each XML |
| GLib | 2.79.1 | LGPL-2.1-or-later; SPDX license texts included |
| gettext libintl | 0.22.4 | LGPL-2.1-or-later; gettext-runtime/intl/COPYING.LIB included |
| PCRE2 | 10.47 | BSD license and bundled notices in PCRE2-LICENCE.md |
| ExifTool | 13.59 / Phil Harvey, https://exiftool.org/ | Same terms as Perl; runtime source included; GPL and Artistic texts included |
| lensfunpy upstream build recipe | v1.18.0 / https://github.com/letmaik/lensfunpy | MIT; recipe and license included |

Native dependency binaries were extracted from the official PyPI lensfunpy 1.18.0 macOS arm64 wheel. LensDock does not import the Python wrapper. The upstream macOS build recipe identifies the dependency versions and source archive SHA256; GLib and PCRE2 runtime versions were independently checked. Runtime library references use @loader_path. System frameworks and system libiconv/libc++/libSystem are provided by macOS and are not distributed.

Corresponding source archives for LGPL dynamic libraries, PCRE2 and the upstream build recipe are included in `Sources/`; archive checksums are in `Sources/upstream-manifest.json`. The DMG includes a complete source ZIP (with these archives, module sources, build scripts, resources and compatibility manifest) beside the installer inside `说明与源码`, so recipients receive corresponding sources without needing access to a private repository. ExifTool's Perl source is inside the installer payload and the repository's Resources. Library internals have not been modified; copies are re-signed ad-hoc when building/installing. Recipients may replace/rebuild the independent libraries and native modules using the supplied source and build script. Libraries are dynamically loaded, not statically linked into the native module.

The database XML files are redistributed unmodified from the recorded public DB; identity alias handling is in LensDock code. LensDock's tests create clearly labelled temporary test databases and never install them as real lens profiles. No vendor Pixelmator app or framework is included in this repository or DMG; users supply their own local compatible licensed installation.
