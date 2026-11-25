"""Read-only, independent audit of a locally GUI-saved Sony v6 PXD.

No Pixelmator runtime or RAW redistribution is required. The named RAW and PXD
stay local; the report includes hashes and selected settings, never pixels.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import plistlib
import sqlite3
import tempfile
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def filter_archives(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == 'CIFilterNSCodingData':
                yield plistlib.loads(base64.b64decode(child, validate=True))
            else:
                yield from filter_archives(child)
    elif isinstance(value, list):
        for child in value:
            yield from filter_archives(child)


def decode_profile(archive):
    objects = archive['$objects']

    def decode(value, depth=0):
        if depth > 64:
            raise ValueError('Archive nesting exceeds audit limit.')
        if isinstance(value, plistlib.UID):
            return decode(objects[value.data], depth+1)
        if isinstance(value, dict):
            if 'NS.keys' in value:
                keys, values = value['NS.keys'], value['NS.objects']
                if len(keys) != len(values):
                    raise ValueError('Malformed dictionary archive.')
                return {decode(k, depth+1): decode(v, depth+1) for k, v in zip(keys, values)}
            if 'NS.objects' in value:
                return [decode(v, depth+1) for v in value['NS.objects']]
            if 'NS.string' in value:
                return decode(value['NS.string'], depth+1)
            if 'NS.data' in value:
                return decode(value['NS.data'], depth+1)
            return {k: decode(v, depth+1) for k, v in value.items() if k != '$class'}
        if isinstance(value, list):
            return [decode(v, depth+1) for v in value]
        return value

    found = [decode(v['LensBridgeVignettingProfile']) for v in objects
             if isinstance(v, dict) and 'LensBridgeVignettingProfile' in v]
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pxd', type=Path)
    parser.add_argument('raw', type=Path)
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    raw_sha = sha(args.raw.read_bytes())
    with zipfile.ZipFile(args.pxd) as document, tempfile.TemporaryDirectory() as temporary:
        if document.testzip() is not None:
            raise ValueError('PXD member CRC failure.')
        raw_members = [name for name in document.namelist() if name.endswith('-OriginalContentSource')]
        if len(raw_members) != 1 or sha(document.read(raw_members[0])) != raw_sha:
            raise ValueError('Saved original RAW differs from the supplied original.')
        metadata = Path(temporary)/'metadata.info'
        metadata.write_bytes(document.read('metadata.info'))
        connection = sqlite3.connect(metadata.as_uri()+'?mode=ro', uri=True)
        try:
            rows = connection.execute("SELECT value FROM layer_info WHERE key='effects-data'").fetchall()
            profiles = [p for row in rows for archive in filter_archives(json.loads(row[0]))
                        for p in decode_profile(archive)]
        finally:
            connection.close()
    if len(profiles) != 1:
        raise ValueError('Expected exactly one saved LensDock effect.')
    profile = profiles[0]
    matched = profile['matchedProfile']
    source = matched['explicitGeometry']['source']
    settings = profile['correctionSettings']
    checks = {
        'explicitV6': profile.get('profileFormatVersion') == 6 and profile.get('workingTransfer') == 'lensdock-explicit-v6',
        'sourceBoundToOriginalRAW': profile['sourceBinding']['sourceInformation']['rawSHA256'] == raw_sha,
        'explicitSonyProvider': matched.get('geometryProvider') == 'sony-explicit-frame-v1',
        'decodedFrameConvention': matched.get('frameConvention') == 'recorded-full-image-aligned-decoder-v1',
        'manufacturerProofNotClaimed': matched.get('manufacturerFrameProven') is False and source.get('pixelFrameVerified') is False,
        'savedSourceEqualsReadMetadata': source == profile['metadata']['embeddedLensCorrectionSource'],
        'noManualCatalogueSelection': not profile['metadata'].get('LensDockProfileSelection'),
        'noGeneratedGainOrMaps': not profile.get('linearGainFloat32BottomUp') and not profile.get('normalizedGeometryMapsLZFSE') and not profile.get('geometryResidualMapsLZFSE'),
        'vignetteOff': not settings['vignettingEnabled'] and settings['vignettingStrength'] == 0,
        'nativeGeometryOff': not profile['sourceBinding']['rawParameters'][1]['lc'],
    }
    report = {
        'scope': 'Actual GUI-saved PXD readback with an independent archive decoder. Not optical proof or cross-camera coverage.',
        'pxdSHA256': sha(args.pxd.read_bytes()), 'pxdBytes': args.pxd.stat().st_size,
        'originalRAWSHA256': raw_sha, 'checks': checks, 'settings': settings,
        'width': profile['width'], 'height': profile['height'],
        'frame': matched['explicitGeometry']['frame'], 'constrainedCrop': profile.get('constrainedCrop'),
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    if not all(checks.values()):
        raise SystemExit('Saved document audit failed: '+', '.join(k for k,v in checks.items() if not v))
    print('Saved Sony v6 PXD: original RAW unchanged, source and independent choices retained.')


if __name__ == '__main__':
    main()
