#import "LensSonyGeometryImage.h"

static CIImage*imageError(NSError**error){if(error)*error=[NSError errorWithDomain:@"LensDockExplicitGeometry" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法确认显式矫正坐标，未生成图像。"}];return nil;}
static void factorBounds(const double*nodes,NSUInteger count,double lowRadius,double highRadius,double*low,double*high){
 if(!count){*low=*high=1;return;}
 double a=LensSonyPreparedFactor(nodes,count,lowRadius),b=isinf(highRadius)?nodes[count-1]:LensSonyPreparedFactor(nodes,count,highRadius);*low=fmin(a,b);*high=fmax(a,b);
 for(NSUInteger i=0;i<count;i++){double radius=((double)i+.5)/(count-1);if(radius>=lowRadius&&radius<=highRadius){*low=fmin(*low,nodes[i]);*high=fmax(*high,nodes[i]);}}
}
static BOOL validTransform(const LensSonyGeometryTransform*t){
 if(!t||t->version!=1||(t->distortionCount&&(t->distortionCount<2||t->distortionCount>16))||(t->tcaCount&&(t->tcaCount<2||t->tcaCount>16)))return NO;
 const CGAffineTransform a=t->outputToCalibration,b=t->calibrationToOutput;
 double fields[]={a.a,a.b,a.c,a.d,a.tx,a.ty,b.a,b.b,b.c,b.d,b.tx,b.ty,t->centerX,t->centerY,t->inverseRadius};for(NSUInteger i=0;i<15;i++)if(!isfinite(fields[i]))return NO;
 if(t->inverseRadius<=0)return NO;
 for(NSUInteger i=0;i<t->distortionCount;i++)if(!isfinite(t->distortion[i])||t->distortion[i]<=0)return NO;
 for(NSUInteger i=0;i<t->tcaCount;i++)if(!isfinite(t->red[i])||t->red[i]<=0||!isfinite(t->blue[i])||t->blue[i]<=0)return NO;
 return YES;
}
double LensSonyGeometryCropScale(const LensSonyGeometryTransform*t,CGSize size){
 if(!validTransform(t)||!isfinite(size.width)||!isfinite(size.height)||size.width<2||size.height<2||size.width>40000||size.height>40000)return NAN;
 double dl,dh;factorBounds(t->distortion,t->distortionCount,0,INFINITY,&dl,&dh);double deviation=0;
 for(NSUInteger c=0;c<3;c++){double tl=1,th=1;if(c!=1)factorBounds(c==0?t->red:t->blue,t->tcaCount,0,INFINITY,&tl,&th);deviation=fmax(deviation,fmax(fabs(dl*tl-1),fabs(dh*th-1)));}
 if(deviation==0)return 1;
 CGPoint center=CGPointApplyAffineTransform(CGPointMake(t->centerX,t->centerY),t->calibrationToOutput);
 double dx=deviation*fmax(fabs(center.x),fabs(size.width-center.x)),dy=deviation*fmax(fabs(center.y),fabs(size.height-center.y));
 double scale=fmin(1-2*(dx+2)/size.width,1-2*(dy+2)/size.height);return isfinite(scale)&&scale>0?scale:NAN;
}
static void productBounds(double a,double b,double lowFactor,double highFactor,double*low,double*high){
 double x[]={a*lowFactor,a*highFactor,b*lowFactor,b*highFactor};*low=*high=x[0];for(NSUInteger i=1;i<4;i++){*low=fmin(*low,x[i]);*high=fmax(*high,x[i]);}
}
CGRect LensSonyGeometrySourceROI(const LensSonyGeometryTransform*t,CGRect extent,CGRect request,double scale){
 if(!validTransform(t)||CGRectIsEmpty(extent)||CGRectIsInfinite(extent)||!isfinite(scale)||scale<=0||scale>1)return CGRectZero;
 CGRect needed=CGRectIntersection(extent,request);if(CGRectIsEmpty(needed)||CGRectIsNull(needed))return CGRectZero;
 // Include neighboring field nodes before taking extrema: interpolated field
 // coordinates are convex combinations of those node coordinates.
 CGRect top=CGRectMake(needed.origin.x-extent.origin.x,CGRectGetMaxY(extent)-CGRectGetMaxY(needed),needed.size.width,needed.size.height);
 top=CGRectInset(top,-2,-2);top=CGRectApplyAffineTransform(top,CGAffineTransformMake(scale,0,0,scale,extent.size.width*(1-scale)/2,extent.size.height*(1-scale)/2));
 CGRect canonical=CGRectApplyAffineTransform(top,t->outputToCalibration);double dx0=CGRectGetMinX(canonical)-t->centerX,dx1=CGRectGetMaxX(canonical)-t->centerX,dy0=CGRectGetMinY(canonical)-t->centerY,dy1=CGRectGetMaxY(canonical)-t->centerY;
 double nx=dx0<=0&&dx1>=0?0:fmin(fabs(dx0),fabs(dx1)),ny=dy0<=0&&dy1>=0?0:fmin(fabs(dy0),fabs(dy1));
 double lowR=hypot(nx,ny)*t->inverseRadius,highR=hypot(fmax(fabs(dx0),fabs(dx1)),fmax(fabs(dy0),fabs(dy1)))*t->inverseRadius,dl,dh;
 factorBounds(t->distortion,t->distortionCount,lowR,highR,&dl,&dh);CGRect result=CGRectNull;
 for(NSUInteger c=0;c<3;c++){
  double tl=1,th=1;if(c!=1)factorBounds(c==0?t->red:t->blue,t->tcaCount,lowR,highR,&tl,&th);
  double x0,x1,y0,y1;productBounds(dx0,dx1,dl*tl,dh*th,&x0,&x1);productBounds(dy0,dy1,dl*tl,dh*th,&y0,&y1);
  CGRect box=CGRectApplyAffineTransform(CGRectMake(t->centerX+x0,t->centerY+y0,x1-x0,y1-y0),t->calibrationToOutput);
  CGRect ci=CGRectMake(extent.origin.x+box.origin.x,CGRectGetMaxY(extent)-CGRectGetMaxY(box),box.size.width,box.size.height);result=CGRectUnion(result,ci);
 }
 result=CGRectIntersection(extent,CGRectInset(result,-2,-2));return CGRectIsNull(result)?CGRectZero:result;
}

static CIKernel *geometryKernel(void){
 static CIKernel *kernel;static dispatch_once_t once;
 dispatch_once(&once,^{
  // Fixed-size uniforms, no image-sized CPU fields. Keeping changes from one
  // separate avoids rounding small CA factors to 1 in single precision.
  NSMutableString *parameters=[NSMutableString new],*names=[NSMutableString new],*selection=[NSMutableString new];
  for(NSUInteger i=0;i<16;i++){
   [parameters appendFormat:@", vec3 n%lu",(unsigned long)i];[names appendFormat:@", n%lu",(unsigned long)i];
   if(i<15)[selection appendFormat:@"if(index<%lu.5)return n%lu; ",(unsigned long)i,(unsigned long)i];
   else [selection appendString:@"return n15; "];
  }
  NSString *code=[NSString stringWithFormat:@"vec3 node(float index%@) { %@ } kernel vec4 explicitGeometry(sampler src, vec4 extent, vec4 centerCropCount, vec4 radiusTransform%@) { vec2 top=vec2(destCoord().x-extent.x,extent.w-(destCoord().y-extent.y)); vec2 cropShift=(top-extent.zw*0.5)*centerCropCount.z; vec2 relative=top-centerCropCount.xy+cropShift; vec2 normalized=vec2(radiusTransform.x*relative.x+radiusTransform.z*relative.y,radiusTransform.y*relative.x+radiusTransform.w*relative.y); float p=clamp(length(normalized)*(centerCropCount.w-1.0)-0.5,0.0,centerCropCount.w-1.0); float left=floor(p); vec3 change=mix(node(left%@),node(min(left+1.0,centerCropCount.w-1.0)%@),fract(p)); vec3 combined=vec3(change.x+change.y+change.x*change.y,change.x,change.x+change.z+change.x*change.z); vec2 r=top+cropShift+relative*combined.r; vec2 g=top+cropShift+relative*combined.g; vec2 b=top+cropShift+relative*combined.b; vec2 hi=extent.zw-vec2(0.5); if(r.x<0.5||r.y<0.5||r.x>hi.x||r.y>hi.y||g.x<0.5||g.y<0.5||g.x>hi.x||g.y>hi.y||b.x<0.5||b.y<0.5||b.x>hi.x||b.y>hi.y)return vec4(0.0); vec4 red=sample(src,samplerTransform(src,extent.xy+vec2(r.x,extent.w-r.y))); vec4 green=sample(src,samplerTransform(src,extent.xy+vec2(g.x,extent.w-g.y))); vec4 blue=sample(src,samplerTransform(src,extent.xy+vec2(b.x,extent.w-b.y))); vec3 color=vec3(red.a>0.0?red.r/red.a:0.0,green.a>0.0?green.g/green.a:0.0,blue.a>0.0?blue.b/blue.a:0.0); return vec4(color*green.a,green.a); }",parameters,selection,parameters,names,names];
  kernel=[CIKernel kernelWithString:code];
 });return kernel;
}

CIImage*LensSonyExplicitGeometryImage(CIImage*input,NSDictionary*source,LensSonyExplicitPixelFrame frame,double ds,double ts,BOOL constrain,NSError**error){
 CGRect extent=input.extent;LensSonyGeometryTransform transform;
 if(!input||CGRectIsEmpty(extent)||CGRectIsInfinite(extent)||!isfinite(extent.origin.x)||!isfinite(extent.origin.y)||extent.size.width!=frame.outputSize.width||extent.size.height!=frame.outputSize.height||!LensSonyPrepareGeometry(source,frame,ds,ts,&transform))return imageError(error);
 if(!validTransform(&transform))return imageError(error);
 BOOL identity=YES;for(NSUInteger i=0;i<transform.distortionCount;i++)if(transform.distortion[i]!=1)identity=NO;for(NSUInteger i=0;i<transform.tcaCount;i++)if(transform.red[i]!=1||transform.blue[i]!=1)identity=NO;
 if(identity)return input;
 // Keep the intermediate's pixel canvas at zero origin. Reapply the original
 // placement after the finite sampling boundary, including negative origins.
 if(extent.origin.x!=0||extent.origin.y!=0){CIImage*local=[input imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x,-extent.origin.y)];if(local.extent.origin.x!=0||local.extent.origin.y!=0||!CGSizeEqualToSize(local.extent.size,extent.size))return imageError(error);CIImage*corrected=LensSonyExplicitGeometryImage(local,source,frame,ds,ts,constrain,error);return corrected?[corrected imageByApplyingTransform:CGAffineTransformMakeTranslation(extent.origin.x,extent.origin.y)]:nil;}
 double scale=constrain?LensSonyGeometryCropScale(&transform,extent.size):1;if(!isfinite(scale))return imageError(error);
 CIKernel *kernel=geometryKernel();
 if(!kernel)return imageError(error);
 CGPoint center=CGPointApplyAffineTransform(CGPointMake(transform.centerX,transform.centerY),transform.calibrationToOutput);CGAffineTransform a=transform.outputToCalibration;
 NSUInteger count=MAX(transform.distortionCount,transform.tcaCount);
 NSMutableArray *arguments=[NSMutableArray arrayWithArray:@[input,[CIVector vectorWithCGRect:extent],[CIVector vectorWithX:center.x Y:center.y Z:scale-1 W:count],[CIVector vectorWithX:a.a*transform.inverseRadius Y:a.b*transform.inverseRadius Z:a.c*transform.inverseRadius W:a.d*transform.inverseRadius]]];
 for(NSUInteger i=0;i<16;i++)[arguments addObject:[CIVector vectorWithX:i<transform.distortionCount?transform.distortion[i]-1:0 Y:i<transform.tcaCount?transform.red[i]-1:0 Z:i<transform.tcaCount?transform.blue[i]-1:0]];
 CIImage*result=[kernel applyWithExtent:extent roiCallback:^CGRect(int index,CGRect request){
  return LensSonyGeometrySourceROI(&transform,extent,request,scale);
 } arguments:arguments];
 // Keep finite source-pixel coverage before later preview/layer transforms.
 // Without a sampling boundary, CI can fuse a fractional transform into this
 // kernel and evaluate cropped-in content outside the original canvas edge.
 return result?[result imageByInsertingTiledIntermediate]:imageError(error);
}
