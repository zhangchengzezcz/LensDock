#import "LensNativeProfileEngine.h"
#import "LensCaptureParameters.h"
#import <ImageIO/ImageIO.h>

// Generated ImageIO containers and a controlled duplicate-tag reader model the
// EXIF/MakerNote collision found in a real CR3. No private RAW is redistributed.
static BOOL writeContainer(NSURL *url,BOOL captureFields){
 unsigned char pixel[4]={128,128,128,255};CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();CGContextRef context=CGBitmapContextCreate(pixel,1,1,8,4,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(space);if(!context)return NO;
 CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);CGImageDestinationRef destination=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.tiff"),1,NULL);if(!destination){CGImageRelease(image);return NO;}
 NSDictionary *exif=captureFields?@{@"FocalLength":@104,@"FNumber":@5.6,@"SubjectDistance":@7}:@{};
 CGImageDestinationAddImage(destination,image,(__bridge CFDictionaryRef)@{@"{TIFF}":@{@"Make":@"Canon",@"Model":@"Canon EOS R50 V"},@"{Exif}":exif});BOOL result=CGImageDestinationFinalize(destination);CFRelease(destination);CGImageRelease(image);return result;
}
int main(){@autoreleasepool{
 NSURL *directory=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
 NSURL *reader=[directory URLByAppendingPathComponent:@"duplicate-tag-reader.pl"];
 NSString *script=@"use strict; use warnings; my $grouped=grep { $_ eq '-G1' } @ARGV; print $grouped ? '[{\"IFD0:Make\":\"Canon\",\"IFD0:Model\":\"Canon EOS R50 V\",\"ExifIFD:LensModel\":\"RF100-400mm F5.6-8 IS USM\",\"ExifIFD:FocalLength\":104,\"Canon:FocalLength\":100,\"Track4:FocalLength\":104,\"ExifIFD:FNumber\":5.6,\"Canon:FNumber\":8,\"ExifIFD:SubjectDistance\":7,\"Canon:SubjectDistance\":3,\"Nikon:FocusDistance\":2.5}]' : '[{\"FocalLength\":100,\"FNumber\":8,\"SubjectDistance\":3,\"LensID\":\"Canon RF 100-400mm F5.6-8 IS USM\"}]';\n";
 if(![script writeToURL:reader atomically:YES encoding:NSUTF8StringEncoding error:nil])return 1;
 for(NSNumber *includeStandard in @[@YES,@NO]){
  NSURL *file=[directory URLByAppendingPathComponent:[includeStandard boolValue]?@"with-exif.tiff":@"without-capture-exif.tiff"];if(!writeContainer(file,includeStandard.boolValue))return 2;
  NSDictionary *metadata=LensReadRawMetadata(file,reader,nil);
  if(!metadata||fabs([metadata[@"FocalLength"]doubleValue]-104)>1e-8||fabs([metadata[@"FNumber"]doubleValue]-5.6)>1e-8||fabs([metadata[@"SubjectDistance"]doubleValue]-7)>1e-8||fabs([metadata[@"FocusDistance"]doubleValue]-2.5)>1e-8)return 3;
 }
 // ImageIO's valid capture fields must also survive an older ungrouped
 // supplemental reader. Other MakerNote-only fields remain usable.
 NSString *legacy=@"print '[{\"FocalLength\":100,\"FNumber\":8,\"SubjectDistance\":3,\"FocusDistance\":2.5}]';\n";[legacy writeToURL:reader atomically:YES encoding:NSUTF8StringEncoding error:nil];
 NSDictionary *metadata=LensReadRawMetadata([directory URLByAppendingPathComponent:@"with-exif.tiff"],reader,nil);
 if(fabs([metadata[@"FocalLength"]doubleValue]-104)>1e-8||fabs([metadata[@"FNumber"]doubleValue]-5.6)>1e-8||fabs([metadata[@"SubjectDistance"]doubleValue]-7)>1e-8||fabs([metadata[@"FocusDistance"]doubleValue]-2.5)>1e-8)return 4;
 // Sony's Composite:FocusDistance is computed from FocusPosition and focal
 // length. It is not a recorded distance and must not win over a direct tag
 // or appear as an automatically measured scalar in the parameter fields.
 NSArray *distanceCases=@[
  @{@"grouped":@{@"Composite:FocusDistance":@1.95},@"expectedDisplay":@1000},
  @{@"grouped":@{@"Composite:FocusDistance":@1.95,@"Nikon:FocusDistance":@2.5},@"expectedDistance":@2.5,@"expectedDisplay":@2.5},
  @{@"grouped":@{@"Composite:FocusDistance":@1.95,@"ExifIFD:SubjectDistance":@7},@"expectedDisplay":@7}
 ];
 for(NSDictionary *test in distanceCases){
  NSData *json=[NSJSONSerialization dataWithJSONObject:@[test[@"grouped"]] options:0 error:nil];
  NSString *payload=[[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding];
  NSString *derivedReader=[NSString stringWithFormat:@"print '%@';\n",payload];
  if(![derivedReader writeToURL:reader atomically:YES encoding:NSUTF8StringEncoding error:nil])return 5;
  NSDictionary *actual=LensReadRawMetadata([directory URLByAppendingPathComponent:@"without-capture-exif.tiff"],reader,nil);
  if(!actual||(test[@"expectedDistance"]?![actual[@"FocusDistance"]isEqual:test[@"expectedDistance"]]:actual[@"FocusDistance"]!=nil)||fabs([LensCaptureParameterDisplayValues(actual)[2]doubleValue]-[test[@"expectedDisplay"]doubleValue])>1e-8)return 6;
 }
 [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
 puts("Standard exposure EXIF survives conflicting MakerNote/track copies; optional MakerNote distance remains available.");
}}
