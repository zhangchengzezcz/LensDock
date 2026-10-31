#import "LensSonyGeometryImage.h"
#import <CommonCrypto/CommonDigest.h>
static void check(BOOL ok,NSString*name,NSMutableArray*failures){if(!ok&&failures.count<32)[failures addObject:name];}
static NSString*digest(NSData*data){unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);NSMutableString*s=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",bytes[i]];return s;}
static NSData*pattern(NSUInteger w,NSUInteger h,BOOL alpha){NSMutableData*d=[NSMutableData dataWithLength:w*h*16];float*p=d.mutableBytes;for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){NSUInteger i=(y*w+x)*4;double a=(x+.5)/w,b=(y+.5)/h,opacity=alpha?.4+.3*a+.15*b:1;p[i]=(.1+.2*a)*opacity;p[i+1]=(.1+.2*b)*opacity;p[i+2]=(.1+.1*(a+b))*opacity;p[i+3]=opacity;}return d;}
static void sample(const float*p,NSUInteger w,NSUInteger h,CGPoint point,double*out){double x=point.x-.5,y=point.y-.5;NSUInteger ix=floor(x),iy=floor(y);double fx=x-ix,fy=y-iy;for(NSUInteger c=0;c<4;c++){out[c]=0;for(NSUInteger j=0;j<2;j++)for(NSUInteger i=0;i<2;i++)out[c]+=p[(MIN(h-1,iy+j)*w+MIN(w-1,ix+i))*4+c]*(i?fx:1-fx)*(j?fy:1-fy);}}
int main(int argc,char**argv){@autoreleasepool{
 NSMutableArray*failures=[NSMutableArray new],*renders=[NSMutableArray new];NSDictionary*source=@{@"provider":@"sony-subifd-radial-source-v1",@"tables":@{@"Distortion":@{@"nodeCount":@2,@"values":@[@4096,@4096]},@"ChromaticAberration":@{@"nodeCount":@2,@"red":@[@8192,@8192],@"blue":@[@-16384,@-16384]}}};
 NSDictionary*zero=@{@"provider":source[@"provider"],@"tables":@{@"Distortion":@{@"nodeCount":@2,@"values":@[@0,@0]},@"ChromaticAberration":@{@"nodeCount":@2,@"red":@[@0,@0],@"blue":@[@0,@0]}}};
 CIContext*context=[CIContext contextWithOptions:@{kCIContextWorkingColorSpace:NSNull.null,kCIContextOutputColorSpace:NSNull.null,kCIContextWorkingFormat:@(kCIFormatRGBAf),kCIContextCacheIntermediates:@NO}];
 // Literal projected calibration centres for the off-centre (3,7,90,130)
 // crop in a 120x160 frame, for EXIF 1...8. This is independent of the native
 // preparation/inverse-transform code exercised by the image provider.
 CGPoint centers[]={CGPointMake(57,73),CGPointMake(33,73),CGPointMake(33,57),CGPointMake(57,57),CGPointMake(73,57),CGPointMake(57,57),CGPointMake(57,33),CGPointMake(73,33)};
 double settings[][2]={{1,0},{0,1},{1,1},{.5,1.5}};NSUInteger identities=0;double worst=0;
 for(NSUInteger orientation=1;orientation<=8;orientation++)for(NSUInteger alpha=0;alpha<2;alpha++)for(NSUInteger translated=0;translated<2;translated++)for(NSUInteger setting=0;setting<4;setting++)for(NSUInteger constrain=0;constrain<2;constrain++){@autoreleasepool{
  BOOL swapped=orientation>=5;NSUInteger w=swapped?130:90,h=swapped?90:130;CGRect extent=CGRectMake(translated?17:0,translated?-31:0,w,h);
  NSData*data=pattern(w,h,alpha);CIImage*input=[[CIImage imageWithBitmapData:data bytesPerRow:w*16 size:CGSizeMake(w,h) format:kCIFormatRGBAf colorSpace:nil]imageByApplyingTransform:CGAffineTransformMakeTranslation(extent.origin.x,extent.origin.y)];
  LensSonyExplicitPixelFrame frame={CGSizeMake(120,160),CGRectMake(3,7,90,130),CGSizeMake(w,h),orientation};double ds=settings[setting][0],ts=settings[setting][1];NSError*error=nil;
  CIImage*image=LensSonyExplicitGeometryImage(input,source,frame,ds,ts,constrain,&error);check(image&&CGRectEqualToRect(image.extent,extent),@"explicit image produced with preserved extent",failures);if(!image)continue;
  if(!setting&&!constrain){check(LensSonyExplicitGeometryImage(input,zero,frame,2,2,YES,nil)==input&&LensSonyExplicitGeometryImage(input,source,frame,0,0,YES,nil)==input,@"zero and disabled image paths preserve object identity",failures);identities+=2;}
  LensSonyGeometryTransform transform;check(LensSonyPrepareGeometry(source,frame,ds,ts,&transform),@"render reference transform prepares",failures);double scale=constrain?LensSonyGeometryCropScale(&transform,frame.outputSize):1;
  NSMutableData*output=[NSMutableData dataWithLength:w*h*16];float*p=output.mutableBytes;[context render:image toBitmap:p rowBytes:w*16 bounds:extent format:kCIFormatRGBAf colorSpace:nil];
  const float*original=data.bytes;double maximum=0;NSUInteger transparent=0;CGPoint center=centers[orientation-1];
  for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){
   CGPoint target=CGPointMake(((x+.5)-w/2.)*scale+w/2.,((y+.5)-h/2.)*scale+h/2.);double samples[3][4],expected[4]={0};BOOL valid=YES;
   for(NSUInteger c=0;c<3;c++){double factor=(1+.25*ds)*(1+ts*(c==0?1./256:c==2?-1./128:0));CGPoint q=CGPointMake(center.x+(target.x-center.x)*factor,center.y+(target.y-center.y)*factor);if(q.x<.5||q.y<.5||q.x>w-.5||q.y>h-.5){valid=NO;break;}sample(original,w,h,q,samples[c]);}
   if(valid){for(NSUInteger c=0;c<3;c++)expected[c]=samples[c][c]/samples[c][3]*samples[1][3];expected[3]=samples[1][3];}else transparent++;
   NSUInteger i=(y*w+x)*4;for(NSUInteger c=0;c<4;c++)maximum=fmax(maximum,fabs(p[i+c]-expected[c]));
  }
  check(maximum<=3e-5,[NSString stringWithFormat:@"render reference o%lu a%lu t%lu s%lu c%lu",orientation,alpha,translated,setting,constrain],failures);
  if(constrain)check(transparent==0,@"conservative crop has no out-of-bounds reference samples",failures);
  worst=fmax(worst,maximum);[renders addObject:@{@"orientation":@(orientation),@"alphaVaries":@(alpha),@"translated":@(translated),@"distortionStrength":@(ds),@"tcaStrength":@(ts),@"constrain":@(constrain),@"cropScale":@(scale),@"maximumRGBAError":@(maximum),@"referenceTransparentPixels":@(transparent)}];
 }}
 // Real variable-node source tables in a deliberately explicit hypothetical
 // frame. This checks image sampling against the separately verified scalar
 // transform, and does not certify that frame for the source camera.
 NSDictionary*fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Tests/Fixtures/Sony-embedded-metadata.json"] options:0 error:nil];
 NSDictionary*realSource=LensSonyEmbeddedSourceEvidence(fixture[@"files"][0][@"expectedGroupedFields"]);check(realSource!=nil,@"variable source fixture loads",failures);
 NSMutableArray*variableRenders=[NSMutableArray new];double variableWorst=0;
 for(NSUInteger orientation=1;orientation<=8;orientation++)for(NSUInteger constrain=0;constrain<2;constrain++){@autoreleasepool{
  NSUInteger w=orientation>=5?160:240,h=orientation>=5?240:160;CGSize size=CGSizeMake(w,h);LensSonyExplicitPixelFrame frame={CGSizeMake(6024,4024),CGRectMake(12,12,6000,4000),size,orientation};
  NSData*data=pattern(w,h,YES);CIImage*input=[CIImage imageWithBitmapData:data bytesPerRow:w*16 size:size format:kCIFormatRGBAf colorSpace:nil];
  CIImage*image=LensSonyExplicitGeometryImage(input,realSource,frame,1,1,constrain,nil);LensSonyGeometryTransform t;BOOL prepared=LensSonyPrepareGeometry(realSource,frame,1,1,&t);
  check(image&&prepared,@"variable table image and scalar transform prepare",failures);if(!image||!prepared)continue;
  double scale=constrain?LensSonyGeometryCropScale(&t,size):1;NSMutableData*rendered=[NSMutableData dataWithLength:w*h*16];[context render:image toBitmap:rendered.mutableBytes rowBytes:w*16 bounds:CGRectMake(0,0,w,h) format:kCIFormatRGBAf colorSpace:nil];
  const float*original=data.bytes,*actual=rendered.bytes;double maximum=0;NSUInteger transparent=0;
  for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){
   CGPoint target=CGPointMake(((x+.5)-w/2.)*scale+w/2.,((y+.5)-h/2.)*scale+h/2.);double samples[3][4],expected[4]={0};BOOL valid=YES;
   for(NSUInteger c=0;c<3;c++){CGPoint q;if(!LensSonyMapGeometryPoint(&t,target,c,&q)||q.x<.5||q.y<.5||q.x>w-.5||q.y>h-.5){valid=NO;break;}sample(original,w,h,q,samples[c]);}
   if(valid){for(NSUInteger c=0;c<3;c++)expected[c]=samples[c][c]/samples[c][3]*samples[1][3];expected[3]=samples[1][3];}else transparent++;
   for(NSUInteger c=0;c<4;c++)maximum=fmax(maximum,fabs(actual[(y*w+x)*4+c]-expected[c]));
  }
  check(maximum<3e-5,@"variable table render agrees with scalar-sampling reference",failures);if(constrain)check(transparent==0,@"variable table crop has no out-of-source samples",failures);
  variableWorst=fmax(variableWorst,maximum);[variableRenders addObject:@{@"orientation":@(orientation),@"constrain":@(constrain),@"maximumRGBAError":@(maximum),@"referenceTransparentPixels":@(transparent)}];
 }}
 check(variableRenders.count==16,@"all variable table image combinations ran",failures);
 NSMutableArray*fractional=[NSMutableArray new];NSUInteger fractionalAlphaDifferences=0;
 for(NSUInteger orientation=1;orientation<=8;orientation++){@autoreleasepool{
  CGSize native=orientation>=5?CGSizeMake(130,90):CGSizeMake(90,130),fraction=orientation>=5?CGSizeMake(130.25,90.5):CGSizeMake(90.5,130.25);
  CIImage*constant=[[CIImage imageWithColor:[CIColor colorWithRed:.2 green:.3 blue:.4 alpha:1]]imageByCroppingToRect:CGRectMake(0,0,native.width,native.height)];
  LensSonyExplicitPixelFrame frame={CGSizeMake(120,160),CGRectMake(3,7,90,130),native,orientation};CIImage*corrected=LensSonyExplicitGeometryImage(constant,source,frame,.5,1.5,YES,nil);check(corrected!=nil,@"explicit image produced before preview transform",failures);if(!corrected)continue;
  // Apply the lens operator in its explicit source pixel frame, then apply
  // the same fractional preview transform to corrected and control images.
  // Core Image reports an integral extent around that fractional coverage.
  CGAffineTransform preview=CGAffineTransformMake(fraction.width/native.width,0,0,fraction.height/native.height,17.25,-31.125);
  CIImage*input=[constant imageByApplyingTransform:preview],*image=[corrected imageByApplyingTransform:preview];CGRect extent=input.extent;
  CGRect bounds=CGRectIntegral(extent);NSUInteger w=bounds.size.width,h=bounds.size.height;NSMutableData*a=[NSMutableData dataWithLength:w*h],*b=[NSMutableData dataWithLength:w*h];
  [context render:image toBitmap:a.mutableBytes rowBytes:w bounds:bounds format:kCIFormatA8 colorSpace:nil];[context render:input toBitmap:b.mutableBytes rowBytes:w bounds:bounds format:kCIFormatA8 colorSpace:nil];NSUInteger different=0;
  NSUInteger partial=0;for(NSUInteger i=0;i<w*h;i++){different+=((unsigned char*)a.bytes)[i]!=((unsigned char*)b.bytes)[i];partial+=((unsigned char*)b.bytes)[i]!=255;}fractionalAlphaDifferences+=different;
  check(partial>0,@"fractional preview control has partial edge coverage",failures);[fractional addObject:@{@"orientation":@(orientation),@"differentAlphaPixels":@(different),@"controlNonopaquePixels":@(partial)}];
 }}
 check(fractional.count==8&&fractionalAlphaDifferences==0,@"fractional preview alpha equals uncorrected preview control",failures);
 // Nonmonotonic positive curves stress interval ROI bounds independently of
 // the constant-factor image reference above.
 NSDictionary*curved=@{@"provider":source[@"provider"],@"tables":@{@"Distortion":@{@"nodeCount":@4,@"values":@[@0,@4096,@-2048,@1024]},@"ChromaticAberration":@{@"nodeCount":@4,@"red":@[@-16384,@8192,@0,@-8192],@"blue":@[@8192,@-16384,@16384,@0]}}};NSUInteger roiPoints=0,roiMisses=0;
 for(NSUInteger orientation=1;orientation<=8;orientation++)for(NSUInteger constrain=0;constrain<2;constrain++){
  CGSize size=orientation>=5?CGSizeMake(130,90):CGSizeMake(90,130);CGRect extent=CGRectMake(-17.25,29.125,size.width,size.height);LensSonyExplicitPixelFrame frame={CGSizeMake(120,160),CGRectMake(3,7,90,130),size,orientation};LensSonyGeometryTransform t;check(LensSonyPrepareGeometry(curved,frame,.5,1,&t),@"nonmonotonic ROI transform prepares",failures);double scale=constrain?LensSonyGeometryCropScale(&t,size):1;
  for(NSUInteger ty=0;ty<3;ty++)for(NSUInteger tx=0;tx<3;tx++){
   CGRect request=CGRectMake(extent.origin.x+tx*(size.width-17)/2,extent.origin.y+ty*(size.height-19)/2,17,19),roi=LensSonyGeometrySourceROI(&t,extent,request,scale);
   for(NSUInteger y=0;y<19;y++)for(NSUInteger x=0;x<17;x++)for(NSUInteger c=0;c<3;c++){
    CGPoint top=CGPointMake(request.origin.x-extent.origin.x+x+.5,CGRectGetMaxY(extent)-(request.origin.y+y+.5));top=CGPointMake((top.x-size.width/2)*scale+size.width/2,(top.y-size.height/2)*scale+size.height/2);CGPoint q;BOOL mapped=LensSonyMapGeometryPoint(&t,top,c,&q);check(mapped,@"ROI reference point maps",failures);
    CGPoint ci=CGPointMake(extent.origin.x+q.x,CGRectGetMaxY(extent)-q.y);if(CGRectContainsPoint(extent,ci)&&!CGRectContainsPoint(roi,ci))roiMisses++;roiPoints++;
   }
  }
 }
 check(roiMisses==0,@"bounded source ROI covers every in-source reference sample",failures);
 LensSonyExplicitPixelFrame base={CGSizeMake(120,160),CGRectMake(3,7,90,130),CGSizeMake(90,130),1};CIImage*input=[[CIImage imageWithColor:[CIColor colorWithRed:.2 green:.3 blue:.4 alpha:1]]imageByCroppingToRect:CGRectMake(0,0,90,130)];NSError*error=nil;
 check(!LensSonyExplicitGeometryImage(input,@{@"provider":@"unknown",@"tables":source[@"tables"]},base,1,1,NO,&error)&&error!=nil,@"unknown source fails with error",failures);
 check(!LensSonyExplicitGeometryImage(input,source,base,NAN,1,NO,nil),@"nonfinite image strength rejected",failures);base.outputSize.width=91;check(!LensSonyExplicitGeometryImage(input,source,base,1,1,NO,nil),@"extent/frame mismatch rejected",failures);
 check(renders.count==256,@"all image combinations ran",failures);
 NSDictionary*report=@{@"scope":@"Synthetic explicit-frame CI image primitive; not a selected manufacturer frame, real optical correction, product provider, host save/reopen/export or added lens coverage",@"renders":renders,@"renderCount":@(renders.count),@"maximumRGBAError":@(worst),@"variableTableRenders":variableRenders,@"variableTableRenderCount":@(variableRenders.count),@"variableTableMaximumRGBAError":@(variableWorst),@"variableTableReference":@"Pinned A6000 tables, hypothetical explicit frame, CPU bilinear sampling using the separately verified scalar transform; not independent manufacturer-frame evidence",@"identityObjectChecks":@(identities),@"fractionalPreviewChecks":fractional,@"roiReferencePoints":@(roiPoints),@"roiMisses":@(roiMisses),@"productionProfileRouteEnabled":@NO,@"manufacturerFrameProven":@NO,@"sourceSHA256":@{@"Sources/Native/LensSonyGeometryImage.h":digest([NSData dataWithContentsOfFile:@"Sources/Native/LensSonyGeometryImage.h"]),@"Sources/Native/LensSonyGeometryImage.m":digest([NSData dataWithContentsOfFile:@"Sources/Native/LensSonyGeometryImage.m"]),@"Tests/verify-sony-geometry-image.m":digest([NSData dataWithContentsOfFile:@"Tests/verify-sony-geometry-image.m"]),@"Tests/Fixtures/Sony-embedded-metadata.json":digest([NSData dataWithContentsOfFile:@"Tests/Fixtures/Sony-embedded-metadata.json"])},@"failures":failures};
 NSString*output=argc>1?@(argv[1]):@"Build/Tests/sony-geometry-image-verification.json";[[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]writeToFile:output atomically:YES];printf("Sony explicit image: %lu renders, %lu fractional checks, %lu ROI points, %lu failures.\n",(unsigned long)renders.count,(unsigned long)fractional.count,(unsigned long)roiPoints,(unsigned long)failures.count);return failures.count?1:0;
}}
