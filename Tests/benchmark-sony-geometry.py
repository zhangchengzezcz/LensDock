"""Optional serial before/after benchmark; needs macOS, Xcode, local PTFoundation.

Builds both implementations with the same current harness and supporting code.
The baseline is own-project source from 05bc52f; no Adobe data or RAW is read.
All binaries and individual reports stay in ignored Build/Development.
"""
from pathlib import Path
import hashlib
import json
import platform
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Build/Development/sony-geometry-performance'
BASE = '05bc52fdb0ef7409235c926f1c678f8ce4b55283'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    native = ROOT / 'Sources/Native'
    baseline = OUT / 'baseline-LensSonyGeometryImage.m'
    baseline.write_bytes(subprocess.check_output(['git', 'show', f'{BASE}:Sources/Native/LensSonyGeometryImage.m'], cwd=ROOT))
    implementations = {'before': baseline, 'after': native / 'LensSonyGeometryImage.m'}
    executables = {}
    for name, implementation in implementations.items():
        executable = OUT / f'benchmark-{name}'
        command = ['xcrun', 'clang', '-arch', 'arm64', '-mmacosx-version-min=26.0', '-O2', '-fobjc-arc',
                   '-Wno-deprecated-declarations', '-I', str(native), '-framework', 'Cocoa', '-framework', 'CoreImage',
                   '-framework', 'ImageIO', f'-DLENS_SONY_BENCH_IMPLEMENTATION_SHA="{sha(implementation)}"',
                   str(ROOT / 'Tests/benchmark-sony-geometry-effect.m'),
                   *[str(native / f) for f in ['LensCorrectionSettings.m', 'LensNativeState.m', 'LensVignettingFilter.m',
                                              'LensCalibrationImage.m', 'LensConstrainedCrop.m']], str(implementation),
                   '-o', str(executable)]
        subprocess.run(command, cwd=ROOT, check=True)
        executables[name] = executable
    records = []
    cases = [('control', 'full'), ('DT', 'full'), ('DT', 'preview'), ('DT', 'roi'), ('D', 'full'), ('T', 'full')]
    # Alternate order across repetitions; no concurrent benchmark processes.
    for repetition in range(3):
        for mode, view in cases:
            for variant in (['before', 'after'] if repetition % 2 == 0 else ['after', 'before']):
                report = OUT / f'{variant}-{mode}-{view}-{repetition}.json'
                result = subprocess.run([str(executables[variant]), mode, view, str(report)], cwd=ROOT,
                                        stderr=subprocess.PIPE, text=True, timeout=180)
                if result.returncode:
                    raise SystemExit(f'{variant}/{mode}/{view} failed; inspect local report and stderr: {result.stderr[-800:]}')
                record = json.loads(report.read_text())
                if not record['passed'] or record['compiledImplementationSHA256'] != sha(implementations[variant]):
                    raise SystemExit('Failed benchmark or implementation digest mismatch.')
                record.update(variant=variant, repetition=repetition, executableSHA256=sha(executables[variant]))
                records.append(record)
    summaries = []
    for mode, view in cases:
        item = {'mode': mode, 'view': view, 'freshProcessesPerVariant': 3}
        for variant in implementations:
            selected = [r for r in records if r['mode'] == mode and r['view'] == view and r['variant'] == variant]
            item[variant] = {
                'medianPreparationMS': statistics.median(r['preparationMS'] for r in selected),
                'medianFirstRenderMS': statistics.median(r['runs'][0]['renderMS'] for r in selected),
                'medianPreparationPlusFirstRenderMS': statistics.median(r['preparationMS'] + r['runs'][0]['renderMS'] for r in selected),
                'medianSecondRenderMS': statistics.median(r['runs'][1]['renderMS'] for r in selected),
                'medianPeakPhysicalFootprintMiB': statistics.median(r['runs'][1]['memoryAfter']['peakPhysicalFootprintBytes'] / 1048576 for r in selected),
                'medianPeakResidentMiB': statistics.median(r['runs'][1]['memoryAfter']['peakResidentBytes'] / 1048576 for r in selected),
            }
        summaries.append(item)
    sources = ['Tests/benchmark-sony-geometry.py', 'Tests/benchmark-sony-geometry-effect.m',
               'Sources/Native/LensSonyGeometryImage.m', 'Sources/Native/LensSonyGeometryImage.h',
               'Sources/Native/LensSonyGeometry.h', 'Sources/Native/LensSonyGeometryArchive.h',
               'Sources/Native/LensCorrectionSettings.m', 'Sources/Native/LensVignettingFilter.m',
               'Sources/Native/LensNativeState.m', 'Sources/Native/LensCalibrationImage.m',
               'Sources/Native/LensConstrainedCrop.m', 'Tests/Fixtures/Sony-embedded-metadata.json',
               'Tests/Fixtures/A6000-reopen-binding.json', 'Resources/native-effects-template.json']
    report = {'scope': 'Serial synthetic 24MP native effect comparison on one Mac, actual recorded source nodes in a hypothetical explicit frame. Not RAW decode, photo optical acceptance, actual app interaction, PXD I/O or all-Mac performance.',
              'baselineCommit': BASE, 'baselineImplementationSHA256': sha(baseline),
              'sourceSHA256': {name: sha(ROOT / name) for name in sources},
              'environment': {'macOS': platform.mac_ver()[0],
                              'build': subprocess.check_output(['sw_vers', '-buildVersion'], text=True).strip(),
                              'cpu': subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip(),
                              'physicalMemoryBytes': int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True))},
              'compileOptions': ['arm64', 'macosx-version-min=26.0', 'O2', 'objc-arc'],
              'conditions': ['Same current harness and supporting source for both variants; only geometry image implementation differs.',
                             'Every observation is a fresh process, same procedural source warmup and output buffer commitment.',
                             'Shared OS/driver shader caches may already be warm; this is not cold application startup.',
                             'Each process measures first evaluation and a second evaluation of the same image graph, cacheIntermediates=false.',
                             'Peak physical footprint includes the whole process and Core Image resources; it is not map storage alone.',
                             'RGBA8 output checks alpha and 63 spatial/color probes per evaluation; independent float-coordinate tests cover precision.'],
              'summaries': summaries, 'records': records, 'failures': []}
    destination = OUT / 'comparison.json'
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'report': str(destination.relative_to(ROOT)), 'summaries': summaries}, indent=2), flush=True)


if __name__ == '__main__':
    main()
