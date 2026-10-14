#import "LensNativeProfileEngine.h"
#import "LensRecommendationPolicy.h"
int main(){@autoreleasepool{
 NSURL*here=[NSURL fileURLWithPath:@"Build/Tests" isDirectory:YES],*db=[here URLByAppendingPathComponent:@"resources/db"],*lib=[here URLByAppendingPathComponent:@"lib/liblensfun.0.3.4.dylib"];NSError*error=nil;NSMutableArray*cases=[NSMutableArray new];
 NSArray*inputs=@[
 @{@"Make":@"Canon",@"Model":@"Canon EOS 40D",@"LensModel":@"EF-S17-85mm f/4-5.6 IS USM",@"FocalLength":@17,@"FNumber":@4},
 @{@"Make":@"Olympus Imaging Corp.",@"Model":@"E-M5",@"LensModel":@"OLYMPUS M.40-150mm F2.8",@"FocalLength":@40,@"FNumber":@2.8,@"FocusDistance":@10},
 @{@"Make":@"Olympus Imaging Corp.",@"Model":@"E-M5",@"LensModel":@"Olympus M.Zuiko Digital ED 40-150mm F2.8 Pro",@"FocalLength":@40,@"FNumber":@2.8,@"FocusDistance":@10},
 @{@"Make":@"Canon",@"Model":@"Canon EOS R",@"LensModel":@"Canon RF 24-50mm F4.5-6.3 IS STM",@"FocalLength":@24,@"FNumber":@4.5,@"FocusDistance":@10}];
 NSDictionary*olympus=nil;BOOL sawInvalidV=NO;
 for(NSDictionary*m in inputs){error=nil;NSDictionary*p=LensNativeProfilePlan(m,db,lib,480,320,&error);if(!p||error){NSLog(@"%@",error);return 2;}NSDictionary*r=p[@"report"];
  if([m[@"Make"]hasPrefix:@"Olympus"]){if(olympus&&![olympus[@"interpolatedCalibration"]isEqual:r[@"interpolatedCalibration"]])return 3;olympus=r;}
  if([r[@"vignettingCalibrationWarning"]length]){sawInvalidV=YES;if([r[@"vignettingProfileAvailable"]boolValue]||[r[@"vignettingCorrectionNeeded"]boolValue]||p[@"linearGainFloat32BottomUp"]||[LensRecommendationPolicy(p)[@"strengths"][2]doubleValue]||![r[@"distortionProfileAvailable"]boolValue])return 4;}
  [cases addObject:@{@"requestedIdentity":m[@"LensModel"],@"matchedLens":r[@"lens"],@"method":r[@"matchingIdentityMethod"],@"distortionAvailable":r[@"distortionProfileAvailable"],@"tcaAvailable":r[@"tcaProfileAvailable"],@"vignettingAvailable":r[@"vignettingProfileAvailable"],@"vignettingWarning":r[@"vignettingCalibrationWarning"]?:@""}];
 }
 if(!sawInvalidV)return 5;
 NSArray*rejected=@[
 @{@"Make":@"Canon",@"Model":@"Canon EOS R",@"LensModel":@"RF-S14-30mm F4-6.3 IS STM PZ",@"FocalLength":@25,@"FNumber":@5.6},
 @{@"Make":@"Canon",@"Model":@"Canon EOS 40D",@"LensModel":@"LensBridge unknown 17-85mm f/4-5.6",@"FocalLength":@17,@"FNumber":@4},
 @{@"Make":@"Canon",@"Model":@"Canon EOS 40D",@"LensModel":@"EF-S17-85mm f/4-5.6 IS USM",@"FocalLength":@200,@"FNumber":@4}];
 for(NSDictionary*m in rejected){error=nil;if(LensNativeProfilePlan(m,db,lib,480,320,&error)||!error)return 6;}
 NSDictionary*out=@{@"databaseAliasesProduceSameCalibration":@YES,@"invalidVignettingDoesNotDisableValidGeometry":@YES,@"invalidVignettingCreatesNoGainOrRecommendation":@YES,@"doesNotSubstituteRF_S_14_30":@YES,@"rejectsUnknownIdentityAndOutOfRangeFocal":@YES,@"cases":cases};
 [[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil]writeToURL:[here URLByAppendingPathComponent:@"matching-boundaries-verification.json"] atomically:YES];puts("Database alias identity, independent calibration validity, and no-substitution boundaries passed.");
}}
