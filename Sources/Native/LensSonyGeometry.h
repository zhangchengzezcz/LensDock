#import "LensSonyEmbeddedProfile.h"
#import <CoreGraphics/CoreGraphics.h>

// An explicit mathematical frame supplied by a caller, not inferred from EXIF
// dimensions. Nothing here certifies a Sony calibration frame or enables a
// product provider. Coordinates are local, top-left, with pixel centres at .5.
typedef struct {
 CGSize calibrationSize;
 CGRect decodedRegion; // unrotated crop, expressed in calibration coordinates
 CGSize outputSize;    // displayed pixels, after EXIF orientation and resizing
 NSUInteger orientation; // EXIF 1...8, including the four reflected cases
} LensSonyExplicitPixelFrame;

typedef struct {
 NSUInteger version,distortionCount,tcaCount;
 CGAffineTransform outputToCalibration,calibrationToOutput;
 double centerX,centerY,inverseRadius;
 double distortion[16],red[16],blue[16];
} LensSonyGeometryTransform;

static inline CGPoint LensSonyOrientPoint(CGPoint p,double width,double height,NSUInteger orientation){
 switch(orientation){
  case 1:return p;case 2:return CGPointMake(width-p.x,p.y);
  case 3:return CGPointMake(width-p.x,height-p.y);case 4:return CGPointMake(p.x,height-p.y);
  case 5:return CGPointMake(p.y,p.x);case 6:return CGPointMake(height-p.y,p.x);
  case 7:return CGPointMake(height-p.y,width-p.x);case 8:return CGPointMake(p.y,width-p.x);
 }
 return CGPointMake(NAN,NAN);
}
static inline BOOL LensSonyPrepareNodes(NSDictionary*table,NSString*component,double strength,int exponent,NSUInteger*count,double*nodes){
 // Reuse the source validator rather than accepting an arbitrary array with a
 // trusted-looking provider name. Validation is performed once, not per pixel.
 if(!isfinite(LensSonyRadialCode(table,component,0)))return NO;
 NSUInteger n=[table[@"nodeCount"]unsignedIntegerValue];NSArray*values=table[component];
 for(NSUInteger i=0;i<n;i++){double factor=1+strength*ldexp([values[i]doubleValue],exponent);if(!isfinite(factor)||factor<=0)return NO;nodes[i]=factor;}
 *count=n;return YES;
}
static inline BOOL LensSonyPrepareGeometry(NSDictionary*source,LensSonyExplicitPixelFrame frame,double distortionStrength,double tcaStrength,LensSonyGeometryTransform*out){
 if(!out)return NO;*out=(LensSonyGeometryTransform){0};
 if(![source isKindOfClass:NSDictionary.class]||![source[@"provider"]isEqual:@"sony-subifd-radial-source-v1"]||![source[@"tables"]isKindOfClass:NSDictionary.class])return NO;
 double cw=frame.calibrationSize.width,ch=frame.calibrationSize.height,x=frame.decodedRegion.origin.x,y=frame.decodedRegion.origin.y;
 double w=frame.decodedRegion.size.width,h=frame.decodedRegion.size.height,ow=frame.outputSize.width,oh=frame.outputSize.height;
 double values[]={cw,ch,x,y,w,h,ow,oh,distortionStrength,tcaStrength};for(NSUInteger i=0;i<10;i++)if(!isfinite(values[i]))return NO;
 if(cw<16||ch<16||cw>40000||ch>40000||cw*ch>400000000||x<0||y<0||w<1||h<1||x+w>cw||y+h>ch||ow<1||oh<1||ow>40000||oh>40000||ow*oh>400000000||frame.orientation<1||frame.orientation>8||distortionStrength<0||distortionStrength>2||tcaStrength<0||tcaStrength>2)return NO;
 LensSonyGeometryTransform t={0};NSDictionary*tables=source[@"tables"];
 if(distortionStrength>0&&!LensSonyPrepareNodes(tables[@"Distortion"],@"values",distortionStrength,-14,&t.distortionCount,t.distortion))return NO;
 if(tcaStrength>0){NSUInteger blueCount=0;if(!LensSonyPrepareNodes(tables[@"ChromaticAberration"],@"red",tcaStrength,-21,&t.tcaCount,t.red)||!LensSonyPrepareNodes(tables[@"ChromaticAberration"],@"blue",tcaStrength,-21,&blueCount,t.blue)||blueCount!=t.tcaCount)return NO;}
 if(t.distortionCount&&t.tcaCount&&t.distortionCount!=t.tcaCount)return NO;
 BOOL swapped=frame.orientation>=5;double sx=ow/(swapped?h:w),sy=oh/(swapped?w:h);
 CGPoint a=LensSonyOrientPoint(CGPointMake(-x,-y),w,h,frame.orientation);
 CGPoint b=LensSonyOrientPoint(CGPointMake(1-x,-y),w,h,frame.orientation);
 CGPoint c=LensSonyOrientPoint(CGPointMake(-x,1-y),w,h,frame.orientation);
 t.calibrationToOutput=CGAffineTransformMake((b.x-a.x)*sx,(b.y-a.y)*sy,(c.x-a.x)*sx,(c.y-a.y)*sy,a.x*sx,a.y*sy);
 t.outputToCalibration=CGAffineTransformInvert(t.calibrationToOutput);
 t.centerX=cw/2;t.centerY=ch/2;t.inverseRadius=1/hypot(t.centerX,t.centerY);t.version=1;*out=t;return YES;
}
static inline double LensSonyPreparedFactor(const double*nodes,NSUInteger count,double radius){
 if(!count)return 1;if(count<2||count>16||!isfinite(radius)||radius<0)return NAN;
 double position=radius*(count-1)-.5;if(position<=0)return nodes[0];if(position>=count-1)return nodes[count-1];
 NSUInteger left=(NSUInteger)floor(position);double fraction=position-left;return nodes[left]*(1-fraction)+nodes[left+1]*fraction;
}
static inline BOOL LensSonyMapGeometryPoint(const LensSonyGeometryTransform*t,CGPoint point,NSUInteger channel,CGPoint*out){
 if(!out)return NO;*out=CGPointMake(NAN,NAN);
 if(!t||t->version!=1||channel>2||!isfinite(point.x)||!isfinite(point.y)||!isfinite(t->centerX)||!isfinite(t->centerY)||!isfinite(t->inverseRadius)||t->inverseRadius<=0)return NO;
 if((t->distortionCount&&(t->distortionCount<2||t->distortionCount>16))||(t->tcaCount&&(t->tcaCount<2||t->tcaCount>16)))return NO;
 CGPoint canonical=CGPointApplyAffineTransform(point,t->outputToCalibration);
 double dx=canonical.x-t->centerX,dy=canonical.y-t->centerY,radius=hypot(dx,dy)*t->inverseRadius;
 if(!isfinite(radius))return NO;
 double d=LensSonyPreparedFactor(t->distortion,t->distortionCount,radius);
 double ca=channel==1?1:LensSonyPreparedFactor(channel==0?t->red:t->blue,t->tcaCount,radius),factor=d*ca;
 if(!isfinite(d)||d<=0||!isfinite(ca)||ca<=0||!isfinite(factor)||factor<=0)return NO;
 // Exact identity matters: a disabled or zero table must not add coordinate
 // round-off (and later cause a resample) through an affine round trip.
 if(factor==1){*out=point;return YES;}
 CGPoint mapped=CGPointApplyAffineTransform(CGPointMake(t->centerX+dx*factor,t->centerY+dy*factor),t->calibrationToOutput);
 if(!isfinite(mapped.x)||!isfinite(mapped.y))return NO;*out=mapped;return YES;
}
