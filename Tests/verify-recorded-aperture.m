#import "LensNativeProfileEngine.h"
#import "LensCaptureParameters.h"
#import <ImageIO/ImageIO.h>

// Generated metadata containers exercise the real ImageIO + bundled ExifTool
// readers, not mocked tag dictionaries. They are not RAW/optical test images.
static BOOL writeContainer(NSURL*url,NSDictionary*exif){
 unsigned char pixels[16*16*4]={0};CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();CGContextRef context=CGBitmapContextCreate(pixels,16,16,8,64,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(space);if(!context)return NO;
 CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);CGImageDestinationRef destination=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.tiff"),1,NULL);if(!destination){CGImageRelease(image);return NO;}
 NSDictionary*properties=@{@"{TIFF}":@{@"Make":@"Canon",@"Model":@"Canon EOS 40D"},@"{Exif}":exif};CGImageDestinationAddImage(destination,image,(__bridge CFDictionaryRef)properties);BOOL success=CGImageDestinationFinalize(destination);CFRelease(destination);CGImageRelease(image);return success;
}

int main(){@autoreleasepool{
 NSURL*here=[NSURL fileURLWithPath:@"Build/Tests" isDirectory:YES],*tool=[here URLByAppendingPathComponent:@"resources/exiftool/exiftool"],*db=[here URLByAppendingPathComponent:@"resources/db"],*lib=[here URLByAppendingPathComponent:@"lib/liblensfun.0.3.4.dylib"];
 NSURL*temporary=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:temporary withIntermediateDirectories:YES attributes:nil error:nil];NSURL*missingTool=[temporary URLByAppendingPathComponent:@"unavailable-exiftool"];
 NSArray*cases=@[@{@"name":@"apex-only",@"apex":@5,@"expected":@(sqrt(32))},@{@"name":@"f-number-priority",@"apex":@5,@"fNumber":@4,@"expected":@4},@{@"name":@"maximum-only",@"expected":@0},@{@"name":@"apex-zero",@"apex":@0,@"expected":@1},@{@"name":@"apex-overflow",@"apex":@100000,@"expected":@0},@{@"name":@"zero-f-number-with-apex",@"fNumber":@0,@"apex":@5,@"expected":@(sqrt(32))}];
 NSMutableArray*checks=[NSMutableArray new];
 for(NSDictionary*test in cases){
  NSMutableDictionary*exif=[@{@"LensModel":@"Canon EF-S 17-85mm f/4-5.6 IS USM",@"FocalLength":@17,@"MaxApertureValue":@1}mutableCopy];if(test[@"apex"])exif[@"ApertureValue"]=test[@"apex"];if(test[@"fNumber"])exif[@"FNumber"]=test[@"fNumber"];
  NSURL*file=[temporary URLByAppendingPathComponent:[test[@"name"]stringByAppendingPathExtension:@"tiff"]];if(!writeContainer(file,exif))return 1;
  CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)file,NULL);NSDictionary*stored=source?CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)):nil;if(source)CFRelease(source);
  if(!stored||![stored[@"{Exif}"][@"MaxApertureValue"]isEqual:@1]||(!test[@"fNumber"]&&stored[@"{Exif}"][@"FNumber"])||(test[@"apex"]&&fabs([stored[@"{Exif}"][@"ApertureValue"]doubleValue]-[test[@"apex"]doubleValue])>1e-9))return 2;
  NSMutableArray*readers=[NSMutableArray new];
  for(NSURL*reader in @[tool,missingTool]){
   NSError*error=nil;NSDictionary*m=LensReadRawMetadata(file,reader,&error);double expected=[test[@"expected"]doubleValue];if(!m||fabs([m[@"FNumber"]doubleValue]-expected)>1e-8||(!expected&&m[@"FNumber"])){fprintf(stderr,"Aperture read failed: case=%s reader=%s expected=%.9g actual=%s\n",[test[@"name"]UTF8String],reader==tool?"ExifTool":"ImageIO",expected,[[m[@"FNumber"]description]UTF8String]?:"missing");return 3;}
   NSDictionary*p=LensNativeProfilePlan(m,db,lib,64,48,&error);if(!p||(!expected&&[p[@"report"][@"vignettingProfileAvailable"]boolValue]))return 4;
   NSArray*defaults=LensCaptureParameterDisplayValues(m);if(expected?(fabs([defaults[1]doubleValue]-expected)>1e-8):defaults[1]!=NSNull.null)return 5;
   [readers addObject:@{@"reader":reader==tool?@"ImageIO+bundled-ExifTool":@"ImageIO-fallback",@"actualFNumber":m[@"FNumber"]?:NSNull.null,@"automaticPlanGenerated":@YES}];
  }
  [checks addObject:@{@"case":test[@"name"],@"readers":readers}];
 }
 [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];NSDictionary*out=@{@"scope":@"Generated TIFF EXIF containers through actual metadata readers and native matching; not RAW decoder/optical accuracy or host GUI proof",@"recordedApertureValueRecoveredAutomatically":@YES,@"ExifToolFNumberNotConvertedTwice":@YES,@"ImageIOAPEXConvertedOnce":@YES,@"validFNumberHasPriority":@YES,@"zeroAPEXMeansF1":@YES,@"maximumApertureAndLensNameNeverUsedAsCaptureAperture":@YES,@"unknownApertureStaysMissingAndVignettingOff":@YES,@"checks":checks};
 [[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil]writeToURL:[here URLByAppendingPathComponent:@"recorded-aperture-verification.json"] atomically:YES];puts("Recorded exposure aperture recovered automatically; maximum aperture is never substituted.");
}}
