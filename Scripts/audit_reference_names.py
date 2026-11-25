"""Optional developer-only name inventory of a local Lightroom profile corpus.

Never copies calibration coefficients or adds a Lightroom runtime dependency.
An exact name overlap is not a support/optical-equivalence measurement.
"""
from pathlib import Path
import argparse
from collections import Counter
import hashlib
import json
import math
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def normal(value):
    return re.sub('[^a-z0-9]', '', value.lower())


def fields(tree, wanted):
    found = {key: set() for key in wanted}
    for node in tree.iter():
        key = node.tag.rsplit('}', 1)[-1]
        if key in found and node.text and node.text.strip():
            found[key].add(node.text.strip())
        for name, value in node.attrib.items():
            key = name.rsplit('}', 1)[-1]
            if key in found:
                found[key].add(value.strip())
    return found


def match_request(values):
    if {flag.lower() for flag in values['CameraRawProfile']} != {'true'}:
        return None, 'notExplicitlyRAW'
    if any(len(values[key]) != 1 for key in ('Make', 'Model', 'Lens')):
        return None, 'missingOrInconsistentIdentity'
    focal_lengths = []
    for value in values['FocalLength']:
        try:
            focal = float(value)
        except ValueError:
            continue
        if math.isfinite(focal) and focal > 0:
            focal_lengths.append(focal)
    if not focal_lengths:
        return None, 'noFocalLengthWitness'
    focal_lengths = sorted(set(focal_lengths))
    return {'Make': next(iter(values['Make'])), 'Model': next(iter(values['Model'])),
            'LensModel': next(iter(values['Lens'])), 'FocalLength': focal_lengths[len(focal_lengths)//2]}, None


def production_matching(requests, skipped):
    native = ROOT/'Sources/Native'
    with tempfile.TemporaryDirectory(prefix='lensdock-reference-audit-') as work:
        executable = Path(work)/'audit-reference-metadata'
        subprocess.run([
            'xcrun', 'clang', '-O2', '-fobjc-arc', '-arch', 'arm64', '-mmacosx-version-min=26.0',
            '-I', str(native), '-framework', 'Cocoa', '-framework', 'ImageIO', '-framework', 'CoreImage',
            str(ROOT/'Tests/audit_reference_metadata.m'), str(native/'LensNativeProfileEngine.m'),
            '-o', str(executable),
        ], cwd=ROOT, check=True)
        counts = json.loads(subprocess.check_output([str(executable)], input=json.dumps(requests), text=True, cwd=ROOT))
    return {
        'scope': 'Production Lensfun plan using one focal length per eligible reference LCP file and its exact recorded Make, Model and Lens. No aperture, MakerNotes, Apple native probe, optical equivalence or real RAW test.',
        'filesTested': len(requests),
        'filesSkippedByReason': dict(skipped),
        **counts,
    }


def audit(reference, output, run_matching=False):
    exact_names = set()
    database_sources, cameras, lenses = [], 0, 0
    for file in sorted((ROOT/'Resources/LensBridge/db').glob('*.xml')):
        content = file.read_bytes()
        tree = ET.fromstring(content)
        database_sources.append([file.name, hashlib.sha256(content).hexdigest()])
        cameras += len(tree.findall('camera'))
        for lens in tree.findall('lens'):
            lenses += 1
            makers = [n.text for n in lens.findall('maker') if not n.attrib.get('lang') and n.text]
            for node in lens.findall('model'):
                if node.attrib.get('lang') or not node.text:
                    continue
                exact_names.add(normal(node.text))
                exact_names.update(normal(maker+node.text) for maker in makers)
    files = sorted(p for p in reference.rglob('*') if p.is_file() and p.suffix.lower() == '.lcp')
    if not files:
        raise ValueError('No LCP files found in the optional local reference directory')
    names, flags, makers, source_hashes, failures = set(), Counter(), Counter(), [], []
    with_exact_name, without_exact_name = 0, 0
    requests, skipped = [], Counter()
    wanted = ['Lens', 'LensPrettyName', 'Make', 'CameraRawProfile']
    if run_matching:
        wanted.extend(['Model', 'FocalLength'])
    for file in files:
        data = file.read_bytes()
        source_hashes.append([str(file.relative_to(reference)), hashlib.sha256(data).hexdigest()])
        try:
            values = fields(ET.fromstring(data), wanted)
        except ET.ParseError:
            failures.append(str(file.relative_to(reference)))
            continue
        recorded = values['Lens'] | values['LensPrettyName']
        names.update(recorded)
        raw = {x.lower() for x in values['CameraRawProfile']}
        flags['true' if raw == {'true'} else 'false' if raw == {'false'} else 'unspecified-or-mixed'] += 1
        for maker in values['Make'] or {'unspecified'}:
            makers[maker] += 1
        if any(normal(name) in exact_names for name in recorded):
            with_exact_name += 1
        else:
            without_exact_name += 1
        if run_matching:
            request, reason = match_request(values)
            if request:
                requests.append(request)
            else:
                skipped[reason] += 1
    report = {
        'scope': 'Read-only local reference name/flag inventory; no calibration coefficients copied, no runtime support or optical-equivalence claim',
        'referenceLCPFiles': len(files), 'parsedFiles': len(files)-len(failures),
        'cameraRawProfileFlagFiles': dict(flags), 'distinctRecordedLensNameStrings': len(names),
        'filesWithAnExactBundledLensfunDefaultName': with_exact_name,
        'filesWithoutAnExactBundledLensfunDefaultName': without_exact_name,
        'cameraMakeFileCounts': dict(sorted(makers.items())),
        'referenceManifestSHA256': hashlib.sha256(json.dumps(source_hashes, ensure_ascii=False).encode()).hexdigest(),
        'bundledDatabase': {'cameras': cameras, 'lensRecords': lenses,
            'manifestSHA256': hashlib.sha256(json.dumps(database_sources).encode()).hexdigest()},
        'parseFailures': failures,
        'interpretation': [
            'LCP files and Lensfun records are not unique physical-lens counts.',
            'A missing exact name can be an alias difference or an Apple-native correction case.',
            'An exact name does not verify calibration range, sensor context or optical equivalence.',
            'Lightroom-equivalent automatic coverage remains unproven; verify actual RAW identities and correction behavior.',
        ],
        'adobeCalibrationCoefficientsRedistributed': False,
        'productRequiresLightroom': False,
    }
    if run_matching:
        report['productionMatching'] = production_matching(requests, skipped)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n')
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT/'Build/Audit/reference-name-inventory.json')
    parser.add_argument('--production-matching', action='store_true', help='Run the production Lensfun planner on eligible recorded camera, lens and focal-length fields')
    args = parser.parse_args()
    audit(args.reference, args.output, args.production_matching)
