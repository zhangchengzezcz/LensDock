#import <Foundation/Foundation.h>
#import "LensNativeProfileEngine.h"
#import "LensRecommendationPolicy.h"
#import <math.h>

// Optional local audit. Input is a private JSON array of original RAW paths
// or {path, expectedFocalMM, expectedApertureAPEX} catalog reference objects.
// Output contains aggregates and input indices, never photo paths or EXIF IDs.
static BOOL validNumber(id value) {
 if(![value isKindOfClass:NSNumber.class])return NO;
 return isfinite([value doubleValue])&&[value doubleValue]>0;
}
int main(int argc,char **argv) { @autoreleasepool {
 if(argc!=3){fprintf(stderr,"Usage: audit-private-raw-corpus private-paths.json report.json\n");return 1;}
 NSArray *paths=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
 if(![paths isKindOfClass:NSArray.class]||!paths.count)return 2;
 NSMutableSet *uniquePaths=[NSMutableSet new];
 for(id entry in paths){NSString *path=[entry isKindOfClass:NSString.class]?entry:[entry isKindOfClass:NSDictionary.class]?entry[@"path"]:nil;if(![path isKindOfClass:NSString.class]||!path.length||[uniquePaths containsObject:path])return 2;[uniquePaths addObject:path];}
 NSURL *root=[NSURL fileURLWithPath:NSFileManager.defaultManager.currentDirectoryPath isDirectory:YES];
 NSURL *tool=[root URLByAppendingPathComponent:@"Resources/LensBridge/exiftool/exiftool"],*db=[root URLByAppendingPathComponent:@"Resources/LensBridge/db"],*lib=[root URLByAppendingPathComponent:@"Vendor/Lib/liblensfun.0.3.4.dylib"];
 NSUInteger read=0,focal=0,aperture=0,distance=0,planned=0,calibrated=0,native=0,vignette=0,far=0,references=0;
 NSMutableArray *failures=[NSMutableArray new];NSMutableDictionary *groups=[NSMutableDictionary new];
 for(NSUInteger index=0;index<paths.count;index++){@autoreleasepool{
  id entry=paths[index];NSDictionary *reference=[entry isKindOfClass:NSDictionary.class]?entry:nil;NSString *path=reference?reference[@"path"]:entry;
  NSError *error=nil;NSDictionary *metadata=LensReadRawMetadata([NSURL fileURLWithPath:path],tool,&error);
  if(!metadata){[failures addObject:@{@"inputIndex":@(index),@"category":@"metadata-read-failed"}];continue;}
  read++;BOOL hasFocal=validNumber(metadata[@"FocalLength"]),hasAperture=validNumber(metadata[@"FNumber"]);
  focal+=hasFocal;aperture+=hasAperture;distance+=validNumber(metadata[@"FocusDistance"])||validNumber(metadata[@"SubjectDistance"]);
  if(reference){
   if(!validNumber(reference[@"expectedFocalMM"])||![reference[@"expectedApertureAPEX"]isKindOfClass:NSNumber.class])return 2;
   double expectedAperture=exp2([reference[@"expectedApertureAPEX"]doubleValue]/2);
   if(!isfinite(expectedAperture)||expectedAperture<=0)return 2;
   references++;
   if(!hasFocal||fabs([metadata[@"FocalLength"]doubleValue]-[reference[@"expectedFocalMM"]doubleValue])>.001||!hasAperture||fabs([metadata[@"FNumber"]doubleValue]-expectedAperture)>5e-5)
    [failures addObject:@{@"inputIndex":@(index),@"category":@"catalog-reference-capture-parameter-mismatch"}];
  }
  NSDictionary *plan=LensNativeProfilePlan(metadata,db,lib,96,64,&error),*report=plan[@"report"];
  if(!plan){[failures addObject:@{@"inputIndex":@(index),@"category":@"automatic-plan-unavailable"}];continue;}
  planned++;BOOL official=[metadata[@"nativeCorrectionSupport"][@"lensCorrectionSupported"]boolValue];native+=official;
  calibrated+=[report[@"matchedCameraProfileID"]length]>0&&[report[@"matchedLensProfileID"]length]>0;
  vignette+=[report[@"vignettingProfileAvailable"]boolValue];far+=[report[@"distance_source"]isEqual:@"infinity_fallback"];
  if(metadata[@"LensDockProfileSelection"]||[plan[@"parameterOverrides"]boolValue]){[failures addObject:@{@"inputIndex":@(index),@"category":@"unexpected-manual-override"}];}
  if(official){
   NSDictionary *policy=LensRecommendationPolicy(plan);
   if(![report[@"geometryHandledByNative"]boolValue]||! [report[@"supplementalVignettingOnly"]boolValue]||[plan[@"normalizedGeometryMapsLZFSE"]count]||[report[@"distortionCorrectionNeeded"]boolValue]||[report[@"tcaCorrectionNeeded"]boolValue]||![policy[@"strengths"]isEqual:@[@0,@0,@0]]||[policy[@"vignettingAutomatic"]boolValue])
    [failures addObject:@{@"inputIndex":@(index),@"category":@"native-priority-or-default-amount-violation"}];
  }
  NSString *key=[NSString stringWithFormat:@"%@ / %@",metadata[@"Model"]?:@"Unknown camera",report[@"lens"]?:@"Unknown lens"];
  NSMutableDictionary *group=groups[key];
  if(!group){group=[@{@"camera":metadata[@"Model"]?:@"Unknown",@"lens":report[@"lens"]?:@"Unknown",@"files":@0,@"focalMinMM":@(DBL_MAX),@"focalMaxMM":@0,@"apertureMin":@(DBL_MAX),@"apertureMax":@0}mutableCopy];groups[key]=group;}
  group[@"files"]=@([group[@"files"]unsignedIntegerValue]+1);
  if(hasFocal){double f=[metadata[@"FocalLength"]doubleValue];group[@"focalMinMM"]=@(fmin(f,[group[@"focalMinMM"]doubleValue]));group[@"focalMaxMM"]=@(fmax(f,[group[@"focalMaxMM"]doubleValue]));}
  if(hasAperture){double a=[metadata[@"FNumber"]doubleValue];group[@"apertureMin"]=@(fmin(a,[group[@"apertureMin"]doubleValue]));group[@"apertureMax"]=@(fmax(a,[group[@"apertureMax"]doubleValue]));}
  if((index+1)%20==0||index+1==paths.count){printf("Audited %lu/%lu RAW files; failures %lu.\n",(unsigned long)index+1,(unsigned long)paths.count,(unsigned long)failures.count);fflush(stdout);}
 }}
 for(NSMutableDictionary *group in groups.allValues){if([group[@"focalMinMM"]doubleValue]==DBL_MAX)group[@"focalMinMM"]=NSNull.null;if([group[@"apertureMin"]doubleValue]==DBL_MAX)group[@"apertureMin"]=NSNull.null;}
 NSDictionary *result=@{@"executedOn":[NSISO8601DateFormatter.new stringFromDate:NSDate.date],@"scope":@"Private local RAW metadata, automatic low-resolution profile-plan generation (96x64, no optical/render claim), native priority and zero default supplemental amounts; counts represent photos, not distinct camera/lens coverage or Lightroom equivalence",@"inputFiles":@(paths.count),@"metadataRead":@(read),@"focalAutomaticallyRecorded":@(focal),@"apertureAutomaticallyRecorded":@(aperture),@"focusDistanceRecorded":@(distance),@"independentCatalogParameterReferencesChecked":@(references),@"explicitFarDistanceFallback":@(far),@"automaticPlans":@(planned),@"independentCalibrationMatches":@(calibrated),@"nativeSupported":@(native),@"optionalVignettingCalibrationAvailable":@(vignette),@"groups":groups.allValues,@"failures":failures,@"userPhotosOrPathsIncluded":@NO};
 NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
 if(![json writeToFile:@(argv[2]) options:NSDataWritingAtomic error:nil])return 4;
 return failures.count?3:0;
}}
