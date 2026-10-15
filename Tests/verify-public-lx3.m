#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <CommonCrypto/CommonDigest.h>
#import "LensNativeProfileEngine.h"
#import "LensCaptureModeEvidence.h"
#import "LensRecommendationPolicy.h"

static NSString *digest(NSData *data) {
 unsigned char value[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,value);
 NSMutableString *result=[NSMutableString new];for(unsigned i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[result appendFormat:@"%02x",value[i]];return result;
}
int main(){@autoreleasepool{
 NSURL *root=[NSURL fileURLWithPath:NSFileManager.defaultManager.currentDirectoryPath];
 NSDictionary *fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"Tests/Fixtures/LX3-public-raw.json"]] options:0 error:nil];
 if(![fixture[@"files"]isKindOfClass:NSArray.class])return 1;
 NSMutableArray *verified=[NSMutableArray new],*missing=[NSMutableArray new];
 for(NSDictionary *item in fixture[@"files"]){@autoreleasepool{
  NSURL *raw=[root URLByAppendingPathComponent:[@"Tests/PrivateRAW" stringByAppendingPathComponent:item[@"file"]]];
  if(![NSFileManager.defaultManager fileExistsAtPath:raw.path]){[missing addObject:item[@"file"]];continue;}
  NSData *original=[NSData dataWithContentsOfURL:raw];if(![digest(original)isEqual:item[@"sha256"]])return 2;
  NSError *error=nil;NSDictionary *metadata=LensReadRawMetadata(raw,[root URLByAppendingPathComponent:@"Resources/LensBridge/exiftool/exiftool"],&error);
  NSDictionary *mode=LensCaptureModeEvidence(metadata[@"rawCaptureMetadata"]);
  NSArray *size=item[@"activeSize"];
  if(!metadata||![metadata[@"Model"]isEqual:@"DMC-LX3"]||![mode[@"variant"]isEqual:item[@"mode"]]||[mode[@"activeWidth"]unsignedIntegerValue]!=[size[0]unsignedIntegerValue]||[mode[@"activeHeight"]unsignedIntegerValue]!=[size[1]unsignedIntegerValue])return 3;
  if(item[@"focalMM"]&&fabs([metadata[@"FocalLength"]doubleValue]-[item[@"focalMM"]doubleValue])>.0001)return 4;
  if(item[@"fNumber"]&&fabs([metadata[@"FNumber"]doubleValue]-[item[@"fNumber"]doubleValue])>.0001)return 5;
  CIRAWFilter *filter=[CIRAWFilter filterWithImageURL:raw];CIImage *image=filter.outputImage;
  if(!image||image.extent.size.width!=[size[0]doubleValue]||image.extent.size.height!=[size[1]doubleValue])return 6;
  double scale=192.0/MAX(image.extent.size.width,image.extent.size.height);
  CIImage *preview=[image imageByApplyingTransform:CGAffineTransformMakeScale(scale,scale)];
  CIContext *context=[CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}];
  CGImageRef rendered=[context createCGImage:preview fromRect:preview.extent];
  if(!rendered)return 7;
  NSUInteger width=CGImageGetWidth(rendered),height=CGImageGetHeight(rendered);
  NSMutableData *rgba=[NSMutableData dataWithLength:width*height*4];CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef bitmap=CGBitmapContextCreate(rgba.mutableBytes,width,height,8,width*4,color,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);CGColorSpaceRelease(color);
  if(!bitmap){CGImageRelease(rendered);return 8;}
  CGContextDrawImage(bitmap,CGRectMake(0,0,width,height),rendered);CGContextRelease(bitmap);CGImageRelease(rendered);
  const unsigned char *bytes=rgba.bytes;unsigned minimum=765,maximum=0;
  for(NSUInteger i=0;i<width*height;i++){unsigned sum=bytes[i*4]+bytes[i*4+1]+bytes[i*4+2];minimum=MIN(minimum,sum);maximum=MAX(maximum,sum);}
  if(maximum-minimum<10)return 8;NSString *pixelHash=digest(rgba);
  NSDictionary *plan=LensNativeProfilePlanIncludingGeometry(metadata,[root URLByAppendingPathComponent:@"Resources/LensBridge/db"],[root URLByAppendingPathComponent:@"Vendor/Lib/liblensfun.0.3.4.dylib"],width,height,&error);
  NSDictionary *report=plan[@"report"],*support=metadata[@"nativeCorrectionSupport"];
  if(!plan||![report[@"cameraIdentityMethod"]isEqual:@"raw-sensor-active-area-aspect-mode"]||![report[@"matchingIdentityMethod"]isEqual:@"fixed-built-in-camera-lens"]||fabs([report[@"interpolatedCalibration"][@"cameraCropFactor"]doubleValue]-[item[@"cameraCropFactor"]doubleValue])>.0001)return 9;
  if(![support[@"probeSucceeded"]boolValue])return 10;
  BOOL native=[support[@"lensCorrectionSupported"]boolValue];
  if(native&&(![report[@"geometryHandledByNative"]boolValue]||plan[@"normalizedGeometryMapsLZFSE"]||![LensRecommendationPolicy(plan)[@"strengths"]isEqual:@[@0,@0,@0]]||[LensRecommendationPolicy(plan)[@"vignettingAutomatic"]boolValue]))return 11;
  if(![digest([NSData dataWithContentsOfURL:raw])isEqual:item[@"sha256"]])return 12;
  [verified addObject:@{@"fixture":item,@"originalUnchanged":@YES,@"decodedFullExtent":@[@(image.extent.size.width),@(image.extent.size.height)],@"renderedPreviewSize":@[@(width),@(height)],@"renderedPreviewPixelSHA256":pixelHash,@"renderedRGBSumRange":@[@(minimum),@(maximum)],@"automaticFocalMM":metadata[@"FocalLength"],@"automaticFNumber":metadata[@"FNumber"],@"captureMode":mode,@"nativeSupport":support,@"cameraProfileID":report[@"matchedCameraProfileID"],@"lensProfileID":report[@"matchedLensProfileID"],@"cameraCropFactor":report[@"interpolatedCalibration"][@"cameraCropFactor"],@"extraGeometrySkipped":@([report[@"geometryHandledByNative"]boolValue])}];
 }}
 NSDictionary *result=@{@"scope":@"Optional complete public LX3 RAW: original checksum, capture mode, automatic profile identity, actual Core Image preview decoding and native priority; not Pixelmator GUI/save/reopen or optical accuracy verification",@"verifiedFiles":verified,@"missingFiles":missing,@"photosIncluded":@NO};
 NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
 if(![json writeToURL:[root URLByAppendingPathComponent:@"Build/Tests/public-lx3-verification.json"] atomically:YES])return 13;
 printf("Complete LX3 RAW checked: %lu; optional absent: %lu. No optical or GUI claim.\n",(unsigned long)verified.count,(unsigned long)missing.count);
}}
