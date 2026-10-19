#import "LensNativeProfileEngine.h"
#import <math.h>
int main(int argc,char**argv){@autoreleasepool{
 NSURL*db=[NSURL fileURLWithPath:argc>1?@(argv[1]):@"Resources/LensBridge/db"],*lib=[NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"];
 NSString*model=@"Tamron 70-300mm F/4.5-6.3 Di III RXD A047Z/E";
 NSArray*cameras=@[@{@"Make":@"Nikon Corporation",@"Model":@"Nikon Z5_2"},@{@"Make":@"Sony",@"Model":@"ILCE-7M3"}];
 // Independent fixed values from upstream commit 3e14a04 (ptlens/poly3).
 NSArray*points=@[@[@70,@.0014354,@(-.0042749),@.0018292,@1.0000829,@1.0000258],@[@100,@(-.0042268),@.0210729,@(-.0056595),@1.0000199,@.9999705],@[@135,@.0028748,@.0079077,@.0041324,@.9999919,@.9999382],@[@200,@(-.0108953),@.0541951,@(-.0436445),@.9999501,@.9999018],@[@300,@.003306,@.0040682,@.0065768,@.9999011,@.9998533]];
 NSUInteger checked=0;
 for(NSDictionary*camera in cameras)for(NSArray*point in points){
  NSMutableDictionary*m=[camera mutableCopy];m[@"LensModel"]=model;m[@"FocalLength"]=point[0];m[@"FNumber"]=@8;
  NSDictionary*p=LensNativeProfilePlan(m,db,lib,96,64,nil),*r=p[@"report"],*c=r[@"interpolatedCalibration"];
  if(!p||![r[@"matchedLensIdentityNames"]containsObject:model])return 1;
  if(fabs([c[@"lensCropFactor"]doubleValue]-1)>1e-6||![r[@"distortionProfileAvailable"]boolValue]||![r[@"tcaProfileAvailable"]boolValue])return 2;
  if([r[@"vignettingProfileAvailable"]boolValue]||p[@"linearGainFloat32BottomUp"]||c[@"vignetting"])return 3;
  NSArray*d=c[@"distortion"][@"terms"],*t=c[@"tca"][@"terms"];
  if([c[@"distortion"][@"model"]intValue]!=3||[c[@"tca"][@"model"]intValue]!=2||d.count!=3||t.count!=6)return 4;
  for(int i=0;i<3;i++)if(fabs([d[i]doubleValue]-[point[i+1]doubleValue])>1e-7)return 5;
  for(int i=0;i<6;i++)if(fabs([t[i]doubleValue]-(i<2?[point[i+4]doubleValue]:0))>1e-7)return 6;
  checked++;
 }
 NSMutableDictionary*generic=[cameras[1]mutableCopy];generic[@"LensModel"]=@"Tamron 70-300mm F/4.5-6.3 Di III RXD";generic[@"FocalLength"]=@100;generic[@"FNumber"]=@8;
 if(LensNativeProfilePlan(generic,db,lib,96,64,nil))return 7; // Same-sensor calibration ambiguity is not permission to guess.
 generic[@"LensIDName"]=@"E 70-300mm F4.5-6.3 A047";
 NSDictionary*old=LensNativeProfilePlan(generic,db,lib,96,64,nil);
 if(!old||![old[@"report"][@"matchingIdentitySource"]isEqual:@"LensIDName"]||![old[@"report"][@"matchedLensIdentityNames"]containsObject:generic[@"LensIDName"]])return 8;
 NSDictionary*r=@{@"scope":@"Upstream coefficient/identity routing regression with controlled metadata; no A047 real RAW or optical-accuracy claim",@"sourceCommit":@"3e14a04ba6a5c02a65fcce50d4f1987c705dc196",@"newProfileCases":@(checked),@"mounts":@[@"Nikon Z",@"Sony E"],@"calibratedFocalLengths":@[@70,@100,@135,@200,@300],@"upstreamTermsChecked":@YES,@"missingVignettingNeverInvented":@YES,@"genericNameAmbiguityRejected":@YES,@"recordedAlternateLensIdentityUsed":@YES,@"realA047RAWTested":@NO};
 [[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/a047-profile-update-verification.json" atomically:YES];
 puts("A047 upstream coefficients across both mounts, absent vignette and identity ambiguity checks passed.");
}}
