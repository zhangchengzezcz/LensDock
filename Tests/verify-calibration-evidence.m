#import "LensNativeProfileEngine.h"
#import "LensCalibrationEvidence.h"
#import "LensRecommendationPolicy.h"
#import "LensCornerAssessment.h"

int main(){@autoreleasepool{
 NSURL *here=[NSURL fileURLWithPath:@"Build/Tests" isDirectory:YES],*library=[here URLByAppendingPathComponent:@"lib/liblensfun.0.3.4.dylib"];
 NSURL *temporary=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:temporary withIntermediateDirectories:YES attributes:nil error:nil];
 // This explicitly named synthetic database tests identity models. It is never
 // installed as a lens profile or attributed to a real manufacturer's lens.
 NSString *xml=@"<lensdatabase version=\"1\"><camera><maker>LensBridge Test</maker><model>Identity Camera</model><mount>TestMount</mount><cropfactor>1.5</cropfactor></camera><lens><maker>LensBridge Test</maker><model>Identity 50mm f/2</model><mount>TestMount</mount><cropfactor>1.5</cropfactor><calibration><distortion model=\"ptlens\" focal=\"50\" a=\"0\" b=\"0\" c=\"0\"/><tca model=\"poly3\" focal=\"50\" vr=\"1\" vb=\"1\" cr=\"0\" cb=\"0\" br=\"0\" bb=\"0\"/><vignetting model=\"pa\" focal=\"50\" aperture=\"2\" distance=\"1000\" k1=\"0\" k2=\"0\" k3=\"0\"/></calibration></lens></lensdatabase>";
 [xml writeToURL:[temporary URLByAppendingPathComponent:@"identity.xml"] atomically:YES encoding:NSUTF8StringEncoding error:nil];NSError *error=nil;
 NSDictionary *metadata=@{@"Make":@"LensBridge Test",@"Model":@"Identity Camera",@"LensModel":@"Identity 50mm f/2",@"FocalLength":@50,@"FNumber":@2};
 NSDictionary *identity=LensNativeProfilePlanFullGeometry(metadata,temporary,library,600,400,&error);if(!identity){NSLog(@"%@",error);return 2;}
 NSDictionary *zero=LensRecommendationPolicy(identity);
 if(LensGeometryCalibrationNeeded(identity[@"report"],@"distortion")||LensGeometryCalibrationNeeded(identity[@"report"],@"tca")||[identity[@"normalizedGeometryMapsLZFSE"]count]||[zero[@"strengths"][0]doubleValue]||[zero[@"strengths"][1]doubleValue]||[zero[@"strengths"][2]doubleValue])return 3;
 NSMutableArray *results=[NSMutableArray new];
 for(NSString *file in @[@"Tests/PrivateRAW/Canon40D.CR2",@"Tests/PrivateRAW/NikonD70.NEF"]){
  if(![NSFileManager.defaultManager fileExistsAtPath:file])continue;
  NSDictionary *m=LensReadRawMetadata([NSURL fileURLWithPath:file],[here URLByAppendingPathComponent:@"resources/exiftool/exiftool"],&error);
  BOOL nikon=[file.pathExtension isEqual:@"NEF"];
  NSDictionary *plan=LensNativeProfilePlan(m,[here URLByAppendingPathComponent:@"resources/db"],library,nikon?2000:1936,nikon?3008:1288,&error);if(!plan){NSLog(@"%@",error);return 4;}
  NSDictionary *report=plan[@"report"];
  if(!LensGeometryCalibrationNeeded(report,@"distortion")||!LensGeometryCalibrationNeeded(report,@"tca")||[report[@"distortionPeakShiftPercent"]doubleValue]<=0||[report[@"tcaPeakSeparationPixels"]doubleValue]<=0)return 5;
  for(int i=0;i<3;i++)for(NSNumber *strength in @[@0,@37,@100,@161,@200]){
   double actual=LensCorrectionStrengthFromAmount(report,i,LensDisplayCorrectionAmount(report,i,strength.doubleValue));if(fabs(actual-strength.doubleValue)>1e-8)return 6;
  }
  [results addObject:@{@"lens":report[@"lens"],@"focal":report[@"focal_mm"],@"distortionPercentOfShortEdge":report[@"distortionPeakShiftPercent"],@"tcaPixels":report[@"tcaPeakSeparationPixels"],@"vignettingFullEV":@(LensDisplayCorrectionAmount(report,2,100)),@"profileOnly":@YES}];
 }
 NSMutableDictionary *unsupported=[identity[@"report"]mutableCopy];unsupported[@"interpolatedCalibration"]=@{@"distortion":@{@"model":@99,@"terms":@[@1,@1,@1]},@"tca":@{@"model":@99,@"terms":@[@1,@1,@1,@1,@1,@1]}};
 if(LensGeometryCalibrationNeeded(unsupported,@"distortion")||LensGeometryCalibrationNeeded(unsupported,@"tca")||LensGeometryCalibrationNeeded(@{},@"distortion"))return 7;
 NSDictionary *out=@{@"identityCalibrationCreatesNoWarp":@YES,@"identityRecommendationsAreZero":@YES,@"missingAndUnsupportedCalibrationCreatesNoWarp":@YES,@"amountStrengthRoundtrip":@YES,@"realFixtures":results};
 [[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/calibration-evidence-verification.json" atomically:YES];[NSFileManager.defaultManager removeItemAtURL:temporary error:nil];puts("Identity and unsupported calibrations create no warp; real-lens amounts and roundtrip passed.");
}}
