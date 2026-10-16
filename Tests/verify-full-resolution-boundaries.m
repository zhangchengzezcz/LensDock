#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>
#import <sys/resource.h>
#import "LensNativeProfileEngine.h"
#import "LensNativeState.h"
#import "LensCorrectionSettings.h"
typedef struct {double v[8];} FullBoundaryTransform;
@interface NSObject(FullBoundaryEffect)
- (CIImage*)applyFor:(CIImage*)input scale:(CGPoint)scale extent:(CGRect)extent bounds:(CGRect)bounds layerOriginalSizeInBacking:(CGSize)size layerCombinedTransformInBacking:(FullBoundaryTransform)transform;
@end
static NSString*digest(NSData*data){unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);NSMutableString*s=[NSMutableString new];for(NSUInteger i=0;i<sizeof(bytes);i++)[s appendFormat:@"%02x",bytes[i]];return s;}
static double interpolate(const float*data,NSUInteger w,NSUInteger h,double x,double y,int c){
 NSUInteger ix=MIN(w-2,(NSUInteger)floor(x)),iy=MIN(h-2,(NSUInteger)floor(y));double fx=x-ix,fy=y-iy;
 return (1-fy)*((1-fx)*data[(iy*w+ix)*2+c]+fx*data[(iy*w+ix+1)*2+c])+fy*((1-fx)*data[((iy+1)*w+ix)*2+c]+fx*data[((iy+1)*w+ix+1)*2+c]);
}
// Independently decode persisted numeric fields, in original bottom-up pixels.
static double coordinate(const float*grid,const unsigned char*residual,NSUInteger w,NSUInteger h,NSUInteger mw,NSUInteger mh,NSUInteger x,NSUInteger y,int c,double step){
 double value=interpolate(grid,mw,mh,(double)x*(mw-1)/(w-1),(double)y*(mh-1)/(h-1),c)+(c?y:x)+.5;
 return value+((int)residual[(y*w+x)*2+c]-128)*step;
}
int main(){@autoreleasepool{
 if(!getenv("LENS_FULL_RENDER_TEST")){puts("Full-resolution boundary check skipped; set LENS_FULL_RENDER_TEST=1 with the pinned public A6000 RAW supplied locally.");return 0;}
 NSURL*raw=[NSURL fileURLWithPath:@"Tests/PrivateRAW/ILCE-6000.ARW"];
 NSString*expectedSHA=@"ce8b4957281a817d52a07a691e2468567b6c78223bd0b514ffc1c65b002b8d89";
 if(![digest([NSData dataWithContentsOfURL:raw])isEqual:expectedSHA]){fprintf(stderr,"Pinned public A6000 RAW missing or mismatched.\n");return 1;}
 void*foundation=dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL);if(!foundation)return 2;
 FullBoundaryTransform*identity=dlsym(foundation,"PTProjectiveTransformIdentity");if(!identity)return 3;
 NSError*error=nil;const NSUInteger w=6000,h=4000;
 NSDictionary*metadata=LensReadRawMetadata(raw,[NSURL fileURLWithPath:@"Resources/LensBridge/exiftool/exiftool"],&error);
 if(!metadata||![metadata[@"Model"]isEqual:@"ILCE-6000"]||[metadata[@"FocalLength"]doubleValue]!=39||[metadata[@"FNumber"]doubleValue]!=5)return 4;
 double start=CFAbsoluteTimeGetCurrent();NSDictionary*generated=nil;
 // Match the production background-generation pool: temporary dense fields
 // must drain before coding/rendering rather than live for the entire probe.
 @autoreleasepool{generated=LensNativeProfilePlanIncludingGeometry(metadata,[NSURL fileURLWithPath:@"Resources/LensBridge/db"],[NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"],w,h,&error);}
 double generationSeconds=CFAbsoluteTimeGetCurrent()-start;printf("Production plan generated in %.3f seconds.\n",generationSeconds);fflush(stdout);
 if(!generated||![generated[@"report"][@"geometryMapEncoding"]isEqual:@"pixel-displacement-residual-RG8-bottom-up-grid-v4"]){NSLog(@"%@",error);return 5;}
 NSDictionary*report=generated[@"report"];NSUInteger mw=[report[@"geometryMapWidth"]unsignedIntegerValue],mh=[report[@"geometryMapHeight"]unsignedIntegerValue];double step=[report[@"geometryResidualStepPixels"]doubleValue];
 NSArray*keys=@[@"D",@"T0",@"T1",@"T2",@"C0",@"C1",@"C2"];NSMutableArray*grids=[NSMutableArray new],*residuals=[NSMutableArray new];const float*g[7];const unsigned char*r[7];
 for(NSUInteger i=0;i<7;i++){NSData*a=[generated[@"normalizedGeometryMapsLZFSE"][keys[i]]decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil],*b=[generated[@"geometryResidualMapsLZFSE"][keys[i]]decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];if(a.length!=mw*mh*8||b.length!=w*h*2)return 6;[grids addObject:a];[residuals addObject:b];g[i]=a.bytes;r[i]=b.bytes;}
 // The source is an opaque constant field, not a decoded photograph. It makes
 // alpha classification independent of scene, demosaicing and color settings.
 CGRect bounds=CGRectMake(0,0,w,h);CIImage*input=[[CIImage imageWithColor:[CIColor colorWithRed:.2 green:.3 blue:.4 alpha:1]]imageByCroppingToRect:bounds];
 CIContext*context=[CIContext contextWithOptions:@{kCIContextWorkingColorSpace:NSNull.null,kCIContextOutputColorSpace:NSNull.null,kCIContextWorkingFormat:@(kCIFormatRGBAf)}];
 NSData*envelope=[NSData dataWithContentsOfFile:@"Resources/native-effects-template.json"];NSMutableArray*checks=[NSMutableArray new];BOOL passed=YES;
 for(NSArray*strengths in @[@[@100,@100,@NO],@[@37,@61,@NO],@[@137,@161,@NO],@[@100,@100,@YES]]){@autoreleasepool{
  double ds=[strengths[0]doubleValue]/100,ts=[strengths[1]doubleValue]/100;NSMutableDictionary*plan=[generated mutableCopy],*rep=[report mutableCopy];rep[@"workingTransfer"]=@"linear";plan[@"report"]=rep;
  BOOL constrained=[strengths[2]boolValue];NSDictionary*settings=@{@"distortionEnabled":@YES,@"distortionStrength":strengths[0],@"tcaEnabled":@YES,@"tcaStrength":strengths[1],@"vignettingEnabled":@NO,@"vignettingStrength":@50,@"constrainCropEnabled":@(constrained)};
  id effects=nil;
  @autoreleasepool{id initial=LensEffectsForCorrectionPlan(plan,envelope,settings,nil,&error);if(!initial)return 7;effects=LensEffectsFromJSON(LensEffectsJSON(initial,&error));}
  if(!effects)return 8;printf("Effect coding roundtrip complete for D %.0f%% / TCA %.0f%%.\n",ds*100,ts*100);fflush(stdout);
  start=CFAbsoluteTimeGetCurrent();CIImage*image=[effects applyFor:input scale:CGPointMake(1,1) extent:bounds bounds:bounds layerOriginalSizeInBacking:bounds.size layerCombinedTransformInBacking:*identity];if(!image)return 9;
  NSMutableData*alpha=[NSMutableData dataWithLength:w*h];[context render:image toBitmap:alpha.mutableBytes rowBytes:w bounds:bounds format:kCIFormatA8 colorSpace:nil];double renderSeconds=CFAbsoluteTimeGetCurrent()-start;
  const unsigned char*a=alpha.bytes;NSUInteger outside=0,inside=0,near=0,wrongOutside=0,wrongInside=0;start=CFAbsoluteTimeGetCurrent();
  if(constrained){inside=w*h;for(NSUInteger i=0;i<w*h;i++)wrongInside+=a[i]!=255;}
  // A predeclared 0.05 px exclusion isolates GPU boundary classification from
  // float/subpixel rounding. Count every excluded pixel explicitly.
  if(!constrained)for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){
   NSUInteger by=h-1-y;double margin=INFINITY;
   for(int c=0;c<3;c++)for(int axis=0;axis<2;axis++){
    double p=(axis?by:x)+.5,value;
    if(ds==1&&ts==1)value=coordinate(g[c+4],r[c+4],w,h,mw,mh,x,by,axis,step);
    else{double d=coordinate(g[0],r[0],w,h,mw,mh,x,by,axis,step),t=coordinate(g[c+1],r[c+1],w,h,mw,mh,x,by,axis,step),combined=coordinate(g[c+4],r[c+4],w,h,mw,mh,x,by,axis,step);value=(1-ts)*((1-ds)*p+ds*d)+ts*((1-ds)*t+ds*combined);}
    margin=fmin(margin,fmin(value-.5,(axis?h:w)-.5-value));
   }
   if(margin<-.05){outside++;wrongOutside+=a[y*w+x]!=0;}else if(margin>.05){inside++;wrongInside+=a[y*w+x]!=255;}else near++;
  }
  if(inside+outside+near!=w*h||!inside||(!constrained&&!outside))return 10;
  double checkSeconds=CFAbsoluteTimeGetCurrent()-start;NSNumber*cropScale=constrained?LensSavedCorrectionProfile(effects)[@"constrainedCrop"][@"scale"]:@1;
  NSDictionary*check=@{@"distortionPercent":strengths[0],@"tcaPercent":strengths[1],@"constrainedCrop":@(constrained),@"constrainedCropScale":cropScale?:@1,@"clearOutsidePixels":@(outside),@"clearInsidePixels":@(inside),@"excludedNearBoundaryPixels":@(near),@"nontransparentOutsidePixels":@(wrongOutside),@"nonopaqueInsidePixels":@(wrongInside),@"renderSeconds":@(renderSeconds),@"CPUAlphaOrIndependentFieldCheckSeconds":@(checkSeconds)};[checks addObject:check];printf("Full-resolution boundary: D %.0f%%, TCA %.0f%%, constrain %d, outside %lu (%lu wrong), inside %lu (%lu wrong), near %lu.\n",ds*100,ts*100,constrained,outside,wrongOutside,inside,wrongInside,near);fflush(stdout);
  if(wrongOutside||wrongInside){passed=NO;break;}
 }}
 if(![digest([NSData dataWithContentsOfURL:raw])isEqual:expectedSHA])return 11;
 struct rusage usage;getrusage(RUSAGE_SELF,&usage);
 NSDictionary*result=@{@"scope":@"Full 6000x4000 production maps from pinned real A6000 RAW and effect coding roundtrip. Three uncropped GPU alpha checks use an independent persisted-field decoder; the constrained-crop check verifies every pixel is opaque. All use a constant opaque source, not a decoded photo, GUI save/reopen/export or optical accuracy validation.",@"dimensions":@[@(w),@(h)],@"rawSHA256":expectedSHA,@"originalUnchanged":@YES,@"automaticFocalMM":metadata[@"FocalLength"],@"automaticFNumber":metadata[@"FNumber"],@"geometryEncoding":report[@"geometryMapEncoding"],@"nearBoundaryExclusionPixels":@.05,@"planGenerationSeconds":@(generationSeconds),@"peakResidentBytes":@(usage.ru_maxrss),@"checks":checks,@"passed":@(passed)};
 [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/full-resolution-boundaries-verification.json" atomically:YES];return passed?0:12;
}}
