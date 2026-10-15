#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <dlfcn.h>
#import <math.h>
static double encode(double x){return x<=.0031308?12.92*x:1.055*pow(x,1/2.4)-.055;}
static BOOL coordinateNoiseFixture=NO;
static double ramp(int x,int y,int c,int w,int h){if(coordinateNoiseFixture)return .02+.1*((x+y+c)%2);double a=(x+.5)/w,b=(y+.5)/h;return .12*(c==0?a:c==1?b:(a+b)/2);}
#import "LensNativeProfileEngine.h"
#import "LensNativeState.h"
#import "LensCorrectionSettings.h"
typedef struct {double v[8];} ProjectiveTransform;
@interface NSObject(TestEffects)
- (CIImage*)applyFor:(CIImage*)input scale:(CGPoint)scale extent:(CGRect)extent bounds:(CGRect)bounds layerOriginalSizeInBacking:(CGSize)size layerCombinedTransformInBacking:(ProjectiveTransform)transform;
@end
int main(){@autoreleasepool{
 void*foundation=dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL);if(!foundation)return 2;
 ProjectiveTransform*identity=dlsym(foundation,"PTProjectiveTransformIdentity");NSURL*here=[NSURL fileURLWithPath:@"Build/Tests" isDirectory:YES];NSError*error=nil;const int w=384,h=256;
 NSDictionary*metadata=@{@"Make":@"Canon",@"Model":@"Canon EOS 40D",@"LensModel":@"Canon EF-S 17-85mm f/4-5.6 IS USM",@"FocalLength":@17,@"FNumber":@4};
 NSDictionary*plan=LensNativeProfilePlanFullGeometry(metadata,[here URLByAppendingPathComponent:@"resources/db"],[here URLByAppendingPathComponent:@"lib/liblensfun.0.3.4.dylib"],w,h,&error);if(!plan){NSLog(@"%@",error);return 3;}
 BOOL gainGrid=getenv("LENS_GAIN_GRID_TEST")!=NULL;
 BOOL residualGrid=getenv("LENS_RESIDUAL_GRID_TEST")!=NULL;
 coordinateNoiseFixture=residualGrid;
 if(residualGrid){
  // Controlled coordinate noise forces the hybrid codec; not optical evidence.
  NSMutableDictionary*test=[plan mutableCopy],*fields=[plan[@"normalizedGeometryMapsLZFSE"]mutableCopy];NSMutableData*data=[[fields[@"D"]decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil]mutableCopy];float*q=data.mutableBytes;
  for(int y=0;y<h;y++)for(int x=0;x<w;x++)q[(y*w+x)*2]+=(x/13+y/11)%2?.09/w:-.09/w;
  fields[@"D"]=[data compressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];test[@"normalizedGeometryMapsLZFSE"]=fields;plan=test;
 }
 if(gainGrid){
  // Asymmetric bilinear gain isolates compact field orientation and node
  // alignment. It is a rendering fixture, not a measured lens calibration.
  NSMutableData*field=[NSMutableData dataWithLength:w*h*4];float*g=field.mutableBytes;
  for(int y=0;y<h;y++)for(int x=0;x<w;x++){double nx=(double)x/(w-1),ny=(double)y/(h-1);g[y*w+x]=1+.2*nx+.3*ny+.1*nx*ny;}
  NSMutableDictionary*test=[plan mutableCopy];test[@"linearGainFloat32BottomUp"]=field;plan=test;
 }
 NSDictionary*reference=plan;if(getenv("LENS_GRID_TEST")||gainGrid||residualGrid){plan=LensCompactGeometryPlan(plan,.001,&error);if(!plan)return 12;}
 if(residualGrid&&(![plan[@"report"][@"geometryMapEncoding"]isEqual:@"pixel-displacement-residual-RG8-bottom-up-grid-v4"]||[plan[@"geometryResidualMapsLZFSE"]count]!=[plan[@"normalizedGeometryMapsLZFSE"]count]))return 14;
 if(gainGrid){plan=LensCompactGainPlan(plan,.000001,&error);if(!plan||![plan[@"report"][@"gainMapEncoding"]isEqual:@"linear-gain-Rf-bottom-up-grid-v1"]||[plan[@"linearGainFloat32BottomUp"]length]>=[reference[@"linearGainFloat32BottomUp"]length])return 13;}
 NSMutableDictionary*p=[plan mutableCopy],*report=[plan[@"report"]mutableCopy];report[@"workingTransfer"]=@"linear";p[@"report"]=report;p[@"metadata"]=metadata;p[@"cornerAssessment"]=@{@"automaticFullStrengthSuitable":@NO};plan=p;
 NSData*envelope=[NSData dataWithContentsOfURL:[here URLByAppendingPathComponent:@"native-effects-template.json"]];NSMutableData*source=[NSMutableData dataWithLength:w*h*16],*out=[NSMutableData dataWithLength:w*h*16],*baselineOut=[NSMutableData dataWithLength:w*h*16];float*s=source.mutableBytes,*o=out.mutableBytes,*bo=baselineOut.mutableBytes;
 NSMutableDictionary*maps=[NSMutableDictionary new];for(NSString*key in reference[@"normalizedGeometryMapsLZFSE"])maps[key]=[reference[@"normalizedGeometryMapsLZFSE"][key]decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];
 const float*gain=[reference[@"linearGainFloat32BottomUp"]bytes];
 double gainMin=INFINITY,gainMax=0,gainDX=0,gainDY=0;
 for(int y=0;y<h;y++)for(int x=0;x<w;x++){double value=gain[y*w+x];gainMin=fmin(gainMin,value);gainMax=fmax(gainMax,value);if(x+1<w)gainDX=fmax(gainDX,fabs(value-gain[y*w+x+1]));if(y+1<h)gainDY=fmax(gainDY,fabs(value-gain[(y+1)*w+x]));}
 CIContext*ctx=[CIContext contextWithOptions:@{kCIContextWorkingColorSpace:NSNull.null,kCIContextOutputColorSpace:NSNull.null,kCIContextWorkingFormat:@(kCIFormatRGBAf)}];NSMutableArray*results=[NSMutableArray new];
 for(int encoded=0;encoded<2;encoded++)for(int half=0;half<3;half++)for(int mode=0;mode<8;mode++){
  report[@"workingTransfer"]=encoded?@"encoded_sRGB":@"linear";p[@"report"]=[report copy];
  for(int y=0;y<h;y++)for(int x=0;x<w;x++){int q=(y*w+x)*4;for(int c=0;c<3;c++)s[q+c]=encoded?encode(ramp(x,y,c,w,h)):ramp(x,y,c,w,h);s[q+3]=1;}
  CIImage*input=[CIImage imageWithBitmapData:source bytesPerRow:w*16 size:CGSizeMake(w,h) format:kCIFormatRGBAf colorSpace:nil];
  double ds=mode&1?(half==2?1.37:half?.37:1):0,ts=mode&2?(half==2?1.61:half?.61:1):0,vs=mode&4?(half==2?1.23:half?.23:1):0;
  NSDictionary*settings=@{@"distortionEnabled":@(!!(mode&1)),@"tcaEnabled":@(!!(mode&2)),@"vignettingEnabled":@(!!(mode&4)),@"distortionStrength":@(half==2?137:half?37:100),@"tcaStrength":@(half==2?161:half?61:100),@"vignettingStrength":@(half==2?123:half?23:100)};
  id effects=LensEffectsForCorrectionPlan(p,envelope,settings,nil,&error);if(!effects){NSLog(@"%@",error);return 4;}
  NSData*json=LensEffectsJSON(effects,&error);if(gainGrid&&!encoded&&!half&&mode==7)[json writeToFile:@"Build/Tests/new-format-compatibility-effects.json" atomically:YES];id restored=LensEffectsFromJSON(json);if(!LensEffectsEquivalent(json,LensEffectsJSON(restored,nil)))return 11;NSDictionary*saved=LensSavedCorrectionProfile(restored);if(![saved[@"correctionSettings"]isEqual:settings]||![saved[@"metadata"]isEqual:metadata]||![saved[@"cornerAssessment"]isEqual:p[@"cornerAssessment"]])return 5;
  CIImage*image=[restored applyFor:input scale:CGPointMake(1,1) extent:input.extent bounds:input.extent layerOriginalSizeInBacking:input.extent.size layerCombinedTransformInBacking:*identity];if(!image)return 6;[ctx render:image toBitmap:o rowBytes:w*16 bounds:input.extent format:kCIFormatRGBAf colorSpace:nil];
  if(residualGrid){
   NSMutableDictionary*base=[reference mutableCopy],*br=[reference[@"report"]mutableCopy];br[@"workingTransfer"]=report[@"workingTransfer"];base[@"report"]=br;
   id fullEffects=LensEffectsForCorrectionPlan(base,envelope,settings,nil,nil);if(!fullEffects)return 15;
   CIImage*fullImage=[fullEffects applyFor:input scale:CGPointMake(1,1) extent:input.extent bounds:input.extent layerOriginalSizeInBacking:input.extent.size layerCombinedTransformInBacking:*identity];if(!fullImage)return 16;
   [ctx render:fullImage toBitmap:bo rowBytes:w*16 bounds:input.extent format:kCIFormatRGBAf colorSpace:nil];
  }
  double max=0,mean=0,paired=0,baselineCPU=0;int samples=0,bx=0,by=0,bc=0;float actualWorst=0;double expectedWorst=0;
  for(int y=8;y<h-8;y++)for(int x=8;x<w-8;x++)for(int c=0;c<3;c++){
   NSUInteger pos=((h-1-y)*w+x)*2;double px=(x+.5)/w,py=1-(y+.5)/h;
   const float*d=[maps[@"D"]bytes],*t=[maps[[NSString stringWithFormat:@"T%d",c]]bytes],*combined=[maps[[NSString stringWithFormat:@"C%d",c]]bytes];
   double nx=(1-ts)*((1-ds)*px+ds*d[pos])+ts*((1-ds)*t[pos]+ds*combined[pos]);
   double ny=(1-ts)*((1-ds)*py+ds*d[pos+1])+ts*((1-ds)*t[pos+1]+ds*combined[pos+1]);
   double sx=nx*w-.5,sy=(1-ny)*h-.5;if(sx<1||sy<1||sx>w-2||sy>h-2)continue;
   int ix=floor(sx),iy=floor(sy);double fx=sx-ix,fy=sy-iy,expected=0;
   for(int yy=0;yy<2;yy++)for(int xx=0;xx<2;xx++){double weight=(xx?fx:1-fx)*(yy?fy:1-fy);double g=1+vs*(gain[(h-1-iy-yy)*w+ix+xx]-1);expected+=weight*ramp(ix+xx,iy+yy,c,w,h)*g;}
   if(encoded)expected=encode(expected);if(!mode)expected=s[(y*w+x)*4+c];
   double e=fabs(o[(y*w+x)*4+c]-expected);if(e>max){max=e;bx=x;by=y;bc=c;actualWorst=o[(y*w+x)*4+c];expectedWorst=expected;}mean+=e;samples++;
   if(residualGrid){paired=fmax(paired,fabs(o[(y*w+x)*4+c]-bo[(y*w+x)*4+c]));baselineCPU=fmax(baselineCPU,fabs(bo[(y*w+x)*4+c]-expected));}
  }
  // Nyquist fixtures expose the native sampler's own rounding. Compare the
  // paired full/native result against that measured rounding plus the analytic
  // color-gradient budget from the independently bounded coordinate codec.
  double gradient=.2*(1+vs*(gainMax-1))+.12*vs*(gainDX+gainDY),minimum=.02*(1+vs*(gainMin-1));
  if(encoded)gradient*=minimum<=.0031308?12.92:1.055/2.4*pow(minimum,1/2.4-1);
  double weights=fabs(ds*(1-ts))+fabs(ts*(1-ds))+fabs(ds*ts);
  double pairedBudget=2*baselineCPU+.001*weights*gradient+2e-5;
  [results addObject:@{@"mode":@(mode),@"partialStrengths":@(half),@"transfer":report[@"workingTransfer"],@"maxError":@(max),@"meanError":@(mean/samples),@"pairedFullNativeMaxError":@(paired),@"pairedNativeRoundingAndCoordinateBudget":@(pairedBudget),@"fullNativeCPUReferenceMaxError":@(baselineCPU),@"savedIndependentSettingsAndMetadata":@YES}];double limit=encoded?2e-4:(getenv("LENS_GRID_TEST")||gainGrid)?1e-4:2e-5;if(residualGrid?paired>pairedBudget:max>limit){NSLog(@"mode%d encoded%d partial%d max%g paired%g budget%g fullCPU%g at%d,%d c%d actual%g expected%g",mode,encoded,half,max,paired,pairedBudget,baselineCPU,bx,by,bc,actualWorst,expectedWorst);return 7;}
 }
 // Real native color-fill wrapper and its context survive adding/replacing ours.
 NSData*existing=[NSData dataWithContentsOfFile:@"Tests/Fixtures/color-fill-effects.json"];
 id baseline=LensEffectsFromJSON(existing);NSArray*original=[NSJSONSerialization JSONObjectWithData:LensEffectsJSON(baseline,nil) options:0 error:nil];
 NSDictionary*off=@{@"distortionEnabled":@NO,@"tcaEnabled":@NO,@"vignettingEnabled":@NO,@"distortionStrength":@37,@"tcaStrength":@61,@"vignettingStrength":@23};
 id composed=LensEffectsForCorrectionPlan(p,envelope,off,LensEffectsJSON(baseline,nil),&error);
 id replaced=LensEffectsForCorrectionPlan(p,envelope,off,LensEffectsJSON(composed,nil),&error);
 NSArray*final=[NSJSONSerialization JSONObjectWithData:LensEffectsJSON(replaced,nil) options:0 error:nil];
 NSArray*tail=[final[1][@"w"]subarrayWithRange:NSMakeRange(1,[final[1][@"w"]count]-1)];
 if(![tail isEqual:original[1][@"w"]]||![final[1][@"ctx"]isEqual:original[1][@"ctx"]])return 8;
 NSDictionary*result=@{@"gridRenderTolerance":@.0001,@"renders":results,@"preservesExistingEffectsAndContext":@YES,@"replacesOnlyOwnEffect":@YES,@"profileReport":report};
 NSData*d=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];[d writeToFile:residualGrid?@"Build/Tests/residual-grid-corrections-verification.json":gainGrid?@"Build/Tests/gain-grid-corrections-verification.json":getenv("LENS_GRID_TEST")?@"Build/Tests/grid-corrections-verification.json":@"Build/Tests/three-corrections-verification.json" atomically:YES];puts("48 native render combinations and composition preservation passed.");
}}
