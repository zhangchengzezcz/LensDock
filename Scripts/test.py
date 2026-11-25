"""Tests without redistributing RAW files. Native render tests need local Pixelmator."""
from pathlib import Path
import subprocess,os,shutil
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'Build/Tests';out.mkdir(parents=True,exist_ok=True)
for name,target in [('lib',ROOT/'Vendor/Lib'),('resources',ROOT/'Resources/LensBridge')]:
 p=out/name
 if not p.exists():p.symlink_to(target,target_is_directory=True)
shutil.copy2(ROOT/'Resources/native-effects-template.json',out/'native-effects-template.json')
native=ROOT/'Sources/Native'
host=Path(os.environ.get('LENS_TEST_PIXELMATOR','/Applications/Pixelmator Pro Creator Studio.app'))
frameworks=host/'Contents/Frameworks'
codec=out/'LensEffectsCodec.dylib'
subprocess.run(['xcrun','swiftc','-target','arm64-apple-macos26.0','-O','-emit-library',str(native/'LensEffectsCodec.swift'),str(ROOT/'Tests/LensEffectsCodecProbe.swift'),'-o',str(codec)],check=True)
legacy_exports=subprocess.check_output(['xcrun','dyld_info','-arch','arm64','-exports',str(frameworks/'PTFoundation.framework/PTFoundation')],text=True)
legacy_wrapper='$s12PTFoundation13PTEffectsObjCC7effectsAA0B0Vvg' in legacy_exports
# These render probes call the historical wrapper's Objective-C apply method.
# The current host's independent render check must use its real photo UI.
legacy_render_groups={'verify-sony-geometry-effect','verify-geometry-boundaries','verify-full-resolution-boundaries','verify-fractional-preview','verify-three-corrections'}
host_env={**os.environ,'LENS_TEST_PIXELMATOR':str(host),'DYLD_FRAMEWORK_PATH':str(frameworks),'DYLD_INSERT_LIBRARIES':str(codec)}
groups={
 'verify-sony-fallback':['LensNativeProfileEngine.m','LensRecommendationPolicy.m','LensCorrectionSettings.m','LensNativeState.m','LensVignettingFilter.m'],
 'verify-sony-recorded-settings':['LensNativeProfileEngine.m','LensRecommendationPolicy.m'],
 'verify-sony-gpu-coordinates':['LensSonyGeometryImage.m'],
 'verify-sony-geometry-effect':['LensCorrectionSettings.m','LensNativeState.m','LensVignettingFilter.m'],
 'verify-sony-geometry-image':['LensSonyGeometryImage.m'],
 'verify-sony-pixel-frame':[],
 'verify-sony-embedded-profile':['LensNativeProfileEngine.m'],
 'verify-lens-identity-format':['LensNativeProfileEngine.m'],
 'verify-a047-profile-update':['LensNativeProfileEngine.m'],
 'verify-photo-open-notice':['LensCompatibilityNotice.m'],
 'compare-rendered-images-16':[],
 'verify-compact-maps':['LensNativeProfileEngine.m'],
 'verify-calibration-image':['LensCalibrationImage.m'],
 'verify-geometry-boundaries':['LensNativeProfileEngine.m','LensCorrectionSettings.m','LensNativeState.m','LensVignettingFilter.m'],
 'verify-full-resolution-boundaries':['LensNativeProfileEngine.m','LensCorrectionSettings.m','LensNativeState.m','LensVignettingFilter.m'],
 'verify-fractional-preview':['LensNativeProfileEngine.m','LensCorrectionSettings.m','LensNativeState.m','LensVignettingFilter.m'],
 'verify-public-capture-metadata':['LensNativeProfileEngine.m','LensRecommendationPolicy.m'],
 'verify-public-lx3':['LensNativeProfileEngine.m','LensRecommendationPolicy.m'],
 'verify-host-diagnostics':['LensHostDiagnostics.m'],
 'verify-host-compatibility':['LensHostCompatibility.m','LensNativeState.m'],
 'verify-recorded-aperture':['LensNativeProfileEngine.m'],
 'verify-capture-tag-precedence':['LensNativeProfileEngine.m'],
 'verify-focus-distance-range':['LensNativeProfileEngine.m','LensCorrectionSettings.m','LensNativeState.m','LensVignettingFilter.m','LensRecommendationPolicy.m'],
 'verify-capture-parameters':['LensNativeProfileEngine.m','LensCorrectionSettings.m','LensNativeState.m','LensVignettingFilter.m'],
 'verify-capture-mode':['LensNativeProfileEngine.m'],
 'verify-f810-raw-mode':['LensNativeProfileEngine.m'],
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
 if name in legacy_render_groups and not legacy_wrapper:
  print(f'{name}: requires a legacy wrapper host; set LENS_TEST_PIXELMATOR to a 4.3 app to run it.',flush=True)
  continue
 if 'LensVignettingFilter.m' in sources:sources=[*sources,'LensCalibrationImage.m','LensConstrainedCrop.m','LensSonyGeometryImage.m']
 subprocess.run(['xcrun','clang','-arch','arm64','-mmacosx-version-min=26.0','-O2','-fobjc-arc','-Wno-deprecated-declarations',*(['-Wl,-export_dynamic'] if name=='verify-effect-replacement' else []),'-I',str(native),'-framework','Cocoa','-framework','CoreImage','-framework','ImageIO',str(ROOT/'Tests'/(name+'.m')),*[str(native/s) for s in sources],'-o',str(out/name)],check=True,cwd=ROOT)
 env=host_env if 'LensNativeState.m' in sources else os.environ
 subprocess.run([str(out/name)],check=True,cwd=ROOT,env=env)
 if name=='verify-three-corrections':
  for variant in ['LENS_GRID_TEST','LENS_GAIN_GRID_TEST','LENS_RESIDUAL_GRID_TEST']:
   subprocess.run([str(out/name)],check=True,cwd=ROOT,env={**env,variant:'1'})
print('All selected tests passed. RAW-specific checks run only when Tests/PrivateRAW is supplied.')
subprocess.run(['xcrun','swiftc','-target','arm64-apple-macos26.0','-O',str(native/'LensScriptingReference.swift'),str(ROOT/'Tests/verify-scripting-reference.swift'),'-o',str(out/'verify-scripting-reference')],check=True)
subprocess.run([str(out/'verify-scripting-reference')],check=True)
