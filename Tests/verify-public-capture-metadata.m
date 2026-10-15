#import "LensNativeProfileEngine.h"
#import "LensCaptureParameters.h"
#import "LensRecommendationPolicy.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *digest(NSData *data){
 unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);
 NSMutableString *result=[NSMutableString new];for(unsigned i=0;i<sizeof(bytes);i++)[result appendFormat:@"%02x",bytes[i]];return result;
}
int main(){@autoreleasepool{
 NSURL *root=[NSURL fileURLWithPath:NSFileManager.defaultManager.currentDirectoryPath isDirectory:YES];
 NSDictionary *fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"Tests/Fixtures/Public-capture-metadata.json"]] options:0 error:nil];
 if(![fixture[@"files"]isKindOfClass:NSArray.class]||![fixture[@"files"]count])return 1;
 NSMutableArray *verified=[NSMutableArray new],*missing=[NSMutableArray new];
 for(NSDictionary *item in fixture[@"files"]){@autoreleasepool{
  NSURL *raw=[root URLByAppendingPathComponent:[@"Tests/PrivateRAW" stringByAppendingPathComponent:item[@"file"]]];
  if(![NSFileManager.defaultManager fileExistsAtPath:raw.path]){[missing addObject:item[@"file"]];continue;}
  if(![digest([NSData dataWithContentsOfURL:raw])isEqual:item[@"sha256"]])return 2;
  NSError *error=nil;NSDictionary *metadata=LensReadRawMetadata(raw,[root URLByAppendingPathComponent:@"Resources/LensBridge/exiftool/exiftool"],&error);
  if(!metadata||![metadata[@"Model"]isEqual:item[@"model"]]||fabs([metadata[@"FocalLength"]doubleValue]-[item[@"focalMM"]doubleValue])>.0001||fabs([metadata[@"FNumber"]doubleValue]-[item[@"fNumber"]doubleValue])>.0001)return 3;
  NSNumber *distance=LensPositiveCaptureNumber(metadata[@"FocusDistance"])?:LensPositiveCaptureNumber(metadata[@"SubjectDistance"]);
  BOOL recorded=item[@"focusDistanceM"]!=NSNull.null;
  if(recorded?(!distance||fabs(distance.doubleValue-[item[@"focusDistanceM"]doubleValue])>[item[@"focusToleranceM"]doubleValue]):distance!=nil)return 4;
  NSArray *display=LensCaptureParameterDisplayValues(metadata);
  if(fabs([display[0]doubleValue]-[item[@"focalMM"]doubleValue])>.0001||fabs([display[1]doubleValue]-[item[@"fNumber"]doubleValue])>.0001||fabs([display[2]doubleValue]-(recorded?distance.doubleValue:1000))>.0001)return 5;
  NSDictionary *plan=LensNativeProfilePlanIncludingGeometry(metadata,[root URLByAppendingPathComponent:@"Resources/LensBridge/db"],[root URLByAppendingPathComponent:@"Vendor/Lib/liblensfun.0.3.4.dylib"],96,64,&error),*report=plan[@"report"];
  if(![item[@"automaticPlanExpected"]boolValue]){
   if(plan||![error.domain isEqual:@"LensBridgeProfile"]||![error.localizedDescription isEqual:item[@"expectedPlanError"]])return 12;
   if(![digest([NSData dataWithContentsOfURL:raw])isEqual:item[@"sha256"]])return 10;
   [verified addObject:@{@"fixture":item,@"originalUnchanged":@YES,@"automaticDisplayValues":display,@"recordedFocusDistanceM":distance?:NSNull.null,@"automaticProfilePlanGenerated":@NO,@"matchingFailure":error.localizedDescription,@"nativeSupport":metadata[@"nativeCorrectionSupport"],@"notCountedAsAutomaticCalibrationCoverage":@YES}];
   continue;
  }
  if(!plan||![report[@"lens"]isEqual:item[@"matchedLens"]]||![report[@"matchedCameraProfileID"]length]||![report[@"matchedLensProfileID"]length]||![report[@"distance_source"]isEqual:recorded?@"metadata":@"infinity_fallback"]||fabs([report[@"focus_distance_m"]doubleValue]-(recorded?distance.doubleValue:1000))>.0001)return 6;
  NSDictionary *support=metadata[@"nativeCorrectionSupport"],*policy=LensRecommendationPolicy(plan);BOOL native=[support[@"lensCorrectionSupported"]boolValue];
  if(![support[@"probeSucceeded"]boolValue]||[report[@"geometryHandledByNative"]boolValue]!=native)return 7;
  if(native&&(plan[@"normalizedGeometryMapsLZFSE"]||![policy[@"strengths"]isEqual:@[@0,@0,@0]]||[policy[@"vignettingAutomatic"]boolValue]))return 8;
  if(metadata[@"LensDockProfileSelection"]||[plan[@"parameterOverrides"]boolValue])return 9;
  if(![digest([NSData dataWithContentsOfURL:raw])isEqual:item[@"sha256"]])return 10;
  [verified addObject:@{@"fixture":item,@"originalUnchanged":@YES,@"automaticDisplayValues":display,@"recordedFocusDistanceM":distance?:NSNull.null,@"distanceSource":report[@"distance_source"],@"matchedCameraProfileID":report[@"matchedCameraProfileID"],@"matchedLensProfileID":report[@"matchedLensProfileID"],@"matchedLens":report[@"lens"],@"nativeSupport":support,@"extraGeometrySkipped":@(native),@"automaticProfilePlanGenerated":@YES,@"manualParameterOrProfileOverrideRequired":@NO}];
 }}
 NSDictionary *result=@{@"executedOn":[NSISO8601DateFormatter.new stringFromDate:NSDate.date],@"scope":@"Optional complete public RAW, checksum and archived Exiv2 reference comparison, production metadata/display values and 96x64 automatic geometry plan. No full-image render, optical accuracy, GUI/save/reopen or Lightroom equivalence claim.",@"verifiedFiles":verified,@"missingFiles":missing,@"photosIncluded":@NO};
 NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
 if(![json writeToURL:[root URLByAppendingPathComponent:@"Build/Tests/public-capture-metadata-verification.json"] atomically:YES])return 11;
 printf("Public capture metadata: %lu complete RAW checked; %lu optional absent. Recorded fields auto-fill; missing distance remains explicit fallback.\n",(unsigned long)verified.count,(unsigned long)missing.count);
}}
