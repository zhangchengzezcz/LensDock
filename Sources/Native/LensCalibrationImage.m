#import "LensCalibrationImage.h"
#import <CoreImage/CIImageProvider.h>
#import <math.h>
#import <string.h>

@interface LensCalibrationProvider:NSObject
@property(nonatomic,copy)NSData*data;
@property(nonatomic)NSUInteger width,height,bytesPerPixel;
@end
@implementation LensCalibrationProvider
- (void)provideImageData:(void*)buffer bytesPerRow:(size_t)rowBytes origin:(size_t)x :(size_t)y size:(size_t)width :(size_t)height userInfo:(id)info{
 const unsigned char*source=self.data.bytes;unsigned char*target=buffer;NSUInteger w=self.width,h=self.height,b=self.bytesPerPixel;
 for(NSUInteger row=0;row<height;row++){
  NSUInteger sy=MIN(h-1,y+row?y+row-1:0);const unsigned char*line=source+sy*w*b;unsigned char*out=target+row*rowBytes;
  if(x>=1&&x+width<=w+1){memcpy(out,line+(x-1)*b,width*b);continue;}
  for(NSUInteger col=0;col<width;col++){NSUInteger sx=MIN(w-1,x+col?x+col-1:0);memcpy(out+col*b,line+sx*b,b);}
 }
}
@end
CIImage*LensCalibrationImage(NSData*data,NSUInteger w,NSUInteger h,NSUInteger b,CIFormat format){
 if(!w||!h||w>16000||h>16000||!b||b>16||data.length!=w*h*b)return nil;
 LensCalibrationProvider*p=[LensCalibrationProvider new];p.data=data;p.width=w;p.height=h;p.bytesPerPixel=b;
 return [CIImage imageWithImageProvider:p size:w+2 :h+2 format:format colorSpace:nil options:@{kCIImageProviderTileSize:NSNull.null}];
}
CGRect LensCalibrationROI(CGRect request,CGRect extent,NSUInteger w,NSUInteger h,NSUInteger mw,NSUInteger mh){
 if(w<2||h<2||mw<2||mh<2||CGRectIsEmpty(extent)||CGRectIsInfinite(extent))return CGRectZero;
 CGRect intersection=CGRectIntersection(request,extent);if(CGRectIsNull(intersection)||CGRectIsEmpty(intersection))return CGRectZero;
 double x0=((CGRectGetMinX(intersection)-extent.origin.x)/extent.size.width*w-.5)*(mw-1)/(w-1);
 double x1=((CGRectGetMaxX(intersection)-extent.origin.x)/extent.size.width*w-.5)*(mw-1)/(w-1);
 double y0=((CGRectGetMinY(intersection)-extent.origin.y)/extent.size.height*h-.5)*(mh-1)/(h-1);
 double y1=((CGRectGetMaxY(intersection)-extent.origin.y)/extent.size.height*h-.5)*(mh-1)/(h-1);
 // The original node centre i+.5 is padded to i+1.5. Include both manual
 // bilinear neighbours and an extra texel for GPU filtering/float roundoff.
 CGRect needed=CGRectMake(floor(x0),floor(y0),ceil(x1)+4-floor(x0),ceil(y1)+4-floor(y0));
 // Persisted fields use bottom-up numeric rows. The image/provider has a
 // top-left sampling origin, so the kernel reflects its image-space Y.
 needed.origin.y=mh+2-CGRectGetMaxY(needed);
 return CGRectIntersection(needed,CGRectMake(0,0,mw+2,mh+2));
}
CIImage*LensApplyCalibrationKernel(CIKernel*kernel,CGRect extent,CIKernelROICallback callback,NSArray*arguments){
 if(!kernel||CGRectIsEmpty(extent)||CGRectIsInfinite(extent))return nil;
 CIImage*image=[kernel applyWithExtent:extent roiCallback:callback arguments:arguments];
 // Public macOS 26 tile caching avoids a duplicated composite kernel graph.
 // The host/CIContext controls tile scheduling; no eager rasterization here.
 return extent.size.width*extent.size.height>2048*1024?[image imageByInsertingTiledIntermediate]:image;
}
