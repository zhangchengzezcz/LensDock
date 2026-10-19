#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>
#import "LensNativeProfileEngine.h"
#import "LensNativeState.h"
#import "LensCorrectionSettings.h"

typedef struct { double v[8]; } PreviewTransform;
@interface NSObject(FractionalPreviewEffect)
- (CIImage*)applyFor:(CIImage*)input scale:(CGPoint)scale extent:(CGRect)extent bounds:(CGRect)bounds layerOriginalSizeInBacking:(CGSize)size layerCombinedTransformInBacking:(PreviewTransform)transform;
@end

static NSString *sha(NSData *data) {
 unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
 NSMutableString *result=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[result appendFormat:@"%02x",digest[i]];return result;
}
static NSDictionary *compare(CIContext *context,CIImage *corrected,CIImage *reference,CGAffineTransform transform) {
 CIImage *a=[corrected imageByApplyingTransform:transform],*b=[reference imageByApplyingTransform:transform];
 CGRect bounds=CGRectIntegral(b.extent);if(!CGRectEqualToRect(a.extent,b.extent))return nil;
 NSUInteger w=bounds.size.width,h=bounds.size.height;
 NSMutableData *actual=[NSMutableData dataWithLength:w*h],*expected=[NSMutableData dataWithLength:w*h];
 [context render:a toBitmap:actual.mutableBytes rowBytes:w bounds:bounds format:kCIFormatA8 colorSpace:nil];
 [context render:b toBitmap:expected.mutableBytes rowBytes:w bounds:bounds format:kCIFormatA8 colorSpace:nil];
 const unsigned char *x=actual.bytes,*y=expected.bytes;NSUInteger different=0,maximum=0,nonopaque=0,minimum=255,rowCount=0;
 NSMutableArray *rows=[NSMutableArray new];
 for(NSUInteger row=0;row<h;row++){
  NSUInteger count=0;for(NSUInteger col=0;col<w;col++){
   NSUInteger i=row*w+col,delta=abs((int)x[i]-(int)y[i]);different+=delta!=0;maximum=MAX(maximum,delta);minimum=MIN(minimum,x[i]);
   if(x[i]!=255){nonopaque++;count++;}
  }
  if(count){rowCount++;if(rows.count<8)[rows addObject:@{@"row":@(row),@"count":@(count)}];}
 }
 return @{@"outputBounds":@[@(bounds.origin.x),@(bounds.origin.y),@(w),@(h)],
  @"scale":@(transform.a),@"translation":@[@(transform.tx),@(transform.ty)],
  @"differentAlphaPixels":@(different),@"maximumAlphaDelta8Bit":@(maximum),
  @"nonopaquePixels":@(nonopaque),@"minimumAlpha8Bit":@(minimum),@"nonopaqueRows":@(rowCount),
  @"firstNonopaqueRows":rows,@"actualAlphaSHA256":sha(actual),@"referenceAlphaSHA256":sha(expected)};
}
int main(){@autoreleasepool{
 if(!getenv("LENS_FULL_RENDER_TEST")){puts("Fractional preview check skipped; set LENS_FULL_RENDER_TEST=1 with the pinned public A6000 RAW supplied locally.");return 0;}
 NSURL *raw=[NSURL fileURLWithPath:@"Tests/PrivateRAW/ILCE-6000.ARW"];
 NSString *rawSHA=@"ce8b4957281a817d52a07a691e2468567b6c78223bd0b514ffc1c65b002b8d89";
 if(![sha([NSData dataWithContentsOfURL:raw])isEqual:rawSHA])return 1;
 void *library=dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL);
 PreviewTransform *identity=library?dlsym(library,"PTProjectiveTransformIdentity"):NULL;if(!identity)return 2;
 NSDictionary *metadata=LensReadRawMetadata(raw,[NSURL fileURLWithPath:@"Resources/LensBridge/exiftool/exiftool"],nil);
 if(![metadata[@"Model"]isEqual:@"ILCE-6000"]||[metadata[@"FocalLength"]doubleValue]!=39||[metadata[@"FNumber"]doubleValue]!=5)return 3;
 NSDictionary *generated=nil;@autoreleasepool{generated=LensNativeProfilePlanIncludingGeometry(metadata,[NSURL fileURLWithPath:@"Resources/LensBridge/db"],[NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"],6000,4000,nil);}
 if(!generated)return 4;NSMutableDictionary *plan=[generated mutableCopy],*report=[generated[@"report"]mutableCopy];report[@"workingTransfer"]=@"encoded_sRGB";plan[@"report"]=report;
 NSDictionary *settings=@{@"distortionEnabled":@YES,@"distortionStrength":@100,@"tcaEnabled":@YES,@"tcaStrength":@100,@"vignettingEnabled":@NO,@"vignettingStrength":@50,@"constrainCropEnabled":@YES};
 id effects=nil;@autoreleasepool{id initial=LensEffectsForCorrectionPlan(plan,[NSData dataWithContentsOfFile:@"Resources/native-effects-template.json"],settings,nil,nil);effects=initial?LensEffectsFromJSON(LensEffectsJSON(initial,nil)):nil;}
 if(!effects)return 5;CGRect full=CGRectMake(0,0,6000,4000);
 // An opaque constant isolates sampling coverage. This is deliberately not a
 // decoded photo or a replacement for the application's full PNG export test.
 CIImage *reference=[[CIImage imageWithColor:[CIColor colorWithRed:.2 green:.3 blue:.4 alpha:1]]imageByCroppingToRect:full];
 CIImage *corrected=[effects applyFor:reference scale:CGPointMake(1,1) extent:full bounds:full layerOriginalSizeInBacking:full.size layerCombinedTransformInBacking:*identity];if(!corrected)return 6;
 CIContext *context=[CIContext contextWithOptions:@{kCIContextWorkingColorSpace:NSNull.null,kCIContextOutputColorSpace:NSNull.null,kCIContextWorkingFormat:@(kCIFormatRGBAf)}];NSMutableArray *checks=[NSMutableArray new];
 for(NSNumber *width in @[@6000,@4096,@1600,@1500]){@autoreleasepool{
  NSDictionary *check=compare(context,corrected,reference,CGAffineTransformMakeScale(width.doubleValue/6000.,width.doubleValue/6000.));
  if(!check||[check[@"differentAlphaPixels"]unsignedIntegerValue])return 7;
  BOOL fractional=width.intValue==4096||width.intValue==1600;
  if(fractional?([check[@"nonopaquePixels"]unsignedIntegerValue]!=width.unsignedIntegerValue||[check[@"nonopaqueRows"]unsignedIntegerValue]!=1):[check[@"nonopaquePixels"]unsignedIntegerValue]!=0)return 8;
  [checks addObject:check];printf("Fractional preview width %d: alpha equals uncorrected opaque control, %lu partial pixels.\n",width.intValue,[check[@"nonopaquePixels"]unsignedIntegerValue]);fflush(stdout);
 }}
 NSDictionary *translated=compare(context,corrected,reference,CGAffineTransformMake(4096./6000.,0,0,4096./6000.,17.25,29.125));if(!translated||[translated[@"differentAlphaPixels"]unsignedIntegerValue])return 9;[checks addObject:translated];
 if(![sha([NSData dataWithContentsOfURL:raw])isEqual:rawSHA])return 10;
 NSDictionary *result=@{@"scope":@"Full production calibration and native wrapper using opaque constant source; alpha compared byte-for-byte to an uncorrected cropped constant under identical Core Image scaling. Not a decoded photo or actual GUI PNG export.",@"rawSHA256":rawSHA,@"originalUnchanged":@YES,@"workingTransfer":@"encoded_sRGB",@"checks":checks,@"passed":@YES};
 [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/fractional-preview-verification.json" atomically:YES];
 puts("Fractional preview alpha matches the no-correction scaling control; integer 1:1 and reduced sizes remain opaque.");
}}
