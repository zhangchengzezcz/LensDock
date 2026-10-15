#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <dlfcn.h>
#import <math.h>
#import "LensNativeProfileEngine.h"
#import "LensRecommendationPolicy.h"
#import "LensCorrectionSettings.h"
#import "LensNativeState.h"
int main(){@autoreleasepool{
 NSURL*here=[NSURL fileURLWithPath:@"Build/Tests" isDirectory:YES];NSURL*db=[here URLByAppendingPathComponent:@"resources/db"],*lib=[here URLByAppendingPathComponent:@"lib/liblensfun.0.3.4.dylib"];
 NSMutableDictionary*m=[@{@"Make":@"Canon",@"Model":@"Canon EOS 40D",@"LensModel":@"Canon EF-S 17-85mm f/4-5.6 IS USM",@"FocalLength":@17,@"FNumber":@4,@"nativeCorrectionSupport":@{@"probeSucceeded":@YES,@"lensCorrectionSupported":@YES}}mutableCopy];NSError*e=nil;
 NSDictionary*p=LensNativeProfilePlanFullGeometry(m,db,lib,192,128,&e),*r=p[@"report"],*policy=LensRecommendationPolicy(p);if(!p||![r[@"supplementalVignettingOnly"]boolValue]||p[@"normalizedGeometryMapsLZFSE"]||[r[@"distortionProfileAvailable"]boolValue]||[r[@"tcaProfileAvailable"]boolValue]||[r[@"distortionPeakShiftPercent"]doubleValue]!=0||![policy[@"strengths"]isEqual:@[@0,@0,@0]]||[policy[@"vignettingAutomatic"]boolValue]||![r[@"vignettingProfileAvailable"]boolValue])return 1;
 if(LensNativeProfilePlan(m,db,lib,0,128,nil)||LensNativeProfilePlan(m,db,lib,16001,128,nil))return 2;
 NSDictionary*on=@{@"rawParameters":@[@1,@{@"lc":@YES}]},*off=@{@"rawParameters":@[@1,@{@"lc":@NO}]};
 if(!LensPlanAllowsLiveNativeCorrection(p,on)||!LensPlanAllowsLiveNativeCorrection(p,off))return 3;
 dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL);
 NSMutableDictionary*mutable=[p mutableCopy],*report=[r mutableCopy];report[@"workingTransfer"]=@"linear";mutable[@"report"]=report;mutable[@"metadata"]=m;
 NSData*envelope=[NSData dataWithContentsOfURL:[here URLByAppendingPathComponent:@"native-effects-template.json"]];NSDictionary*settings=@{@"distortionEnabled":@NO,@"tcaEnabled":@NO,@"vignettingEnabled":@YES,@"distortionStrength":@0,@"tcaStrength":@0,@"vignettingStrength":@23};
 id effects=LensEffectsForCorrectionPlan(mutable,envelope,settings,nil,&e);if(!effects||![LensSavedCorrectionProfile(LensEffectsFromJSON(LensEffectsJSON(effects,nil)))[@"correctionSettings"]isEqual:settings])return 4;
 NSMutableDictionary*illegal=[settings mutableCopy];illegal[@"distortionEnabled"]=@YES;if(LensEffectsForCorrectionPlan(mutable,envelope,illegal,nil,nil))return 5;
 m[@"LensModel"]=@"Unknown 12345";NSDictionary*unknown=LensNativeProfilePlan(m,db,lib,192,128,&e);if(!unknown||unknown[@"linearGainFloat32BottomUp"]||[unknown[@"report"][@"vignettingProfileAvailable"]boolValue])return 6;
 // Native correction can remain available without an independent profile.
 // Its report must still retain a recorded standard EXIF SubjectDistance.
 m[@"SubjectDistance"]=@2.5;
 NSDictionary*standardDistance=LensNativeProfilePlan(m,db,lib,192,128,&e);
 if(fabs([standardDistance[@"report"][@"focus_distance_m"]doubleValue]-2.5)>1e-9||![standardDistance[@"report"][@"distance_source"]isEqual:@"metadata"])return 11;
 m[@"FocusDistance"]=@4;
 NSDictionary*makerDistance=LensNativeProfilePlan(m,db,lib,192,128,&e);
 if(fabs([makerDistance[@"report"][@"focus_distance_m"]doubleValue]-4)>1e-9)return 12;
 m[@"FocusDistance"]=@(-1);
 NSDictionary*invalidMakerDistance=LensNativeProfilePlan(m,db,lib,192,128,&e);
 if(fabs([invalidMakerDistance[@"report"][@"focus_distance_m"]doubleValue]-2.5)>1e-9)return 13;
 [m removeObjectForKey:@"SubjectDistance"];
 NSDictionary*missingDistance=LensNativeProfilePlan(m,db,lib,192,128,&e);
 if([missingDistance[@"report"][@"focus_distance_m"]doubleValue]!=1000||![missingDistance[@"report"][@"distance_source"]isEqual:@"infinity_fallback"])return 14;
 [m removeObjectForKey:@"FocusDistance"];
 m[@"nativeCorrectionSupport"]=@{@"probeSucceeded":@NO};if(LensNativeProfilePlan(m,db,lib,192,128,nil))return 7;
 m[@"LensModel"]=@"Canon EF-S 17-85mm f/4-5.6 IS USM";m[@"nativeCorrectionSupport"]=@{@"probeSucceeded":@YES,@"lensCorrectionSupported":@NO};NSDictionary*unsupported=LensNativeProfilePlanFullGeometry(m,db,lib,192,128,&e);if(!unsupported[@"normalizedGeometryMapsLZFSE"]||LensPlanAllowsLiveNativeCorrection(unsupported,on)||!LensPlanAllowsLiveNativeCorrection(unsupported,off))return 8;
 NSMutableArray*probes=[NSMutableArray new];for(NSString*file in @[@"Tests/PrivateRAW/Canon40D.CR2",@"Tests/PrivateRAW/NikonD70.NEF",@"Tests/PrivateRAW/CanonR50V.CR3"]){if(![NSFileManager.defaultManager fileExistsAtPath:file])continue;NSDictionary*n=LensReadNativeCorrectionSupport([NSURL fileURLWithPath:file]);if(![n[@"probeSucceeded"]boolValue])return 9;BOOL expected=[file.pathExtension isEqual:@"CR3"];if([n[@"lensCorrectionSupported"]boolValue]!=expected)return 10;[probes addObject:@{@"fixtureType":file.pathExtension,@"nativeSupport":n}];}
 NSDictionary*result=@{@"verifiedAt":NSDate.date.description,@"nativeSupported":@{@"noSupplementalGeometryMaps":@YES,@"defaultVignettingOffAndZero":@YES,@"manualVignettingSettingsRoundtrip":@YES,@"rejectEnabledSupplementalGeometry":@YES,@"nativeOffSwitchPreserved":@YES},@"unknownLensNoInventedGain":@YES,@"unknownSupportFailsClosed":@YES,@"nativeUnsupportedRetainsGeometry":@YES,@"invalidDimensionsRejected":@YES,@"nativeOnlyDistanceMetadata":@{@"standardSubjectDistanceRetained":@YES,@"validMakerNoteDistanceHasPriority":@YES,@"invalidMakerNoteFallsBackToStandard":@YES,@"missingDistanceExplicitFarFallback":@YES},@"actualRAWProbes":probes};
 [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]writeToURL:[here URLByAppendingPathComponent:@"native-priority-verification.json"] atomically:YES];puts("Native priority, optional vignette, bounds and settings passed. See actualRAWProbes for optional RAW checks.");
}}
