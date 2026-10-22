"""Generate a synthetic mathematical oracle, never a manufacturer's frame.

Decimal square roots and explicit EXIF orientation matrices form expected
display/source point pairs from canonical coordinates. The native operator
instead receives displayed points and must invert the frame to evaluate them.
"""
from decimal import Decimal as D, getcontext
from pathlib import Path
import hashlib
import json

getcontext().prec = 60
ROOT = Path(__file__).resolve().parents[1]
FRAMES = [
    {'calibrationSize': [120, 160], 'decodedRegion': [0, 0, 120, 160], 'unrotatedOutputSize': [90, 80]},
    {'calibrationSize': [120, 160], 'decodedRegion': [12, 20, 96, 120], 'unrotatedOutputSize': [72, 90]},
    {'calibrationSize': [6024, 4024], 'decodedRegion': [12, 12, 6000, 4000], 'unrotatedOutputSize': [1500, 1000]},
]
TABLES = {'Distortion': {'nodeCount': 4, 'values': [0, 2048, 4096, 8192]},
          'ChromaticAberration': {'nodeCount': 4, 'red': [-16384, -8192, 0, 8192], 'blue': [32767, 16384, 8192, 0]}}


def main():
    cases = []
    for index, frame in enumerate(FRAMES):
        cw, ch = map(D, frame['calibrationSize'])
        x, y, w, h = map(D, frame['decodedRegion'])
        ow, oh = map(D, frame['unrotatedOutputSize'])
        center = [cw / 2, ch / 2]
        diagonal = (center[0] ** 2 + center[1] ** 2).sqrt()
        # Published EXIF orientation relationships expressed as affine rows.
        matrices = [((1, 0, 0), (0, 1, 0)), ((-1, 0, w), (0, 1, 0)),
                    ((-1, 0, w), (0, -1, h)), ((1, 0, 0), (0, -1, h)),
                    ((0, 1, 0), (1, 0, 0)), ((0, -1, h), (1, 0, 0)),
                    ((0, -1, h), (-1, 0, w)), ((0, 1, 0), (-1, 0, w))]
        for orientation, matrix in enumerate(matrices, 1):
            swapped = orientation >= 5
            scale = [oh / h, ow / w] if swapped else [ow / w, oh / h]

            def display(point):
                local = [point[0] - x, point[1] - y, D(1)]
                return [sum(D(a) * b for a, b in zip(row, local)) * scale[i] for i, row in enumerate(matrix)]

            for local in [(D('.5'), D('.5')), (w - D('.5'), h - D('.5')), (w / 2, h / 2), (w * D('.3'), h * D('.7'))]:
                point = [x + local[0], y + local[1]]
                delta = [point[i] - center[i] for i in range(2)]
                radius = (delta[0] ** 2 + delta[1] ** 2).sqrt() / diagonal

                def code(values):
                    position = min(D(3), max(D(0), radius * 3 - D('.5')))
                    left = min(2, int(position))
                    fraction = position - left
                    return D(values[left]) * (1 - fraction) + D(values[left + 1]) * fraction

                for ds, ts in [(0, 0), (1, 0), (0, 1), (1, 1), (D('.5'), D('1.5')), (2, 2), (D('1.25'), D('.75'))]:
                    for channel in range(3):
                        factor = (1 + D(ds) * code(TABLES['Distortion']['values']) / 16384)
                        if channel != 1:
                            factor *= 1 + D(ts) * code(TABLES['ChromaticAberration']['red' if channel == 0 else 'blue']) / 2097152
                        mapped = [center[i] + delta[i] * factor for i in range(2)]
                        cases.append([index, orientation, channel, float(ds), float(ts), *map(float, display(point)), *map(float, display(mapped))])
    out = ROOT / 'Tests/Fixtures/Sony-pixel-frame-reference.json'
    header = {'scope': 'Synthetic 60-digit Decimal reference only; explicit coordinate contracts, not Sony optical or manufacturer-frame evidence.',
              'generatorSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'frames': FRAMES,
              'source': {'provider': 'sony-subifd-radial-source-v1', 'tables': TABLES},
              'caseColumns': ['frame', 'orientation', 'channel', 'distortionStrength', 'tcaStrength', 'displayX', 'displayY', 'expectedSourceDisplayX', 'expectedSourceDisplayY']}
    # Keep cases one-per-line for readable reviews and deterministic regeneration.
    prefix = json.dumps(header, indent=2)[:-2]
    out.write_text(prefix + ',\n  "cases": [\n' + ',\n'.join('    ' + json.dumps(row) for row in cases) + '\n  ]\n}\n')
    print(f'Wrote {len(cases)} synthetic frame/orientation reference points.')


if __name__ == '__main__':
    main()
