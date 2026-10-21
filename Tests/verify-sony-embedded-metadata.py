"""Optional read-only source check for future camera-embedded correction support.

This verifies original grouped tables, not a correction or coordinate algorithm.
Only the pinned public RAW files are read. No photo, path, GPS or serial is output.
"""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'Tests/Fixtures/Sony-embedded-metadata.json'


def main():
    fixture = json.loads(FIXTURE.read_text())
    checked, missing = [], []
    for item in fixture['files']:
        raw = ROOT / 'Tests/PrivateRAW' / item['file']
        if not raw.exists():
            missing.append(item['file'])
            continue
        digest = hashlib.sha256(raw.read_bytes()).hexdigest()
        assert digest == item['sha256'], 'Public RAW checksum mismatch'
        expected = item['expectedGroupedFields']
        keys = sorted(set(expected) | {
            f'{group}:{kind}CorrParams'
            for group in ['SubIFD', 'Sony']
            for kind in ['Distortion', 'ChromaticAberration', 'Vignetting']
        })
        command = ['/usr/bin/perl', str(ROOT / 'Resources/LensBridge/exiftool/exiftool'),
                   '-j', '-G1', '-a', '-n', *['-' + key for key in keys], str(raw)]
        rows = json.loads(subprocess.check_output(command))
        assert len(rows) == 1
        actual = rows[0]
        actual.pop('SourceFile', None)
        assert actual == expected, 'Grouped calibration-source fields changed'
        tables = {name: [int(x) for x in actual[f'SubIFD:{name}CorrParams'].split()]
                  for name in ['Distortion', 'ChromaticAberration', 'Vignetting']
                  if f'SubIFD:{name}CorrParams' in actual}
        assert len(tables) in [0, 3], 'Incomplete table set needs separate validation'
        if tables:
            n = tables['Distortion'][0]
            assert 2 <= n <= 16
            for name, values in tables.items():
                count = 2 * n if name == 'ChromaticAberration' else n
                assert values[0] == count and len(values) > count
                assert all(-32768 <= value <= 32767 for value in values[1:count + 1])
                assert all(value == 0 for value in values[count + 1:])
        assert hashlib.sha256(raw.read_bytes()).hexdigest() == digest
        checked.append({
            'fixture': item, 'originalUnchanged': True,
            'completeSubIFDTableSetPresent': bool(tables),
            'recordedKnotCount': tables['Distortion'][0] if tables else None,
            'sourceFramePixels': [actual['SubIFD:ImageWidth'], actual['SubIFD:ImageHeight']],
            'makerNoteAndSubIFDValuesMustNotBeFlattened': bool(tables),
            'tablesAppliedToPixels': False, 'addedAutomaticCoverageClaim': False,
        })
    report = {
        'scope': fixture['scope'], 'verified': checked, 'missingFiles': missing,
        'fixtureSHA256': hashlib.sha256(FIXTURE.read_bytes()).hexdigest(),
        'readerSHA256': hashlib.sha256((ROOT / 'Resources/LensBridge/exiftool/exiftool').read_bytes()).hexdigest(),
        'pending': ['pixel-frame and active-area alignment', 'coefficient interpretation and independent numerical oracle',
                    'linear-light vignette response', 'native-priority routing and saved editable effects',
                    'real optical and host render acceptance'],
    }
    output = ROOT / 'Build/Tests/sony-embedded-source-verification.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f'Sony embedded metadata: {len(checked)} pinned RAW verified, {len(missing)} optional absent; tables not applied.')


if __name__ == '__main__':
    main()
