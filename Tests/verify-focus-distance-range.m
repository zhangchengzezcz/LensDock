#import "LensNativeProfileEngine.h"
#import "LensCaptureParameters.h"
#import "LensCorrectionSettings.h"
#import "LensNativeState.h"
#import "LensRecommendationPolicy.h"
#import <dlfcn.h>

int main(){@autoreleasepool{
 NSDictionary *tags=@{@"IFD0:Make":@"Canon",@"Canon:FocusDistanceLower":@9.75,@"Canon:FocusDistanceUpper":@11.05,@"Track4:FocusDistanceLower":@11.05,@"Track4:FocusDistanceUpper":@9.75};
 NSDictionary *range=LensCanonFocusDistanceRange(tags);if(![range[@"lower"]isEqual:@9.75]||![range[@"upper"]isEqual:@11.05]||[range[@"upperUnbounded"]boolValue])return 1;
 NSMutableDictionary *infinite=[tags mutableCopy];infinite[@"Canon:FocusDistanceUpper"]=@655.35;NSDictionary *far=LensCanonFocusDistanceRange(infinite);if(![far[@"upperUnbounded"]boolValue]||far[@"upper"])return 2;
 for(NSArray *invalid in @[@[@"IFD0:Make",@"Nikon"],@[@"Canon:FocusDistanceLower",@0],@[@"Canon:FocusDistanceLower",@(-1)],@[@"Canon:FocusDistanceLower",@12],@[@"Canon:FocusDistanceLower",@"9.75"],@[@"Canon:FocusDistanceUpper",@(NAN)],@[@"Canon:FocusDistanceUpper",@655.36],@[@"Canon:FocusDistanceLower",@655.35]]){
  NSMutableDictionary *bad=[tags mutableCopy];bad[invalid[0]]=invalid[1];if(LensCanonFocusDistanceRange(bad))return 3;
 }
 NSMutableDictionary *trackOnly=[tags mutableCopy];[trackOnly removeObjectForKey:@"Canon:FocusDistanceLower"];[trackOnly removeObjectForKey:@"Canon:FocusDistanceUpper"];if(LensCanonFocusDistanceRange(trackOnly)||LensCanonFocusDistanceRange((id)@42))return 4;
 NSURL *here=[NSURL fileURLWithPath:@"Build/Tests" isDirectory:YES],*db=[here URLByAppendingPathComponent:@"resources/db"],*lib=[here URLByAppendingPathComponent:@"lib/liblensfun.0.3.4.dylib"];
 NSMutableDictionary *metadata=[@{@"Make":@"Canon",@"Model":@"Canon EOS 40D",@"LensModel":@"Canon EF-S 17-85mm f/4-5.6 IS USM",@"FocalLength":@17,@"FNumber":@4,@"FocusDistanceRangeMeters":range}mutableCopy];
 NSDictionary *plan=LensNativeProfilePlanFullGeometry(metadata,db,lib,64,48,nil),*report=plan[@"report"];
 if(!plan||![report[@"FocusDistanceRangeMeters"]isEqual:range]||[report[@"focus_distance_m"]doubleValue]!=1000||![report[@"distance_source"]isEqual:@"infinity_fallback"]||![LensCaptureParameterDisplayValues(metadata)[2]isEqual:@1000])return 5;
 if(![LensFocusDistanceTextForReport(report)containsString:@"对焦范围"]||[LensFocusRangeFallbackNote(metadata)containsString:@"未记录对焦距离"])return 6;
 NSMutableDictionary *scalar=[metadata mutableCopy];scalar[@"FocusDistance"]=@2.5;NSDictionary *scalarPlan=LensNativeProfilePlan(scalar,db,lib,64,48,nil);
 if([scalarPlan[@"report"][@"focus_distance_m"]doubleValue]!=2.5||[LensFocusDistanceTextForReport(scalarPlan[@"report"])containsString:@"对焦范围"])return 7;
 NSMutableDictionary *official=[metadata mutableCopy];official[@"LensModel"]=@"Unknown lens";official[@"nativeCorrectionSupport"]=@{@"probeSucceeded":@YES,@"lensCorrectionSupported":@YES};NSDictionary *nativePlan=LensNativeProfilePlan(official,db,lib,64,48,nil);
 if(![nativePlan[@"report"][@"FocusDistanceRangeMeters"]isEqual:range]||nativePlan[@"normalizedGeometryMapsLZFSE"]||![LensRecommendationPolicy(nativePlan)[@"strengths"]isEqual:@[@0,@0,@0]])return 8;
 NSDictionary *cleared=LensMetadataWithCaptureParameterText(metadata,metadata,@[@"17",@"4",@""],nil,NO,nil),*restored=LensMetadataRestoringCaptureParameters(metadata,cleared),*reset=LensMetadataWithCaptureParameterText(metadata,cleared,@[],nil,YES,nil);
 if(cleared[@"FocusDistanceRangeMeters"]||restored[@"FocusDistanceRangeMeters"]||![reset[@"FocusDistanceRangeMeters"]isEqual:range])return 9;
 NSDictionary *unchanged=LensMetadataWithCaptureParameterText(metadata,metadata,@[@"18",@"4",@"1000"],nil,NO,nil),*manual=LensMetadataWithCaptureParameterText(metadata,metadata,@[@"18",@"4",@"12"],nil,NO,nil);
 if(unchanged[@"FocusDistance"]||![unchanged[@"FocusDistanceRangeMeters"]isEqual:range]||manual[@"FocusDistanceRangeMeters"]||![manual[@"FocusDistance"]isEqual:@12])return 12;
 if(!dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL))return 10;
 NSMutableDictionary *savedPlan=[plan mutableCopy],*savedReport=[report mutableCopy];savedReport[@"workingTransfer"]=@"linear";savedPlan[@"report"]=savedReport;savedPlan[@"metadata"]=metadata;
 NSDictionary *settings=@{@"distortionEnabled":@YES,@"tcaEnabled":@YES,@"vignettingEnabled":@NO,@"distortionStrength":@100,@"tcaStrength":@100,@"vignettingStrength":@0};
 id effects=LensEffectsForCorrectionPlan(savedPlan,[NSData dataWithContentsOfURL:[here URLByAppendingPathComponent:@"native-effects-template.json"]],settings,nil,nil);NSDictionary *saved=LensSavedCorrectionProfile(LensEffectsFromJSON(LensEffectsJSON(effects,nil)));
 if(!effects||![saved[@"metadata"][@"FocusDistanceRangeMeters"]isEqual:range])return 11;
 NSDictionary *evidence=@{@"scope":@"Canon distance range validation, native/independent plan routing, display and actual effect serialization; no new optical calibration or host GUI proof",@"canonGroupWinsOverReversedTrackCopy":@YES,@"rangeNeverConvertedToMeasuredScalar":@YES,@"unboundedSentinelNotFiniteDistance":@YES,@"malformedAndReversedCanonBoundsRejected":@YES,@"nativeOnlyReportRetainsRange":@YES,@"nativeDefaultSupplementalAmountsRemainZero":@YES,@"manualClearPersistsAndResetRestoresRange":@YES,@"effectSerializationRetainsRecordedRange":@YES};
 [[NSJSONSerialization dataWithJSONObject:evidence options:NSJSONWritingPrettyPrinted error:nil]writeToURL:[here URLByAppendingPathComponent:@"focus-distance-range-verification.json"] atomically:YES];
 puts("Recorded focus ranges stay ranges, survive effect serialization and never become estimated measured distances.");
}}
