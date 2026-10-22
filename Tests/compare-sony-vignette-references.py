"""Compile pinned, local upstream snippets into ignored developer-only oracles.

This distinguishes darktable's legacy v1 and current v2 response. It does not
choose a product curve or establish optical correctness. No download, product
linkage, RAW read or image output occurs. Keep extracted GPL snippets in Build/.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Build/Development/sony-vignette-oracles'
REFERENCES = {
    'rawtherapee': ('8db8986eb6df164c1a47e27696dee1c37195bd97132b40d796e159cd90f40e93',
                   'https://github.com/RawTherapee/RawTherapee/blob/7deb2754d1f31beff891063b476905d4093e8570/rtengine/lensmetadata.cc'),
    'darktable46': ('5da8f95bca20b4ff1ea56e163de022c2e5716fe72a618a5effc69ba2f770b30f',
                   'https://github.com/darktable-org/darktable/blob/release-4.6.0/src/iop/lens.cc'),
    'darktableCurrent': (None,
                        'https://github.com/darktable-org/darktable/blob/4769e85ed227f35112a75b1f1c18fb2067c337cc/src/iop/lens.cc'),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def block(text, anchor):
    """Extract braces in these hash-pinned functions, not arbitrary C++ parsing."""
    start = text.index(anchor)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rawtherapee', type=Path, default=ROOT / 'Build/Development/sony-rt-current.cc')
    parser.add_argument('--darktable46', type=Path, default=ROOT / 'Build/Development/sony-dt46-lens.cc')
    parser.add_argument('--darktable-current', type=Path, default=ROOT / 'Build/Development/sony-dt-current-lens.cc')
    args = parser.parse_args()
    paths = {'rawtherapee': args.rawtherapee, 'darktable46': args.darktable46, 'darktableCurrent': args.darktable_current}
    # Git blob SHA for the optional current snapshot is separately pinned.
    for name, path in paths.items():
        if not path.is_file():
            raise SystemExit(f'Missing local {name} reference; use the pinned URL documented in this script.')
        expected = REFERENCES[name][0]
        if expected and digest(path) != expected:
            raise SystemExit(f'{name} reference checksum mismatch')
        if name == 'darktableCurrent':
            blob = path.read_bytes()
            blob_sha = hashlib.sha1(b'blob ' + str(len(blob)).encode() + b'\0' + blob).hexdigest()
            if blob_sha != '43ca324be940c8b906ecd6d151d5b367b811ed2d':
                raise SystemExit('Current darktable pinned blob mismatch')
    OUT.mkdir(parents=True, exist_ok=True)
    common = '#include <array>\n#include <vector>\n#include <cmath>\n#include <iostream>\n#include <iomanip>\n'
    rt = paths['rawtherapee'].read_text()
    sony = rt[rt.index('class SonyMetadataLensCorrection'):rt.index('class FujiMetadataLensCorrection')]
    setup = block(sony, 'void setup()')
    factor = block(sony, 'double vignettingCorrectionFactor').replace(' override', '')
    sources = {'rt': rt[:rt.index('*/') + 2] + '\n' + common + block(rt, 'double interpolateLinearSpline') + '''
struct Oracle { int nc; std::array<short,16> distortion{},ca_r{},ca_b{},vignetting{};
std::vector<double> knots,dist,vig; std::array<std::vector<double>,3> ca;
''' + setup + '\n' + factor + '''
};
int main(){Oracle o;std::cin>>o.nc;for(int i=0;i<o.nc;i++)std::cin>>o.vignetting[i];o.setup();
int count;std::cin>>count;std::cout<<std::setprecision(17);while(count--){double r;std::cin>>r;std::cout<<o.vignettingCorrectionFactor(r)<<"\\n";}}
'''}
    for name, version, key in [('dt46v1', 1, 'darktable46'), ('dt46v2', 2, 'darktable46'), ('dtCurrentV2', 2, 'darktableCurrent')]:
        dt = paths[key].read_text()
        function = block(dt, f'static int _init_coeffs_md_v{version}(')
        branch = block(function, 'if(img->exif_correction_type == CORRECTION_TYPE_SONY)')
        sources[name] = dt[:dt.index('*/') + 2] + '\n' + common + '''
#define CORRECTION_TYPE_SONY 1
#define DT_IOP_LENS_MODIFY_FLAG_DISTORTION 1
#define DT_IOP_LENS_MODIFY_FLAG_TCA 2
#define DT_IOP_LENS_MODIFY_FLAG_VIGNETTING 4
struct Sony{int nc;short distortion[16]{},ca_r[16]{},ca_b[16]{},vignetting[16]{};};
struct Correction{Sony sony;};struct Image{int exif_correction_type;Correction exif_correction_data;};
struct Params{int modify_flags;float cor_dist_ft,cor_vig_ft,cor_ca_r_ft,cor_ca_b_ft;};
''' + block(dt, 'static inline float _interpolate_linear_spline(') + '''
int setup(Image*img, Params*p, float*knots_dist, float*knots_vig,float cor_rgb[3][16],float*vig){
const Correction*cd=&img->exif_correction_data;int nc=0;float scale=1;
''' + branch + '\nreturn nc;}\n' + '''
int main(){Image im;im.exif_correction_type=1;auto&o=im.exif_correction_data.sony;std::cin>>o.nc;
for(int i=0;i<o.nc;i++)std::cin>>o.vignetting[i];float kd[16],kv[16],rgb[3][16],v[16];
Params p{4,1,1,1,1};setup(&im,&p,kd,kv,rgb,v);int count;std::cin>>count;std::cout<<std::setprecision(17);
while(count--){float r;std::cin>>r;std::cout<<1.f/_interpolate_linear_spline(kv,v,o.nc,r)<<"\\n";}}
'''
    for name, content in sources.items():
        path = OUT / f'{name}.cc'
        path.write_text(content)
        subprocess.run(['xcrun', 'clang++', '-std=c++17', '-O2', str(path), '-o', str(OUT / name)], check=True, timeout=60)

    fixture = json.loads((ROOT / 'Tests/Fixtures/Sony-embedded-metadata.json').read_text())['files'][0]
    words = [int(x) for x in fixture['expectedGroupedFields']['SubIFD:VignettingCorrParams'].split()]
    profiles = {'A6000Recorded': words[1:1 + words[0]], 'zero2': [0, 0], 'zero16': [0] * 16,
                'constantPositive': [8192] * 4, 'constantNegative': [-8192] * 4}
    summaries, failures = [], []
    for name, values in profiles.items():
        n = len(values)
        knots = [(i + .5) / (n - 1) for i in range(n)]
        radii = sorted(set([i / 256 for i in range(257)] + knots + [(a + b) / 2 for a, b in zip(knots, knots[1:])] + [1.5]))
        data = f'{n}\n' + ' '.join(map(str, values)) + f'\n{len(radii)}\n' + '\n'.join(map(str, radii)) + '\n'
        results = {key: [float(x) for x in subprocess.check_output([str(OUT / key)], input=data, text=True, timeout=30).split()] for key in sources}
        for key, numbers in results.items():
            if len(numbers) != len(radii) or any(not math.isfinite(x) or x <= 0 for x in numbers):
                raise SystemExit(f'{name}/{key}: malformed oracle output')
        # Independent double-precision mathematical reconstruction. RT
        # interpolates inverse transmission; DT interpolates transmission then
        # inverts. Legacy DT first squares transmission at the knots.
        transmission = [2 ** (.5 - 2 ** (code / 8192 - 1)) for code in values]

        def interpolate(nodes, radius):
            position = min(n - 1, max(0, radius * (n - 1) - .5))
            index = min(n - 2, int(position))
            fraction = position - index
            return nodes[index] * (1 - fraction) + nodes[index + 1] * fraction

        expected = {'rt': [interpolate([1 / x for x in transmission], r) for r in radii],
                    'dt46v1': [1 / interpolate([x * x for x in transmission], r) for r in radii],
                    'dt46v2': [1 / interpolate(transmission, r) for r in radii],
                    'dtCurrentV2': [1 / interpolate(transmission, r) for r in radii]}
        for key, numbers in results.items():
            if any(abs(a - b) > 1e-6 * max(1, abs(b)) for a, b in zip(numbers, expected[key])):
                failures.append(f'{name}/{key}: independent formula mismatch')
            if name.startswith('zero') and any(x != 1 for x in numbers):
                failures.append(f'{name}/{key}: zero table not identity')
        if results['dt46v2'] != results['dtCurrentV2']:
            failures.append(f'{name}: pinned 4.6/current vignette response changed')
        summaries.append({'profile': name, 'nodeCount': n, 'sampleCount': len(radii),
                          'maximumRTVsV2GainDifference': max(abs(a - b) for a, b in zip(results['rt'], results['dt46v2'])),
                          'samples': [{'radius': r, **{key: numbers[radii.index(r)] for key, numbers in results.items()}} for r in [0, .25, .5, .75, 1]],
                          'maximumIndependentFormulaError': {key: max(abs(a - b) for a, b in zip(numbers, expected[key])) for key, numbers in results.items()}})
    report = {
        'scope': 'Coordinate-free upstream response comparison. Corrects the earlier legacy-v1-as-default interpretation; not manufacturer calibration, physical accuracy, source frame or product enablement.',
        'references': {name: {'url': REFERENCES[name][1], 'fileSHA256': digest(path)} for name, path in paths.items()},
        'driverSHA256': digest(Path(__file__)), 'oracleSourceSHA256': {name: digest(OUT / f'{name}.cc') for name in sources},
        'darktable46DefaultUsesV2': 'src/iop/lens.cc:3573; reload_defaults assigns VERSION_2 for available embedded metadata. Preserved v1 remains selectable for old edits.',
        'geometryAutoscaleExcluded': 'Vignette-only scalar response; source v2 automatic scaling changes only distortion knots/RGB arrays, not vignette knots/values.',
        'samples': summaries, 'failures': failures,
        'oldEvidenceCorrection': 'Evidence/sony-radial-upstream-oracle-verification.json darktable46 compiled _init_coeffs_md_v1. Its numeric results are legacy v1, not the 4.6 default v2.',
        'referenceGPLCodeIncludedInProduct': False, 'manufacturerVignetteRenderingEnabled': False,
    }
    (OUT / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Sony vignette references: {len(profiles)} tables, {sum(x["sampleCount"] for x in summaries)} radii per reference, {len(failures)} failures. Product rendering remains disabled.')
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
