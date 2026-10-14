#import "LensNativeProfileEngine.h"
#import <math.h>
static NSString*norm(NSString*s){return [s.lowercaseString stringByReplacingOccurrencesOfString:@"[^a-z0-9]" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0,s.length)];}
int main(int argc,char**argv){@autoreleasepool{
 NSURL*here=[NSURL fileURLWithPath:@"Build/Audit" isDirectory:YES];
 NSDictionary*input=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[here URLByAppendingPathComponent:@"catalog-audit-input.json"]] options:0 error:nil];if(!input)return 2;
 NSMutableArray*failures=[NSMutableArray new],*matches=[NSMutableArray new],*variantDifferences=[NSMutableArray new];NSUInteger i=0;
 for(NSDictionary*request in input[@"requests"]){@autoreleasepool{
  NSError*error=nil;NSDictionary*plan=LensNativeProfilePlan(request[@"metadata"],[here URLByAppendingPathComponent:@"../../Resources/LensBridge/db"],[here URLByAppendingPathComponent:@"../../Vendor/Lib/liblensfun.0.3.4.dylib"],[request[@"width"]unsignedIntegerValue],[request[@"height"]unsignedIntegerValue],&error);
  NSDictionary*r=plan[@"report"];BOOL correct=NO;
  if(plan)for(NSString*alias in r[@"matchedLensIdentityNames"])if([norm(alias)isEqual:norm(request[@"expectedLens"])])correct=YES;
  if(correct&&request[@"expectedCameraCrop"])correct=[r[@"cameraMount"]isEqual:request[@"expectedCameraMount"]]&&fabs([r[@"interpolatedCalibration"][@"cameraCropFactor"]doubleValue]-[request[@"expectedCameraCrop"]doubleValue])<1e-5;
  if(!correct)[failures addObject:@{@"id":request[@"id"],@"expectedLens":request[@"expectedLens"],@"metadata":request[@"metadata"],@"reason":error.localizedDescription?:@"matched-different-model",@"matchedLens":r[@"lens"]?:@""}];
  else {
   NSDictionary*c=r[@"interpolatedCalibration"];
   BOOL variantMatches=fabs([c[@"lensCropFactor"]doubleValue]-[request[@"expectedCrop"]doubleValue])<1e-5&&[c[@"lensProjection"]isEqual:request[@"expectedProjection"]]&&fabs([c[@"lensAspectRatio"]doubleValue]-[request[@"expectedAspectRatio"]doubleValue])<1e-5;
   NSDictionary*match=@{@"id":request[@"id"],@"lens":r[@"lens"],@"camera":r[@"camera"],@"identityMethod":r[@"matchingIdentityMethod"],@"cameraMethod":r[@"cameraIdentityMethod"]?:@"legacy",@"cameraCrop":c[@"cameraCropFactor"],@"cameraMount":r[@"cameraMount"],@"distortionAvailable":r[@"distortionProfileAvailable"],@"tcaAvailable":r[@"tcaProfileAvailable"],@"vignettingAvailable":r[@"vignettingProfileAvailable"],@"selectedCrop":c[@"lensCropFactor"],@"requestedCrop":request[@"expectedCrop"],@"selectedProjection":c[@"lensProjection"],@"requestedProjection":request[@"expectedProjection"],@"selectedAspectRatio":c[@"lensAspectRatio"],@"requestedAspectRatio":request[@"expectedAspectRatio"],@"calibrationVariantMatchesWitness":@(variantMatches)};
   [matches addObject:match];if(!variantMatches)[variantDifferences addObject:match];
  }
  if(++i%100==0){printf("Audited %lu / %lu; failures %lu\n",(unsigned long)i,(unsigned long)[input[@"requests"]count],(unsigned long)failures.count);fflush(stdout);}
 }}
 NSDictionary*out=@{@"sourceCommit":input[@"sourceCommit"],@"scope":input[@"testedScope"],@"cameraEntries":input[@"cameraEntries"],@"lensEntries":input[@"lensEntries"],@"uniqueMakerModels":input[@"uniqueMakerModels"],@"requestCount":@([input[@"requests"]count]),@"matchedCount":@(matches.count),@"failureCount":@(failures.count),@"calibrationVariantDifferenceCount":@(variantDifferences.count),@"calibrationVariantDifferences":variantDifferences,@"skipped":input[@"skipped"],@"failures":failures,@"matches":matches};
 [[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil]writeToURL:[here URLByAppendingPathComponent:argc>1?@(argv[1]):@"catalog-audit-results.json"] atomically:YES];
 printf("Completed: %lu matched, %lu failed, %lu skipped, %lu calibration variant differences.\n",(unsigned long)matches.count,(unsigned long)failures.count,(unsigned long)[input[@"skipped"]count],(unsigned long)variantDifferences.count);
 return 0; // An audit records gaps; it is not a claim of universal support.
}}
