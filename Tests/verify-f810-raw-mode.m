#import "LensNativeProfileEngine.h"
#import "LensCaptureModeEvidence.h"
#import <CommonCrypto/CommonDigest.h>
static NSString*sha(NSData*d){unsigned char h[32];CC_SHA256(d.bytes,(CC_LONG)d.length,h);NSMutableString*s=[NSMutableString new];for(int i=0;i<32;i++)[s appendFormat:@"%02x",h[i]];return s;}
int main(){@autoreleasepool{
 NSDictionary*f=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Tests/Fixtures/F810-raw-mode.json"] options:0 error:nil];NSDictionary*tags=f[@"tags"],*e=LensCaptureModeEvidence(tags);
 if(![e[@"variant"]isEqual:@"standard"]||fabs([e[@"aspectRatio"]doubleValue]-4./3)>1e-9)return 1;
 NSURL*db=[NSURL fileURLWithPath:@"Resources/LensBridge/db"],*lib=[NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"];
 NSMutableDictionary*m=[@{@"Make":@"FUJIFILM",@"Model":@"FinePix F810",@"LensModel":@"FinePix F810 & compatibles (Standard)",@"FocalLength":@7.2,@"FNumber":@4,@"rawCaptureMetadata":tags}mutableCopy];
 NSUInteger plans=0;
 for(NSNumber*focal in @[@7.2,@9.3,@11.9,@13.5,@16.8,@20.2,@24.5,@28.8]){
  m[@"FocalLength"]=focal;NSDictionary*p=LensNativeProfilePlan(m,db,lib,64,48,nil);
  if(!p||![p[@"report"][@"cameraIdentityMethod"]isEqual:@"raw-format-documented-camera-mode"]||fabs([p[@"report"][@"interpolatedCalibration"][@"cameraCropFactor"]doubleValue]-4.5)>1e-6)return 2;plans++;
 }
 m[@"FocalLength"]=@7.2;
 if(LensNativeProfilePlan(m,db,lib,64,36,nil))return 3;
 NSMutableDictionary*preview=[tags mutableCopy];preview[@"ExifIFD:ExifImageWidth"]=@3968;preview[@"ExifIFD:ExifImageHeight"]=@2232;
 if(![LensCaptureModeEvidence(preview)[@"variant"]isEqual:@"standard"])return 4;
 for(NSArray*bad in @[@[@"File:FileType",@"JPEG"],@[@"File:FileType",@"DNG"],@[@"IFD0:Make",@"Panasonic"],@[@"IFD0:Model",@"FinePix F710"],@[@"LensDock:RAFHeaderModel",@"FinePix S5Pro"],@[@"LensDock:RAFHeaderModel",@42],@[@"ExifIFD:DigitalZoomRatio",@2],@[@"ExifIFD:DigitalZoomRatio",@"1"]]){
  NSMutableDictionary*b=[tags mutableCopy];b[bad[0]]=bad[1];if(LensCaptureModeEvidence(b))return 5;
 }
 NSMutableDictionary*missing=[tags mutableCopy];[missing removeObjectForKey:@"LensDock:RAFHeaderModel"];if(LensCaptureModeEvidence(missing))return 6;
 [m removeObjectForKey:@"rawCaptureMetadata"];if(LensNativeProfilePlan(m,db,lib,64,48,nil))return 7;
 m[@"rawCaptureMetadata"]=tags;[m removeObjectForKey:@"LensModel"];if(LensNativeProfilePlan(m,db,lib,64,48,nil))return 8;
 // Verify the production 60-byte reader against an existing upstream RAF
 // metadata container. Relabeling bytes is an explicit parser fixture only.
 NSURL*sample=[NSURL fileURLWithPath:@"Build/Audit/MetadataSamples/FujiFilm.raf"],*tool=[NSURL fileURLWithPath:@"Resources/LensBridge/exiftool/exiftool"];
 NSMutableDictionary*parser=[NSMutableDictionary new];NSData*original=[NSData dataWithContentsOfURL:sample];
 if(original){
  NSDictionary*read=LensReadRawCaptureMetadata(sample,tool,nil);
  if(![read[@"LensDock:RAFHeaderModel"]isEqual:@"FinePix S5Pro"]||LensCaptureModeEvidence(read))return 9;
  NSURL*temp=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"RAF"]]];
  NSMutableData*changed=[original mutableCopy];const char*replacement="FinePix F810";memset((char*)changed.mutableBytes+28,0,32);memcpy((char*)changed.mutableBytes+28,replacement,strlen(replacement));
  if(![changed writeToURL:temp atomically:YES])return 10;
  NSDictionary*headerOnly=LensReadRawCaptureMetadata(temp,tool,nil);
  [NSFileManager.defaultManager removeItemAtURL:temp error:nil];
  if(![headerOnly[@"LensDock:RAFHeaderModel"]isEqual:@"FinePix F810"]||LensCaptureModeEvidence(headerOnly))return 11;
  if(![original isEqual:[NSData dataWithContentsOfURL:sample]])return 12;
  parser[@"upstreamContainerSHA256"]=sha(original);parser[@"headerAndEmbeddedModelMismatchRejected"]=@YES;
 }
 NSDictionary*r=@{@"scope":f[@"scope"],@"manual":f[@"manual"],@"documentedStandardModeSelected":@YES,@"explicitLensPlansChecked":@(plans),@"cameraCropFactor":@4.5,@"widescreenOutputRejected":@YES,@"previewSizeNotUsed":@YES,@"missingHeaderOrUnknownLensStillRejected":@YES,@"opticalCoefficientsChanged":@NO,@"realF810RAWTested":@NO,@"parserFixtures":parser};
 [[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/f810-raw-mode-verification.json" atomically:YES];
 puts("F810 documented RAW standard mode, eight exact-lens routes and inconsistent/missing evidence rejection passed; no real F810 RAW or optical claim.");return 0;
}}
