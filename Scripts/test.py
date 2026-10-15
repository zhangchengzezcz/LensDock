"""Tests without redistributing RAW files. Native render tests need local Pixelmator."""
from pathlib import Path
import subprocess,os,shutil
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'Build/Tests';out.mkdir(parents=True,exist_ok=True)
for name,target in [('lib',ROOT/'Vendor/Lib'),('resources',ROOT/'Resources/LensBridge')]:
 p=out/name
 if not p.exists():p.symlink_to(target,target_is_directory=True)
shutil.copy2(ROOT/'Resources/native-effects-template.json',out/'native-effects-template.json')
native=ROOT/'Sources/Native'
groups={
 'verify-effect-replacement':['LensCorrectionSettings.m','LensNativeState.m','LensVignettingFilter.m'],
 'verify-profile-selection':['LensNativeProfileEngine.m','LensCorrectionSettings.m','LensNativeState.m','LensVignettingFilter.m'],
 'verify-recorded-aliases':['LensNativeProfileEngine.m'],
 'verify-sensor-variant':['LensNativeProfileEngine.m'],
 'verify-camera-context':['LensNativeProfileEngine.m'],
 'verify-matching-boundaries':['LensNativeProfileEngine.m','LensRecommendationPolicy.m'],
 'verify-calibration-evidence':['LensNativeProfileEngine.m','LensRecommendationPolicy.m','LensCornerAssessment.m'],
 'verify-corner-assessment':['LensCornerAssessment.m','LensRecommendationPolicy.m'],
 'verify-three-corrections':['LensNativeProfileEngine.m','LensCorrectionSettings.m','LensNativeState.m','LensVignettingFilter.m'],
 'verify-native-priority':['LensNativeProfileEngine.m','LensRecommendationPolicy.m','LensCorrectionSettings.m','LensNativeState.m','LensVignettingFilter.m'],
 'verify-source-binding':['LensCorrectionSettings.m','LensNativeState.m','LensVignettingFilter.m'],
}
for name,sources in groups.items():
 subprocess.run(['xcrun','clang','-arch','arm64','-mmacosx-version-min=26.0','-O2','-fobjc-arc','-Wno-deprecated-declarations',*(['-Wl,-export_dynamic'] if name=='verify-effect-replacement' else []),'-I',str(native),'-framework','Cocoa','-framework','CoreImage','-framework','ImageIO',str(ROOT/'Tests'/(name+'.m')),*[str(native/s) for s in sources],'-o',str(out/name)],check=True,cwd=ROOT)
 subprocess.run([str(out/name)],check=True,cwd=ROOT)
 if name=='verify-three-corrections':subprocess.run([str(out/name)],check=True,cwd=ROOT,env={**os.environ,'LENS_GRID_TEST':'1'})
print('All selected tests passed. RAW-specific checks run only when Tests/PrivateRAW is supplied.')
