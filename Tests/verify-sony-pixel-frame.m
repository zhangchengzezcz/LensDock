#import "LensSonyGeometry.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreImage/CoreImage.h>
static void check(BOOL ok,NSString*name,NSMutableArray*failures){if(!ok)[failures addObject:name];}
static NSString*digest(NSData*data){unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);NSMutableString*s=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",bytes[i]];return s;}
static LensSonyExplicitPixelFrame frameFor(NSDictionary*f,NSUInteger orientation){NSArray*c=f[@"calibrationSize"],*r=f[@"decodedRegion"],*o=f[@"unrotatedOutputSize"];BOOL swapped=orientation>=5;return (LensSonyExplicitPixelFrame){CGSizeMake([c[0]doubleValue],[c[1]doubleValue]),CGRectMake([r[0]doubleValue],[r[1]doubleValue],[r[2]doubleValue],[r[3]doubleValue]),CGSizeMake([o[swapped?1:0]doubleValue],[o[swapped?0:1]doubleValue]),orientation};}
static CGPoint scalarPoint(NSDictionary*source,LensSonyGeometryTransform*t,CGPoint point,NSUInteger channel){CGPoint p=CGPointApplyAffineTransform(point,t->outputToCalibration);double dx=p.x-t->centerX,dy=p.y-t->centerY,r=hypot(dx,dy)*t->inverseRadius;double factor=LensSonyEmbeddedGeometryFactor(source,r,channel,YES,YES);return CGPointApplyAffineTransform(CGPointMake(t->centerX+dx*factor,t->centerY+dy*factor),t->calibrationToOutput);}
int main(int argc,char**argv){@autoreleasepool{
 NSMutableArray*failures=[NSMutableArray new];NSString*fixturePath=@"Tests/Fixtures/Sony-pixel-frame-reference.json";NSData*fixtureData=[NSData dataWithContentsOfFile:fixturePath];
 NSDictionary*fixture=fixtureData?[NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:nil]:nil;if(!fixture)return 2;
 check([fixture[@"generatorSHA256"]isEqual:digest([NSData dataWithContentsOfFile:@"Tests/make-sony-pixel-frame-reference.py"])],@"reference generator hash",failures);
 NSDictionary*source=fixture[@"source"];double maximumError=0;NSUInteger outside=0;
 for(NSArray*row in fixture[@"cases"]){
  NSUInteger orientation=[row[1]unsignedIntegerValue],channel=[row[2]unsignedIntegerValue];LensSonyExplicitPixelFrame frame=frameFor(fixture[@"frames"][[row[0]unsignedIntegerValue]],orientation);
  LensSonyGeometryTransform transform;BOOL prepared=LensSonyPrepareGeometry(source,frame,[row[3]doubleValue],[row[4]doubleValue],&transform);
  CGPoint point=CGPointMake([row[5]doubleValue],[row[6]doubleValue]),mapped;BOOL valid=prepared&&LensSonyMapGeometryPoint(&transform,point,channel,&mapped);double error=valid?hypot(mapped.x-[row[7]doubleValue],mapped.y-[row[8]doubleValue]):INFINITY;
  check(valid&&error<=2e-10,@"60-digit explicit frame/orientation reference",failures);maximumError=fmax(maximumError,error);
  if(valid&&(mapped.x<0||mapped.y<0||mapped.x>frame.outputSize.width||mapped.y>frame.outputSize.height))outside++;
 }
 check(outside>0,@"radial mapping retains outside coordinates for later crop instead of clamping",failures);
 LensSonyExplicitPixelFrame base=frameFor(fixture[@"frames"][0],1);LensSonyGeometryTransform t;
 NSUInteger rejected=0;
 NSArray*badStrengths=@[@-1,@2.001,@(NAN),@(INFINITY)];
 for(NSNumber*strength in badStrengths)for(NSUInteger axis=0;axis<2;axis++){
  BOOL ok=LensSonyPrepareGeometry(source,base,axis?1:strength.doubleValue,axis?strength.doubleValue:1,&t);check(!ok&&t.version==0,@"invalid strength rejected and output cleared",failures);rejected++;
 }
 LensSonyExplicitPixelFrame invalid[13];for(NSUInteger i=0;i<13;i++)invalid[i]=base;
 invalid[0].orientation=0;invalid[1].orientation=9;invalid[2].calibrationSize.width=NAN;invalid[3].calibrationSize.height=INFINITY;
 invalid[4].calibrationSize.width=40001;invalid[5].calibrationSize=CGSizeMake(30000,30000);
 invalid[6].decodedRegion.origin.x=-1;invalid[7].decodedRegion.origin.y=-1;invalid[8].decodedRegion.size.width=0;
 invalid[9].decodedRegion.size.height=161;invalid[10].outputSize.width=0;invalid[11].outputSize.height=NAN;invalid[12].outputSize=CGSizeMake(30000,30000);
 for(NSUInteger i=0;i<13;i++){BOOL ok=LensSonyPrepareGeometry(source,invalid[i],1,1,&t);check(!ok&&t.version==0,@"invalid explicit frame rejected",failures);rejected++;}
 NSDictionary*missingD=@{@"provider":source[@"provider"],@"tables":@{@"ChromaticAberration":source[@"tables"][@"ChromaticAberration"]}};
 check(LensSonyPrepareGeometry(missingD,base,0,1,&t),@"missing disabled D leaves TCA independent",failures);
 check(!LensSonyPrepareGeometry(missingD,base,1,1,&t),@"missing requested D rejected",failures);rejected++;
 NSDictionary*missingT=@{@"provider":source[@"provider"],@"tables":@{@"Distortion":source[@"tables"][@"Distortion"]}};
 check(LensSonyPrepareGeometry(missingT,base,1,0,&t),@"missing disabled TCA leaves D independent",failures);
 check(!LensSonyPrepareGeometry(missingT,base,1,1,&t),@"missing requested TCA rejected",failures);rejected++;
 NSDictionary*badSource=@{@"provider":source[@"provider"],@"tables":@{@"Distortion":@{@"nodeCount":@2,@"values":@[@-32768,@-32768]}}};
 check(!LensSonyPrepareGeometry(badSource,base,1,0,&t),@"nonpositive radial curve rejected",failures);rejected++;
 NSDictionary*wrongCount=@{@"provider":source[@"provider"],@"tables":@{@"Distortion":@{@"nodeCount":@2,@"values":@[@0,@1]},@"ChromaticAberration":source[@"tables"][@"ChromaticAberration"]}};
 check(!LensSonyPrepareGeometry(wrongCount,base,1,1,&t),@"conflicting source node counts rejected",failures);rejected++;
 check(!LensSonyPrepareGeometry(@{@"provider":@"unknown",@"tables":source[@"tables"]},base,1,1,&t),@"unknown provider rejected",failures);rejected++;
 check(!LensSonyPrepareGeometry(source,base,1,1,NULL),@"null prepare output rejected",failures);rejected++;
 check(LensSonyPrepareGeometry(source,base,1,1,&t),@"valid transform prepared",failures);CGPoint p;
 check(!LensSonyMapGeometryPoint(&t,CGPointMake(NAN,1),0,&p)&&isnan(p.x),@"NaN point rejected",failures);rejected++;
 check(!LensSonyMapGeometryPoint(&t,CGPointMake(1,INFINITY),0,&p)&&isnan(p.x),@"infinite point rejected",failures);rejected++;
 check(!LensSonyMapGeometryPoint(&t,CGPointMake(1,1),3,&p)&&isnan(p.x),@"unknown channel rejected",failures);rejected++;
 check(!LensSonyMapGeometryPoint(NULL,CGPointMake(1,1),0,&p)&&isnan(p.x),@"absent prepared transform rejected",failures);rejected++;
 check(!LensSonyMapGeometryPoint(&t,CGPointMake(1,1),0,NULL),@"null mapping output rejected",failures);rejected++;
 LensSonyGeometryTransform corrupt=t;corrupt.tcaCount=17;check(!LensSonyMapGeometryPoint(&corrupt,CGPointMake(1,1),1,&p),@"bad prepared count rejected even for green",failures);rejected++;
 NSDictionary*zero=@{@"provider":source[@"provider"],@"tables":@{@"Distortion":@{@"nodeCount":@2,@"values":@[@0,@0]},@"ChromaticAberration":@{@"nodeCount":@2,@"red":@[@0,@0],@"blue":@[@0,@0]}}};
 NSUInteger identities=0;for(NSUInteger f=0;f<[fixture[@"frames"]count];f++)for(NSUInteger orientation=1;orientation<=8;orientation++)for(NSUInteger c=0;c<3;c++)for(NSUInteger disabled=0;disabled<2;disabled++){
  LensSonyGeometryTransform z;CGPoint point=CGPointMake(12.3456789012345,26.7890123456789),mapped;
  BOOL valid=LensSonyPrepareGeometry(disabled?source:zero,frameFor(fixture[@"frames"][f],orientation),disabled?0:2,disabled?0:2,&z)&&LensSonyMapGeometryPoint(&z,point,c,&mapped);
  check(valid&&mapped.x==point.x&&mapped.y==point.y,@"zero or disabled transform exact identity through every frame",failures);identities++;
 }
 // Independent native EXIF orientation oracle. The in-memory ramp encodes
 // canonical pixel positions, so reading its actual Core Image transforms
 // checks the frame against the decoder's orientation convention as well as
 // the separate Decimal fixture. No optical table is applied in this check.
 double maxNativeOrientationError=0;NSUInteger nativeOrientationImages=0,nativeOrientationPixels=0;NSMutableArray*nativeImages=[NSMutableArray new];
 CIContext*context=[CIContext contextWithOptions:@{kCIContextWorkingColorSpace:NSNull.null,kCIContextOutputColorSpace:NSNull.null,kCIContextWorkingFormat:@(kCIFormatRGBAf)}];
 NSMutableData*ramp=[NSMutableData dataWithLength:120*160*16];float*gradient=ramp.mutableBytes;
 for(NSUInteger y=0;y<160;y++)for(NSUInteger x=0;x<120;x++){NSUInteger i=(y*120+x)*4;gradient[i]=(x+.5)/120;gradient[i+1]=(y+.5)/160;gradient[i+2]=.1;gradient[i+3]=1;}
 CIImage*input=[CIImage imageWithBitmapData:ramp bytesPerRow:120*16 size:CGSizeMake(120,160) format:kCIFormatRGBAf colorSpace:nil];
 // Bitmap row zero is the top row, while CI image-space Y starts at the
 // bottom. Confirm that convention by sampling the actual source's bottom-left.
 CIFilter*probe=[CIFilter filterWithName:@"CIAreaAverage" withInputParameters:@{kCIInputImageKey:input,kCIInputExtentKey:[CIVector vectorWithCGRect:CGRectMake(0,0,1,1)]}];float bottomLeft[4]={0};
 [context render:probe.outputImage toBitmap:bottomLeft rowBytes:16 bounds:CGRectMake(0,0,1,1) format:kCIFormatRGBAf colorSpace:nil];
 check(hypot(bottomLeft[0]*120-.5,bottomLeft[1]*160-159.5)<=3e-5,@"native bitmap top-row and image-space bottom-left convention",failures);
 for(NSUInteger f=0;f<2;f++)for(NSUInteger orientation=1;orientation<=8;orientation++){@autoreleasepool{
  LensSonyExplicitPixelFrame frame=frameFor(fixture[@"frames"][f],orientation);CGRect region=frame.decodedRegion;
  CGRect ciRegion=CGRectMake(region.origin.x,160-CGRectGetMaxY(region),region.size.width,region.size.height);
  CIImage*crop=[[input imageByCroppingToRect:ciRegion]imageByApplyingTransform:CGAffineTransformMakeTranslation(-ciRegion.origin.x,-ciRegion.origin.y)];
  CIImage*oriented=[crop imageByApplyingOrientation:(int)orientation];CGRect extent=oriented.extent;
  frame.outputSize=extent.size;LensSonyGeometryTransform transform;BOOL prepared=LensSonyPrepareGeometry(source,frame,0,0,&transform);
  check(prepared&&extent.origin.x==0&&extent.origin.y==0,@"native orientation extent and explicit frame prepared",failures);if(!prepared)continue;
  NSUInteger width=frame.outputSize.width,height=frame.outputSize.height;NSMutableData*buffer=[NSMutableData dataWithLength:width*height*16];float*pixels=buffer.mutableBytes;
  [context render:oriented toBitmap:pixels rowBytes:width*16 bounds:extent format:kCIFormatRGBAf colorSpace:nil];double imageError=0;
  for(NSUInteger y=0;y<height;y++)for(NSUInteger x=0;x<width;x++){
   CGPoint canonical=CGPointApplyAffineTransform(CGPointMake(x+.5,y+.5),transform.outputToCalibration);NSUInteger i=(y*width+x)*4;
   double error=hypot(pixels[i]*120-canonical.x,pixels[i+1]*160-canonical.y);maxNativeOrientationError=fmax(maxNativeOrientationError,error);imageError=fmax(imageError,error);nativeOrientationPixels++;
  }
  [nativeImages addObject:@{@"frame":@(f),@"orientation":@(orientation),@"maximumCanonicalPixelError":@(imageError),@"firstPixelCanonical":@[@(pixels[0]*120),@(pixels[1]*160)],@"expectedFirstCanonical":@[@(CGPointApplyAffineTransform(CGPointMake(.5,.5),transform.outputToCalibration).x),@(CGPointApplyAffineTransform(CGPointMake(.5,.5),transform.outputToCalibration).y)]}];nativeOrientationImages++;
 }}
 check(nativeOrientationImages==16&&maxNativeOrientationError<=3e-5,@"all native Core Image EXIF orientations match explicit canonical coordinates",failures);
 NSUInteger nodeCountCases=0;double maxNodeCountDifference=0;
 for(NSUInteger n=2;n<=16;n++){
  NSMutableArray*d=[NSMutableArray new],*red=[NSMutableArray new],*blue=[NSMutableArray new];
  for(NSUInteger i=0;i<n;i++){[d addObject:@(((NSInteger)(i%3)-1)*512)];[red addObject:@(((NSInteger)(i%5)-2)*2048)];[blue addObject:@(i==n-1?32767:((NSInteger)(i%7)-3)*1024)];}
  NSDictionary*s=@{@"provider":source[@"provider"],@"tables":@{@"Distortion":@{@"nodeCount":@(n),@"values":d},@"ChromaticAberration":@{@"nodeCount":@(n),@"red":red,@"blue":blue}}};
  LensSonyGeometryTransform transform;BOOL valid=LensSonyPrepareGeometry(s,base,1,1,&transform);check(valid,@"every supported node count prepares",failures);if(!valid)continue;
  for(NSUInteger k=0;k<=4*n;k++)for(NSUInteger c=0;c<3;c++){
   double radius=(double)k/(2*(n-1));CGPoint canonical=CGPointMake(transform.centerX+radius/transform.inverseRadius,transform.centerY);
   CGPoint point=CGPointApplyAffineTransform(canonical,transform.calibrationToOutput),mapped,expected=scalarPoint(s,&transform,point,c);
   BOOL ok=LensSonyMapGeometryPoint(&transform,point,c,&mapped);double difference=ok?hypot(mapped.x-expected.x,mapped.y-expected.y):INFINITY;
   maxNodeCountDifference=fmax(maxNodeCountDifference,difference);nodeCountCases++;
  }
 }
 check(maxNodeCountDifference<=2e-10,@"all supported node counts agree with scalar core including endpoint extension",failures);
 // Numeric hot-loop comparison only. It is not a claim of faster Pixelmator
 // rendering and has no speed threshold (shared host load is variable).
 const NSUInteger count=200000;volatile double preparedSum=0,scalarSum=0;double maxScalarDifference=0;
 NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;
 for(NSUInteger i=0;i<count;i++){CGPoint q;LensSonyMapGeometryPoint(&t,CGPointMake((i%90)+.5,((i/90)%80)+.5),i%3,&q);preparedSum+=q.x+q.y;}
 double preparedSeconds=NSProcessInfo.processInfo.systemUptime-start;start=NSProcessInfo.processInfo.systemUptime;
 for(NSUInteger i=0;i<count;i++){CGPoint q=scalarPoint(source,&t,CGPointMake((i%90)+.5,((i/90)%80)+.5),i%3);scalarSum+=q.x+q.y;}
 double scalarSeconds=NSProcessInfo.processInfo.systemUptime-start;
 for(NSUInteger i=0;i<4096;i++){CGPoint point=CGPointMake((i%90)+.5,((i/90)%80)+.5),a,b=scalarPoint(source,&t,point,i%3);BOOL ok=LensSonyMapGeometryPoint(&t,point,i%3,&a);double error=ok?hypot(a.x-b.x,a.y-b.y):INFINITY;maxScalarDifference=fmax(maxScalarDifference,error);}
 check(maxScalarDifference<=2e-10&&fabs(preparedSum-scalarSum)<1e-5,@"prepared mapping agrees with validated scalar core",failures);
 NSDictionary*report=@{@"scope":@"Explicit mathematical frame mapping and native EXIF orientation only; no manufacturer frame inference, product renderer integration, physical optical accuracy or added lens coverage",@"decimalReferenceCases":@([fixture[@"cases"]count]),@"maximumReferenceErrorPixels":@(maximumError),@"exactIdentityCases":@(identities),@"invalidInputCases":@(rejected),@"outsideCoordinatesPreserved":@(outside),@"maximumScalarCoreDifferencePixels":@(maxScalarDifference),@"supportedNodeCounts":@{@"minimum":@2,@"maximum":@16,@"cases":@(nodeCountCases),@"maximumScalarCoreDifferencePixels":@(maxNodeCountDifference)},@"nativeOrientationCheck":@{@"images":@(nativeOrientationImages),@"perImage":nativeImages,@"pixels":@(nativeOrientationPixels),@"maximumCanonicalPixelError":@(maxNativeOrientationError),@"reference":@"Actual CIImage imageByApplyingOrientation results for canonical coordinate ramps, all eight EXIF orientations on full and offset crop",@"opticalTablesApplied":@NO},@"preparedTransformBytes":@(sizeof(LensSonyGeometryTransform)),@"hotLoopBenchmark":@{@"pointsPerPath":@(count),@"preparedSeconds":@(preparedSeconds),@"dictionaryScalarSeconds":@(scalarSeconds),@"scope":@"Developer scalar arithmetic only, not whole-app or image-render timing"},@"fixtureSHA256":digest(fixtureData),@"nativeHeaderSHA256":digest([NSData dataWithContentsOfFile:@"Sources/Native/LensSonyGeometry.h"]),@"testSourceSHA256":digest([NSData dataWithContentsOfFile:@"Tests/verify-sony-pixel-frame.m"]),@"manufacturerFrameProven":@NO,@"productRendererCallsMapper":@NO,@"failures":failures};
 NSString*output=argc>1?@(argv[1]):@"Build/Tests/sony-pixel-frame-verification.json";[[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]writeToFile:output atomically:YES];printf("Sony explicit pixel frame: %lu references, %lu exact identities, %lu rejected inputs, %lu failures.\n",(unsigned long)[fixture[@"cases"]count],(unsigned long)identities,(unsigned long)rejected,(unsigned long)failures.count);return failures.count?1:0;
}}
