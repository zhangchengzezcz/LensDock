#import "LensCalibrationImage.h"
int main(){@autoreleasepool{
 const NSUInteger w=2050,h=1030;NSMutableData*data=[NSMutableData dataWithLength:w*h*8];float*f=data.mutableBytes;
 for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){f[(y*w+x)*2]=(float)x/w-.1;f[(y*w+x)*2+1]=.2+.7*(float)y/h;}
 CIImage*provider=LensCalibrationImage(data,w,h,8,kCIFormatRGf);CGRect bounds=CGRectMake(0,0,w+2,h+2);CIContext*context=[CIContext contextWithOptions:@{kCIContextWorkingColorSpace:NSNull.null,kCIContextOutputColorSpace:NSNull.null,kCIContextWorkingFormat:@(kCIFormatRGBAf)}];
 NSMutableData*padding=[NSMutableData dataWithLength:(w+2)*(h+2)*8];float*pf=padding.mutableBytes;for(NSUInteger y=0;y<h+2;y++)for(NSUInteger x=0;x<w+2;x++){NSUInteger sx=MIN(w-1,x?x-1:0),sy=MIN(h-1,y?y-1:0);for(int c=0;c<2;c++)pf[(y*(w+2)+x)*2+c]=f[(sy*w+sx)*2+c];}CIImage*bitmap=[CIImage imageWithBitmapData:padding bytesPerRow:(w+2)*8 size:bounds.size format:kCIFormatRGf colorSpace:nil];
 NSMutableData*out=[NSMutableData dataWithLength:(w+2)*(h+2)*16];float*o=out.mutableBytes;
 NSMutableArray*checks=[NSMutableArray new];
 for(int mode=0;mode<8;mode++){
  CIImage*original=(mode>=3&&mode<6)||mode==7?bitmap:provider,*image=original;int variant=mode>=6?2:mode%3;
  if(variant){CIKernel*k=[CIKernel kernelWithString:variant==1?@"kernel vec4 identity(sampler s) {return sample(s,destCoord());}":@"kernel vec4 identity(sampler s) {return sample(s,samplerTransform(s,destCoord()));}"];image=mode>=6?LensApplyCalibrationKernel(k,bounds,^CGRect(int i,CGRect r){return r;},@[original]):[k applyWithExtent:bounds roiCallback:^CGRect(int i,CGRect r){return r;}arguments:@[original]];}
  [context render:image toBitmap:o rowBytes:(w+2)*16 bounds:bounds format:kCIFormatRGBAf colorSpace:nil];double worst=0;NSUInteger bx=0,by=0;
  for(NSUInteger y=0;y<h+2;y++)for(NSUInteger x=0;x<w+2;x++){NSUInteger sx=MIN(w-1,x?x-1:0),sy=MIN(h-1,y?y-1:0);for(int c=0;c<2;c++){double e=fabs(o[(y*(w+2)+x)*4+c]-f[(sy*w+sx)*2+c]);if(e>worst){worst=e;bx=x;by=y;}}}
  printf("provider mode %d max %.9g at %lu,%lu actual %.9g %.9g\n",mode,worst,bx,by,o[(by*(w+2)+bx)*4],o[(by*(w+2)+bx)*4+1]);
  BOOL negative=mode==1||mode==4;if(negative?worst<.1:worst>1e-5)return 1;
  [checks addObject:@{@"mode":@(mode),@"negativeControl":@(negative),@"maxError":@(worst)}];
 }
 NSMutableData*alpha=[NSMutableData dataWithLength:(w+2)*(h+2)];[context render:provider toBitmap:alpha.mutableBytes rowBytes:w+2 bounds:bounds format:kCIFormatA8 colorSpace:nil];const unsigned char*a=alpha.bytes;for(NSUInteger i=0;i<alpha.length;i++)if(a[i]!=255)return 2;
 [[NSJSONSerialization dataWithJSONObject:@{@"scope":@"Signed asymmetric numeric provider, bitmap reference, sampler coordinate negative controls, system tiled intermediate and A8 output",@"dimensionsIncludingPadding":@[@(w+2),@(h+2)],@"checks":checks,@"a8OutputVerified":@YES}options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/calibration-image-verification.json" atomically:YES];
 puts("Calibration provider preserves signed asymmetric numeric values.");
}}
