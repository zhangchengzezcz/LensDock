"""Optional developer-only image registration; not a manufacturer's frame proof.

Needs macOS Vision/Core Image and rawpy, numpy, Pillow in a developer venv.
Reads only the pinned public A6000 RAW. All images stay in ignored Build/.
No decoder, image or profile is added to the product runtime by this script.
"""
from pathlib import Path
import hashlib
import json
import math
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Build/Development/sony-decoder-frame'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    import numpy as np
    import rawpy
    from PIL import Image, __version__ as pillow_version

    fixture_path = ROOT / 'Tests/Fixtures/Sony-embedded-metadata.json'
    fixture = next(x for x in json.loads(fixture_path.read_text())['files'] if x['file'] == 'ILCE-6000.ARW')
    source = ROOT / 'Tests/PrivateRAW' / fixture['file']
    if not source.is_file():
        raise SystemExit('Optional pinned A6000 RAW is absent; no frame evidence generated.')
    if digest(source) != fixture['sha256']:
        raise SystemExit('Pinned public RAW checksum mismatch.')
    OUT.mkdir(parents=True, exist_ok=True)
    swift = ROOT / 'Tests/observe-decoder-frame.swift'
    helper = OUT / 'observe-decoder-frame'
    subprocess.run(['xcrun', 'swiftc', '-O', '-target', 'arm64-apple-macos26.0', str(swift), '-o', str(helper)], check=True, timeout=60)

    def observe(*args):
        return json.loads(subprocess.check_output([str(helper), *map(str, args)], timeout=60))

    with rawpy.imread(str(source)) as raw:
        sizes = raw.sizes._asdict()
        rgb = raw.postprocess(user_flip=0, use_camera_wb=True, no_auto_bright=True,
                              output_bps=16, gamma=(1, 1))
    if rgb.shape[:2] != (4024, 6024):
        raise SystemExit('LibRaw visible frame changed; inspect before using existing candidates.')
    # Match the transfer function only. Tone/color differences remain; Vision
    # compares spatial content rather than assuming equal decoded RGB values.
    linear = rgb.astype(np.float32) / 65535
    srgb = np.where(linear <= .0031308, linear * 12.92, 1.055 * np.power(linear, 1 / 2.4) - .055)
    decoded = Image.fromarray(np.rint(np.clip(srgb, 0, 1) * 255).astype(np.uint8))
    del rgb, linear, srgb
    records = []
    failures = []

    def require(condition, message):
        if not condition:
            failures.append(message)

    for scale in [.25, .5]:
        label = 'quarter' if scale == .25 else 'half'
        target = OUT / f'coreimage-{label}.png'
        ci = observe('render', source, target, scale)
        require(ci['nativePixelSize'] == [6000, 4000] and ci['outputExtent'] == [0, 0, 6000, 4000], f'{label}: CI frame changed')
        require(ci['orientation'] == 1 and not ci['nativeLensCorrectionEnabled'], f'{label}: unexpected CI orientation/correction')
        candidates = []
        for origin in [0, 4, 12]:
            moving = OUT / f'libraw-{label}-origin-{origin}.png'
            decoded.crop((origin, origin, origin + 6000, origin + 4000)).resize(
                (int(6000 * scale), int(4000 * scale)), Image.Resampling.LANCZOS).save(moving)
            registration = observe('register', target, moving, 'tiles' if origin == 12 else 'full')
            expected = [(12 - origin) * scale, -(12 - origin) * scale]
            for item in registration['observations']:
                measured = item['translationAffine'][4:6]
                error = [measured[i] - expected[i] for i in range(2)]
                item['expectedTranslationObservationPixels'] = expected
                item['translationResidualFullResolutionPixels'] = [x / scale for x in error]
                # Two original pixels is the predeclared observation tolerance,
                # not a subpixel optical accuracy claim for the manufacturer table.
                require(all(math.isfinite(x) and abs(x / scale) <= 2 for x in error),
                        f'{label}/origin-{origin}/{item["name"]}: translation outside 2 original pixels')
                columns = item['homographyColumns']
                width, height = item['region'][2:4]
                displacement = []
                for x, y in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1), (width / 2, height / 2)]:
                    z = columns[0][2] * x + columns[1][2] * y + columns[2][2]
                    if not math.isfinite(z) or abs(z) < 1e-6:
                        failures.append(f'{label}: invalid homogeneous denominator')
                        continue
                    mapped = [(columns[0][i] * x + columns[1][i] * y + columns[2][i]) / z for i in range(2)]
                    displacement.append(math.hypot(mapped[0] - x - expected[0], mapped[1] - y - expected[1]) / scale)
                item['homographyProbeLocations'] = 'Four local region corners and its center'
                item['homographyProbeResidualFullResolutionPixels'] = displacement
                item['homographyMaxSampledResidualFullResolutionPixels'] = max(displacement, default=None)
                require(len(displacement) == 5 and all(math.isfinite(x) and x <= 2 for x in displacement),
                        f'{label}/origin-{origin}/{item["name"]}: homography outside 2 original pixels')
            candidates.append({'librawCropOrigin': [origin, origin], 'imageSHA256': digest(moving), **registration})
        # Independent known-shift control establishes the signs returned by
        # Vision, rather than labelling them using an assumed transform direction.
        with Image.open(target) as im:
            shifted = im.transform(im.size, Image.Transform.AFFINE, (1, 0, -8, 0, 1, -6))
            control = OUT / f'shift-control-{label}.png'
            shifted.save(control)
        control_report = observe('register', target, control, 'full')
        shift = control_report['observations'][0]['translationAffine'][4:6]
        require(abs(shift[0] - 8) <= .5 and abs(shift[1] + 6) <= .5, f'{label}: known shift control failed')
        self_report = observe('register', target, target, 'full')
        require(all(abs(x) <= .01 for x in self_report['observations'][0]['translationAffine'][4:6]), f'{label}: identity control failed')
        records.append({'scale': scale, 'coreImage': ci, 'targetSHA256': digest(target), 'candidates': candidates,
                        'knownShiftControl': {'movingContentShiftImagePixels': [8, 6], **control_report}, 'identityControl': self_report})
        print(f'{label}: 12 cross-decoder regions and two controls measured.', flush=True)

    require(digest(source) == fixture['sha256'], 'Original RAW changed')
    # Explicit correction state prevents accidentally treating the in-camera
    # JPEG as a corrected optical reference for this scene.
    command = ['/usr/bin/perl', str(ROOT / 'Resources/LensBridge/exiftool/exiftool'), '-j', '-G1', '-n',
               '-SubIFD:DistortionCorrection', '-SubIFD:VignettingCorrection', str(source)]
    flags = json.loads(subprocess.check_output(command, timeout=30))[0]
    flags.pop('SourceFile', None)
    labels = json.loads(subprocess.check_output([x for x in command if x != '-n'], timeout=30))[0]
    labels.pop('SourceFile', None)
    report = {
        'scope': 'One pinned A6000 scene: spatial relation between uncorrected Core Image and LibRaw decoder frames. Not optical calibration, manufacturer-table normalization, all cameras or added automatic coverage.',
        'sourceRAW': {'fixture': fixture['file'], 'sha256': fixture['sha256'], 'originalUnchanged': digest(source) == fixture['sha256']},
        'toolSHA256': {'swift': digest(swift), 'driver': digest(Path(__file__)), 'metadataFixture': digest(fixture_path)},
        'environment': {'macOS': platform.mac_ver()[0], 'rawpy': rawpy.__version__, 'libraw': list(rawpy.libraw_version), 'numpy': np.__version__, 'Pillow': pillow_version},
        'librawSizes': sizes, 'cameraRecordedCorrectionFlags': flags, 'cameraRecordedCorrectionLabels': labels,
        'visionTranslationConvention': 'Known control: moving content shifted right 8/down 6 reports +8/-6. Values are observations, not a product warp.',
        'toleranceFullResolutionPixels': 2, 'measurements': records, 'failures': failures,
        'manufacturerTableFrameProven': False, 'renderingEnabled': False,
    }
    output = OUT / 'verification.json'
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(f'Decoder frame: {len(failures)} failed observations; no manufacturer profile enabled.')
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
