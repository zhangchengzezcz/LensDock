"""Verify built deployment metadata; does not pretend to run another macOS."""
from pathlib import Path
import json
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT/'Build/LensDock.app'


def output(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)


def verify():
    info = plistlib.loads((APP/'Contents/Info.plist').read_bytes())
    contract = json.loads((ROOT/'Compatibility/Pixelmator-4.3.json').read_text())
    assert info['LSMinimumSystemVersion'] == contract['minimumOS'] == '26.0'
    assert contract['architecture'] == 'arm64'
    paths = [APP/'Contents/MacOS/LensDock', *sorted((APP/'Contents/Resources/Payload').rglob('*.dylib'))]
    records = []
    for file in paths:
        arch = output('lipo', '-archs', str(file)).strip().split()
        assert arch == ['arm64'], (file, arch)
        build = output('xcrun', 'vtool', '-show-build', str(file))
        platform = re.search(r'platform (\w+)', build).group(1)
        minimum = re.search(r'minos ([\d.]+)', build).group(1)
        version = tuple(map(int, minimum.split('.')))
        assert platform == 'MACOS' and version <= (26, 0), (file, build)
        records.append({'path': str(file.relative_to(APP)), 'architecture': arch[0], 'minimumOS': minimum})
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(APP)], check=True)
    report = {
        'passed': True, 'scope': 'Deployment and architecture contract, not cross-OS runtime acceptance',
        'target': 'Apple Silicon Macs running macOS 26 or later',
        'runtimeOS': output('sw_vers', '-productVersion').strip(),
        'runtimeBuild': output('sw_vers', '-buildVersion').strip(),
        'sdk': output('xcrun', '--sdk', 'macosx', '--show-sdk-version').strip(),
        'runtimeMatrix': {'macOS26': 'NOT_TESTED', 'macOS27.2': 'LOCAL_TESTS_ONLY', 'laterOS': 'NOT_TESTED'},
        'binaries': records,
    }
    (ROOT/'Build/Tests').mkdir(parents=True, exist_ok=True)
    (ROOT/'Build/Tests/platform-contract-verification.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f'Platform contract passed for {len(records)} arm64 binaries; deployment <= macOS 26.0. Other OS runtimes remain untested.')


if __name__ == '__main__':
    verify()
