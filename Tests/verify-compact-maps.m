#import "LensNativeProfileEngine.h"
#import "LensGainMap.h"

static double sample(const float*f,NSUInteger w,NSUInteger h,double x,double y,int channel,int components){
 NSUInteger ix=MIN(w-2,(NSUInteger)floor(x)),iy=MIN(h-2,(NSUInteger)floor(y));double fx=x-ix,fy=y-iy;
 return (1-fy)*((1-fx)*f[(iy*w+ix)*components+channel]+fx*f[(iy*w+ix+1)*components+channel])+fy*((1-fx)*f[((iy+1)*w+ix)*components+channel]+fx*f[((iy+1)*w+ix+1)*components+channel]);
}
static double verifyCoordinates(NSDictionary*plan,NSData*original,NSString*key){
 NSDictionary*r=plan[@"report"];NSUInteger w=[r[@"width"]unsignedIntegerValue],h=[r[@"height"]unsignedIntegerValue],mw=[r[@"geometryMapWidth"]unsignedIntegerValue],mh=[r[@"geometryMapHeight"]unsignedIntegerValue];
 NSData*grid=[plan[@"normalizedGeometryMapsLZFSE"][key]decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];
 if([r[@"geometryMapEncoding"]isEqual:@"normalized-source-RGf-bottom-up-v1"])return [grid isEqual:original]?0:INFINITY;
 if(grid.length!=mw*mh*8||original.length!=w*h*8)return INFINITY;
 NSData*bytes=[plan[@"geometryResidualMapsLZFSE"][key]decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];const unsigned char*residual=bytes.bytes;BOOL hybrid=[r[@"geometryMapEncoding"]isEqual:@"pixel-displacement-residual-RG8-bottom-up-grid-v4"];
 if(hybrid&&bytes.length!=w*h*2)return INFINITY;
 const float*g=grid.bytes,*source=original.bytes;double worst=0;
 for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++)for(int c=0;c<2;c++){
  double value=sample(g,mw,mh,(double)x*(mw-1)/(w-1),(double)y*(mh-1)/(h-1),c,2)+(c==0?x:y)+.5;
  if(hybrid)value+=((int)residual[(y*w+x)*2+c]-128)*[r[@"geometryResidualStepPixels"]doubleValue];
  worst=fmax(worst,fabs(value-(double)source[(y*w+x)*2+c]*(c==0?w:h)));
 }
 return worst;
}
int main(){@autoreleasepool{
 const NSUInteger w=384,h=256;NSMutableArray*checks=[NSMutableArray new];
 for(NSNumber*noisy in @[@NO,@YES]){
  NSMutableData*data=[NSMutableData dataWithLength:w*h*8];float*f=data.mutableBytes;
  for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){
   double dx=.02*sin((double)x/w*3)+([noisy boolValue]?((x+y)%2?.09:-.09):0);
   f[(y*w+x)*2]=(x+.5+dx)/w;f[(y*w+x)*2+1]=(y+.5+.01*cos((double)y/h*3))/h;
  }
  NSDictionary*full=@{@"report":@{@"width":@(w),@"height":@(h)},@"workingGeometryMapsFloat32":@{@"D":data}};
  NSDictionary*compact=LensCompactGeometryPlan(full,.001,nil);double worst=verifyCoordinates(compact,data,@"D");
  NSString*expected=[noisy boolValue]?@"pixel-displacement-residual-RG8-bottom-up-grid-v4":@"pixel-displacement-RGf-bottom-up-grid-v3";
  if(!compact||compact[@"workingGeometryMapsFloat32"]||![compact[@"report"][@"geometryMapEncoding"]isEqual:expected]||worst>.001)return 1;
  [checks addObject:@{@"noiseFixture":noisy,@"independentEveryCoordinateMaxErrorPixels":@(worst),@"encoding":expected}];
  if(LensCompactGeometryPlan(full,0,nil)||LensCompactGeometryPlan(full,NAN,nil))return 2;
 }
 // A bilinear, asymmetric scalar field checks gain dimensions and orientation.
 NSMutableData*gain=[NSMutableData dataWithLength:w*h*4];float*f= gain.mutableBytes;
 for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++)f[y*w+x]=1+.2*(double)x/(w-1)+.3*(double)y/(h-1)+.1*(double)x*y/((w-1)*(h-1));
 NSDictionary*compact=LensCompactGainPlan(@{@"report":@{@"width":@(w),@"height":@(h)},@"linearGainFloat32BottomUp":gain},.000001,nil),*report=compact[@"report"];
 NSUInteger gw=0,gh=0;if(!LensGainMapDimensions(report,w,h,&gw,&gh)||gw*gh>=w*h)return 3;
 const float*g=[compact[@"linearGainFloat32BottomUp"]bytes];double gainWorst=0;
 for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++)gainWorst=fmax(gainWorst,fabs(sample(g,gw,gh,(double)x*(gw-1)/(w-1),(double)y*(gh-1)/(h-1),0,1)-f[y*w+x]));
 if(gainWorst>.000001)return 4;
 NSData*encoded=LensEncodeGainGrid(compact[@"linearGainFloat32BottomUp"],nil);
 NSDictionary*stored=@{@"matchedProfile":report,@"gainGridLosslessEncoding":@"float32-delta-byteplanes-LZFSE-v1",@"gainGridLosslessData":encoded};
 if(![LensDecodedGainData(stored,nil)isEqual:compact[@"linearGainFloat32BottomUp"]])return 5;
 // Bitwise lossless coding includes arbitrary IEEE bit patterns, not merely
 // positive optical values; this is a byte-codec test, not a calibration.
 NSMutableData*bits=[NSMutableData dataWithLength:64*64*4];uint32_t*values=bits.mutableBytes,state=0x12345678;
 for(int i=0;i<64*64;i++){state^=state<<13;state^=state>>17;state^=state<<5;values[i]=state;}
 NSDictionary*random=@{@"matchedProfile":@{@"width":@64,@"height":@64},@"gainGridLosslessEncoding":@"float32-delta-byteplanes-LZFSE-v1",@"gainGridLosslessData":LensEncodeGainGrid(bits,nil)};
 if(![LensDecodedGainData(random,nil)isEqual:bits])return 6;
 NSMutableDictionary*bad=[stored mutableCopy];bad[@"gainGridLosslessEncoding"]=@"unknown";if(LensDecodedGainData(bad,nil))return 7;
 bad=[stored mutableCopy];bad[@"matchedProfile"]=@{@"width":@(w),@"height":@(h),@"gainMapEncoding":@"linear-gain-Rf-bottom-up-grid-v1",@"gainMapWidth":@2,@"gainMapHeight":@2};if(LensDecodedGainData(bad,nil))return 8;
 // Compare the new temporary-working-map path with the retained dense API
 // after every EXIF orientation. These small fields exercise all seven planes
 // and gain, independently of the renderer and without a private RAW fixture.
 NSMutableArray*orientations=[NSMutableArray new];
 NSURL*db=[NSURL fileURLWithPath:@"Resources/LensBridge/db"],*lib=[NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"];
 for(int orientation=1;orientation<=8;orientation++){@autoreleasepool{
  NSDictionary*m=@{@"Make":@"Canon",@"Model":@"Canon EOS 40D",@"LensModel":@"Canon EF-S 17-85mm f/4-5.6 IS USM",@"FocalLength":@17,@"FNumber":@4,@"Orientation":@(orientation)};
  NSDictionary*dense=LensNativeProfilePlanFullGeometry(m,db,lib,w,h,nil),*working=LensNativeProfilePlanIncludingGeometry(m,db,lib,w,h,nil);
  if(!dense||!working||working[@"workingGeometryMapsFloat32"]||[dense[@"normalizedGeometryMapsLZFSE"]count]!=7||[working[@"normalizedGeometryMapsLZFSE"]count]!=7)return 9;
  double coordinateWorst=0;
  for(NSString*key in dense[@"normalizedGeometryMapsLZFSE"]){NSData*original=[dense[@"normalizedGeometryMapsLZFSE"][key]decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];coordinateWorst=fmax(coordinateWorst,verifyCoordinates(working,original,key));}
  if(coordinateWorst>.001)return 10;
  NSUInteger cw=0,ch=0;if(!LensGainMapDimensions(working[@"report"],w,h,&cw,&ch))return 11;
  const float*dg=[dense[@"linearGainFloat32BottomUp"]bytes],*cg=[working[@"linearGainFloat32BottomUp"]bytes];if(!dg||!cg)return 12;
  double scalarWorst=0;
  for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++)scalarWorst=fmax(scalarWorst,fabs(sample(cg,cw,ch,(double)x*(cw-1)/(w-1),(double)y*(ch-1)/(h-1),0,1)-dg[y*w+x]));
  if(scalarWorst>.00001)return 13;
  [orientations addObject:@{@"orientation":@(orientation),@"geometryPlanes":@7,@"independentEveryCoordinateMaxErrorPixels":@(coordinateWorst),@"independentGainMaxError":@(scalarWorst)}];
 }}
 NSDictionary*result=@{@"scope":@"Synthetic compact-map byte decoding and all eight oriented Lensfun working-map versus dense-path comparisons, not real RAW or optical accuracy",@"geometry":checks,@"orientedWorkingPath":orientations,@"independentGainMaxError":@(gainWorst),@"gainLosslessBitwiseRoundtrip":@YES,@"arbitraryIEEEBitPatternsRoundtrip":@YES,@"malformedCodecRejected":@YES};
 [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/compact-maps-verification.json" atomically:YES];puts("Compact geometry/residual fields, scalar grid, bitwise gain codec and malformed-data checks passed.");
}}
