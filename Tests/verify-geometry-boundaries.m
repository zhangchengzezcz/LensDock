#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <dlfcn.h>
#import "LensNativeProfileEngine.h"
#import "LensNativeState.h"
#import "LensCorrectionSettings.h"
#import "LensConstrainedCrop.h"
Class LensRegisterVignettingFilter(void);
typedef struct {double v[8];} BoundaryTransform;
@interface NSObject(BoundaryEffect)
- (CIImage*)applyFor:(CIImage*)input scale:(CGPoint)scale extent:(CGRect)extent bounds:(CGRect)bounds layerOriginalSizeInBacking:(CGSize)size layerCombinedTransformInBacking:(BoundaryTransform)transform;
@end
static double toLinear(double v){return v<=.04045?v/12.92:pow((v+.055)/1.055,2.4);}
static double toEncoded(double v){return v<=.0031308?12.92*v:1.055*pow(v,1/2.4)-.055;}
int main(){@autoreleasepool{
 void*foundation=dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL);if(!foundation)return 2;
 BoundaryTransform*identity=dlsym(foundation,"PTProjectiveTransformIdentity");if(!identity)return 3;
 const NSUInteger w=384,h=256;
 NSDictionary*m=@{@"Make":@"Canon",@"Model":@"Canon EOS 40D",@"LensModel":@"Canon EF-S 17-85mm f/4-5.6 IS USM",@"FocalLength":@17,@"FNumber":@4};
 NSDictionary*base=LensNativeProfilePlanFullGeometry(m,[NSURL fileURLWithPath:@"Resources/LensBridge/db"],[NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"],w,h,nil);if(!base)return 4;
 NSData*envelope=[NSData dataWithContentsOfFile:@"Resources/native-effects-template.json"];
 NSMutableData*source=[NSMutableData dataWithLength:w*h*16],*output=[NSMutableData dataWithLength:w*h*16];float*s=source.mutableBytes,*o=output.mutableBytes;
 for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){NSUInteger i=(y*w+x)*4;s[i]=.1+.2*(x+.5)/w;s[i+1]=.1+.2*(y+.5)/h;s[i+2]=.1+.1*(x+.5)/w+.1*(y+.5)/h;s[i+3]=1;}
 CIImage*input=[CIImage imageWithBitmapData:source bytesPerRow:w*16 size:CGSizeMake(w,h) format:kCIFormatRGBAf colorSpace:nil];CIContext*context=[CIContext contextWithOptions:@{kCIContextWorkingColorSpace:NSNull.null,kCIContextOutputColorSpace:NSNull.null,kCIContextWorkingFormat:@(kCIFormatRGBAf)}];
 NSMutableArray*checks=[NSMutableArray new],*constrainedChecks=[NSMutableArray new];NSUInteger croppedChecks=0,scaledCropChecks=0;double croppedWorst=0;
 for(NSString*layout in @[@"dense",@"grid",@"residual"])for(NSArray*shift in @[@[@-12,@0],@[@12,@0],@[@0,@-12],@[@0,@12]]){@autoreleasepool{
  double dx=[shift[0]doubleValue],dy=[shift[1]doubleValue];BOOL noisy=[layout isEqual:@"residual"];
  NSMutableDictionary*maps=[NSMutableDictionary new];
  for(NSString*key in @[@"D",@"T0",@"T1",@"T2",@"C0",@"C1",@"C2"]){
   BOOL d=[key isEqual:@"D"]||[key hasPrefix:@"C"],t=![key isEqual:@"D"];int channel=t?[[key substringFromIndex:1]intValue]:1;
   NSMutableData*field=[NSMutableData dataWithLength:w*h*8];float*f=field.mutableBytes;
   for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){double noise=noisy?((x/13+y/11)%2?.09:-.09):0;NSUInteger i=(y*w+x)*2;f[i]=(x+.5+(d?dx+noise:0)+(t&&channel==0?-7:0))/w;f[i+1]=(y+.5+(d?dy:0)+(t&&channel==2?7:0))/h;}
   maps[key]=[field compressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];
  }
  NSMutableDictionary*dense=[base mutableCopy];dense[@"normalizedGeometryMapsLZFSE"]=maps;
  NSDictionary*layoutPlan=[layout isEqual:@"dense"]?dense:LensCompactGeometryPlan(dense,.001,nil);if(!layoutPlan)return 8;
  if(noisy&&![layoutPlan[@"report"][@"geometryMapEncoding"]isEqual:@"pixel-displacement-residual-RG8-bottom-up-grid-v4"])return 9;
  for(int encoded=0;encoded<2;encoded++)for(int mode=0;mode<4;mode++)for(NSNumber*strength in @[@37,@100,@137]){@autoreleasepool{
  double amount=strength.doubleValue/100,ds=mode&1?amount:0,ts=mode&2?amount:0;
  NSMutableDictionary*plan=[layoutPlan mutableCopy],*report=[layoutPlan[@"report"]mutableCopy];report[@"workingTransfer"]=encoded?@"encoded_sRGB":@"linear";plan[@"report"]=report;
  NSDictionary*settings=@{@"distortionEnabled":@(!!(mode&1)),@"distortionStrength":strength,@"tcaEnabled":@(!!(mode&2)),@"tcaStrength":strength,@"vignettingEnabled":@NO,@"vignettingStrength":@0};
  id effects=LensEffectsForCorrectionPlan(plan,envelope,settings,nil,nil);if(!effects)return 5;effects=LensEffectsFromJSON(LensEffectsJSON(effects,nil));if(!effects)return 10;
  CIImage*image=[effects applyFor:input scale:CGPointMake(1,1) extent:input.extent bounds:input.extent layerOriginalSizeInBacking:input.extent.size layerCombinedTransformInBacking:*identity];if(!image)return 6;
  [context render:image toBitmap:o rowBytes:w*16 bounds:input.extent format:kCIFormatRGBAf colorSpace:nil];
  NSUInteger invalid=0,opaqueInvalid=0,valid=0,bx=0,by=0;double maxInterior=0;
  for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){
   // Independent analytic translations. The native wrapper presents top-down
   // layer space while persisted fields are bottom-up, so field Y is negated.
   double noise=noisy?((x/13+(h-1-y)/11)%2?.09:-.09):0;
   double sx[3],sy[3];BOOL outside=NO,inside=YES;
   for(int c=0;c<3;c++){sx[c]=x+ds*(dx+noise)+(c==0?-7*ts:0);sy[c]=y-ds*dy-(c==2?7*ts:0);outside|=sx[c]<-1||sy[c]<-1||sx[c]>w||sy[c]>h;inside&=sx[c]>2&&sy[c]>2&&sx[c]<w-3&&sy[c]<h-3;}
   NSUInteger i=(y*w+x)*4;
   // Entirely outside the original: no source pixel exists to extend here.
   if(outside){invalid++;if(fabs(o[i])+fabs(o[i+1])+fabs(o[i+2])+fabs(o[i+3])>1e-6){if(opaqueInvalid<4)fprintf(stderr,"boundary sample %lu,%lu rgba %.9g %.9g %.9g %.9g source %.9g %.9g\n",x,y,o[i],o[i+1],o[i+2],o[i+3],sx[0],sy[0]);opaqueInvalid++;}}
   if(inside){valid++;double before=maxInterior;maxInterior=fmax(maxInterior,fabs(o[i]-(.1+.2*(sx[0]+.5)/w)));maxInterior=fmax(maxInterior,fabs(o[i+1]-(.1+.2*(sy[1]+.5)/h)));maxInterior=fmax(maxInterior,fabs(o[i+2]-(.1+.1*(sx[2]+.5)/w+.1*(sy[2]+.5)/h)));maxInterior=fmax(maxInterior,fabs(o[i+3]-1));if(maxInterior>before){bx=x;by=y;}}
  }
  if(opaqueInvalid||maxInterior>.001){fprintf(stderr,"Out-of-source samples: %lu, fabricated opaque/color samples: %lu, interior error: %.9g at %lu,%lu rgba %.9g %.9g %.9g %.9g (shift %.0f %.0f, strength %.0f, mode %d, encoded %d, layout %s)\n",invalid,opaqueInvalid,maxInterior,bx,by,o[(by*w+bx)*4],o[(by*w+bx)*4+1],o[(by*w+bx)*4+2],o[(by*w+bx)*4+3],dx,dy,strength.doubleValue,mode,encoded,layout.UTF8String);return 7;}
  if(!encoded&&strength.intValue==100){
   const NSUInteger tx=31,ty=23,tw=197,th=113,top=h-ty-th;NSMutableData*part=[NSMutableData dataWithLength:tw*th*16];float*q=part.mutableBytes;
   [context render:image toBitmap:q rowBytes:tw*16 bounds:CGRectMake(tx,ty,tw,th) format:kCIFormatRGBAf colorSpace:nil];
   for(NSUInteger y=0;y<th;y++)for(NSUInteger x=0;x<tw;x++)for(int c=0;c<4;c++)croppedWorst=fmax(croppedWorst,fabs(q[(y*tw+x)*4+c]-o[((top+y)*w+tx+x)*4+c]));
   if(croppedWorst>.0001)return 15;croppedChecks++;
  }
  [checks addObject:@{@"layout":layout,@"encoded":@(encoded),@"mode":@(mode),@"shift":shift,@"strength":strength,@"checkedOutsideSamples":@(invalid),@"checkedInteriorSamples":@(valid),@"maxInteriorError":@(maxInterior)}];
  NSMutableDictionary*constrainedSettings=[settings mutableCopy];constrainedSettings[@"constrainCropEnabled"]=@YES;
  id constrained=LensEffectsForCorrectionPlan(plan,envelope,constrainedSettings,nil,nil);if(!constrained)return 16;
  constrained=LensEffectsFromJSON(LensEffectsJSON(constrained,nil));NSDictionary*saved=LensSavedCorrectionProfile(constrained);
  if(![saved[@"correctionSettings"]isEqual:constrainedSettings]||![saved[@"profileFormatVersion"]isEqual:@5])return 17;
  double cropScale=[saved[@"constrainedCrop"][@"scale"]doubleValue];if(mode?!(cropScale>0&&cropScale<1):cropScale!=1)return 18;
  CIImage*filled=[constrained applyFor:input scale:CGPointMake(1,1) extent:input.extent bounds:input.extent layerOriginalSizeInBacking:input.extent.size layerCombinedTransformInBacking:*identity];
  if(!CGRectEqualToRect(filled.extent,input.extent))return 19;
  [context render:filled toBitmap:o rowBytes:w*16 bounds:input.extent format:kCIFormatRGBAf colorSpace:nil];
  double alphaError=0,rgbError=0;
  for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){
   NSUInteger i=(y*w+x)*4;alphaError=fmax(alphaError,fabs(o[i+3]-1));
   if(!noisy){double qx=((x+.5)-w*.5)*cropScale+w*.5, qy=((y+.5)-h*.5)*cropScale+h*.5;
    double expected[3]={.1+.2*(qx+ds*dx-7*ts)/w,.1+.2*(qy-ds*dy)/h,.1+.1*(qx+ds*dx)/w+.1*(qy-ds*dy-7*ts)/h};
    for(int c=0;c<3;c++)rgbError=fmax(rgbError,fabs(o[i+c]-expected[c]));
   }
  }
  if(alphaError>1e-5||rgbError>.001){fprintf(stderr,"Constrained crop failed: alpha %.9g RGB %.9g scale %.9g layout %s mode %d strength %.0f\n",alphaError,rgbError,cropScale,layout.UTF8String,mode,strength.doubleValue);return 20;}
  [constrainedChecks addObject:@{@"layout":layout,@"encoded":@(encoded),@"mode":@(mode),@"strength":strength,@"scale":@(cropScale),@"maxAlphaError":@(alphaError),@"maxAnalyticRGBError":@(rgbError),@"analyticRGBChecked":@(!noisy)}];
  if(!encoded&&strength.intValue==100){
   CIImage*scaled=[input imageByApplyingTransform:CGAffineTransformMake(.25,0,0,.25,17,29)];CIFilter*f=[[LensRegisterVignettingFilter()alloc]init];[f setValue:saved forKey:@"lensProfile"];[f setValue:scaled forKey:kCIInputImageKey];CIImage*preview=[f valueForKey:kCIOutputImageKey];
   if(!CGRectEqualToRect(preview.extent,scaled.extent))return 23;
   NSMutableData*small=[NSMutableData dataWithLength:(w/4)*(h/4)];[context render:preview toBitmap:small.mutableBytes rowBytes:w/4 bounds:preview.extent format:kCIFormatA8 colorSpace:nil];const unsigned char*a=small.bytes;for(NSUInteger i=0;i<small.length;i++)if(a[i]!=255)return 24;scaledCropChecks++;
  }
  }}
 }}
 // The same calibration padding is used for gain. Check every edge/corner,
 // with an asymmetric analytic field, instead of skipping an interior margin.
 NSMutableData*gain=[NSMutableData dataWithLength:w*h*4];float*g=gain.mutableBytes;
 for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++)g[y*w+x]=1+.2*(double)x/(w-1)+.3*(double)y/(h-1);
 NSMutableDictionary*gainBase=[base mutableCopy];gainBase[@"linearGainFloat32BottomUp"]=gain;
 NSDictionary*compactGain=LensCompactGainPlan(gainBase,.000001,nil);if(!compactGain||!compactGain[@"report"][@"gainMapEncoding"])return 11;
 NSMutableArray*gainChecks=[NSMutableArray new];
 for(int encoded=0;encoded<2;encoded++)for(NSNumber*strength in @[@0,@37,@100,@137]){@autoreleasepool{
  NSMutableDictionary*plan=[compactGain mutableCopy],*report=[compactGain[@"report"]mutableCopy];report[@"workingTransfer"]=encoded?@"encoded_sRGB":@"linear";plan[@"report"]=report;
  NSDictionary*settings=@{@"distortionEnabled":@NO,@"distortionStrength":@100,@"tcaEnabled":@NO,@"tcaStrength":@100,@"vignettingEnabled":@YES,@"vignettingStrength":strength};
  id effects=LensEffectsForCorrectionPlan(plan,envelope,settings,nil,nil);if(!effects)return 12;effects=LensEffectsFromJSON(LensEffectsJSON(effects,nil));
  CIImage*image=[effects applyFor:input scale:CGPointMake(1,1) extent:input.extent bounds:input.extent layerOriginalSizeInBacking:input.extent.size layerCombinedTransformInBacking:*identity];if(!image)return 13;[context render:image toBitmap:o rowBytes:w*16 bounds:input.extent format:kCIFormatRGBAf colorSpace:nil];
  double worst=0;
  for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){double amount=1+strength.doubleValue/100*(.2*(double)x/(w-1)+.3*(double)(h-1-y)/(h-1));NSUInteger i=(y*w+x)*4;for(int c=0;c<3;c++){double expected=encoded?toEncoded(toLinear(s[i+c])*amount):s[i+c]*amount;worst=fmax(worst,fabs(o[i+c]-expected));}worst=fmax(worst,fabs(o[i+3]-1));}
  if(worst>.001){fprintf(stderr,"Gain full-canvas error %.9g, encoded %d, strength %.0f\n",worst,encoded,strength.doubleValue);return 14;}
  [gainChecks addObject:@{@"encoded":@(encoded),@"strength":strength,@"allPixelsIncludingCorners":@(w*h),@"maxError":@(worst)}];
 }}
 // No geometry means no crop, even when the user retains the crop preference.
 NSMutableDictionary*identityPlan=[base mutableCopy],*identityReport=[base[@"report"]mutableCopy];identityReport[@"distortionCorrectionNeeded"]=@NO;identityReport[@"tcaCorrectionNeeded"]=@NO;identityPlan[@"report"]=identityReport;
 NSDictionary*identitySettings=@{@"distortionEnabled":@YES,@"distortionStrength":@200,@"tcaEnabled":@YES,@"tcaStrength":@200,@"constrainCropEnabled":@YES};
 if([LensConstrainedCrop(identityPlan,identitySettings,nil)[@"scale"]doubleValue]!=1)return 21;
 NSMutableDictionary*broken=[base mutableCopy];broken[@"normalizedGeometryMapsLZFSE"]=@{};
 if(LensConstrainedCrop(broken,identitySettings,nil))return 22;
 NSDictionary*result=@{@"scope":@"Synthetic translation and asymmetric gain full-canvas boundary regression through native effect wrapper; not measured optical calibration or full GUI",@"checks":checks,@"gainChecks":gainChecks,@"constrainedCropChecks":constrainedChecks,@"scaledTranslatedCropChecks":@(scaledCropChecks),@"identityCalibrationNotCropped":@YES,@"missingActiveMapRejected":@YES,@"croppedRegionComparisons":@(croppedChecks),@"maxCroppedRegionVersusFullImageError":@(croppedWorst),@"outOfSourceSamplesTransparent":@YES};[[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/geometry-boundaries-verification.json" atomically:YES];puts("Out-of-source geometry samples remain transparent; optional constrained crop fills the canvas while preserving settings, source and analytic mapping.");
}}
