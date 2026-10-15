#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>

static NSString*sha(NSData*data){unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,hash);NSMutableString*s=[NSMutableString new];for(unsigned i=0;i<sizeof(hash);i++)[s appendFormat:@"%02x",hash[i]];return s;}
static NSDictionary*decode(NSURL*url){
 CGImageSourceRef reader=CGImageSourceCreateWithURL((__bridge CFURLRef)url,NULL);if(!reader)return nil;CGImageRef image=CGImageSourceCreateImageAtIndex(reader,0,NULL);CFRelease(reader);if(!image)return nil;
 size_t w=CGImageGetWidth(image),h=CGImageGetHeight(image);CGColorSpaceRef space=CGImageGetColorSpace(image);
 if(!w||!h||w*h>120000000||CGImageGetBitsPerComponent(image)!=16||!space||CGColorSpaceGetModel(space)!=kCGColorSpaceModelRGB){CGImageRelease(image);return nil;}
 NSData*icc=CFBridgingRelease(CGColorSpaceCopyICCData(space));NSMutableData*rgba=[NSMutableData dataWithLength:w*h*8];
 CGContextRef context=CGBitmapContextCreate(rgba.mutableBytes,w,h,16,w*8,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder16Little);
 if(!context){CGImageRelease(image);return nil;}CGContextDrawImage(context,CGRectMake(0,0,w,h),image);CGContextRelease(context);CGImageRelease(image);
 return @{@"width":@(w),@"height":@(h),@"rgba":rgba,@"icc":icc?:NSData.data};
}
static NSDictionary*compare(NSURL*left,NSURL*right){
 NSDictionary*a=decode(left),*b=decode(right);if(!a||!b||![a[@"width"]isEqual:b[@"width"]]||![a[@"height"]isEqual:b[@"height"]]||![a[@"icc"]isEqual:b[@"icc"]])return nil;
 NSData*ad=a[@"rgba"],*bd=b[@"rgba"];const uint16_t*x=ad.bytes,*y=bd.bytes;NSUInteger pixels=ad.length/8,changed=0,alpha=0,maximum=0;double sum=0,squares=0;NSMutableData*counts=[NSMutableData dataWithLength:65536*sizeof(NSUInteger)];NSUInteger*hist=counts.mutableBytes;
 for(NSUInteger p=0;p<pixels;p++){BOOL different=NO;for(int c=0;c<3;c++){unsigned delta=(unsigned)abs((int)x[p*4+c]-(int)y[p*4+c]);hist[delta]++;maximum=MAX(maximum,delta);sum+=delta;squares+=(double)delta*delta;different|=delta!=0;}changed+=different;alpha+=x[p*4+3]!=y[p*4+3];}
 NSUInteger q99=0,q999=0,total=0;BOOL got99=NO;for(NSUInteger i=0;i<65536;i++){total+=hist[i];if(total>=ceil(pixels*3*.99)&&!got99){q99=i;got99=YES;}if(total>=ceil(pixels*3*.999)){q999=i;break;}}
 return @{@"scope":@"Read-only 16-bit PNG comparison in the identical embedded RGB color space; no 8-bit conversion, no optical accuracy claim",@"width":a[@"width"],@"height":a[@"height"],@"bitsPerChannel":@16,@"identicalEmbeddedICC":@YES,@"iccSHA256":sha(a[@"icc"]),@"changedRGBPixelFraction":@((double)changed/pixels),@"maximumRGBDelta16Bit":@(maximum),@"p99RGBDelta16Bit":@(q99),@"p999RGBDelta16Bit":@(q999),@"meanAbsoluteRGBDelta16Bit":@(sum/(pixels*3)),@"rmsRGBDelta16Bit":@(sqrt(squares/(pixels*3))),@"changedAlphaPixels":@(alpha),@"baselinePixelSHA256":sha(ad),@"candidatePixelSHA256":sha(bd)};
}
static BOOL writeFixture(NSURL*url,NSUInteger width,BOOL changed){
 NSMutableData*data=[NSMutableData dataWithLength:width*8*8];uint16_t*p=data.mutableBytes;for(NSUInteger i=0;i<width*8;i++){p[i*4]=10000;p[i*4+1]=20000;p[i*4+2]=30000;p[i*4+3]=65535;}if(changed)p[4*4]++;
 CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);CGContextRef context=CGBitmapContextCreate(p,width,8,16,width*8,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder16Little);CGColorSpaceRelease(space);if(!context)return NO;
 CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);CGImageDestinationRef writer=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,NULL);if(!writer){CGImageRelease(image);return NO;}CGImageDestinationAddImage(writer,image,NULL);BOOL ok=CGImageDestinationFinalize(writer);CFRelease(writer);CGImageRelease(image);return ok;
}
int main(int argc,char**argv){@autoreleasepool{
 if(argc==1){
  NSURL*root=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];NSURL*a=[root URLByAppendingPathComponent:@"a.png"],*b=[root URLByAppendingPathComponent:@"b.png"],*c=[root URLByAppendingPathComponent:@"c.png"];
  if(!writeFixture(a,8,NO)||!writeFixture(b,8,YES)||!writeFixture(c,7,NO))return 1;NSDictionary*same=compare(a,a),*one=compare(a,b);BOOL passed=same&&[same[@"maximumRGBDelta16Bit"]unsignedIntegerValue]==0&&[one[@"maximumRGBDelta16Bit"]unsignedIntegerValue]==1&&[one[@"p99RGBDelta16Bit"]unsignedIntegerValue]==0&&[one[@"p999RGBDelta16Bit"]unsignedIntegerValue]==1&&fabs([one[@"changedRGBPixelFraction"]doubleValue]-1./64)<1e-9&&!compare(a,c);[NSFileManager.defaultManager removeItemAtURL:root error:nil];if(!passed)return 2;puts("16-bit comparator detects a single 1/65535 channel step, exact identity and dimension mismatch.");return 0;
 }
 if(argc!=4){fprintf(stderr,"Usage: compare-rendered-images-16 baseline.png candidate.png report.json\n");return 1;}
 NSDictionary*report=compare([NSURL fileURLWithPath:@(argv[1])],[NSURL fileURLWithPath:@(argv[2])]);if(!report){fprintf(stderr,"Requires matching dimensions, 16-bit RGB images and identical embedded ICC.\n");return 3;}
 NSData*json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];if(![json writeToFile:@(argv[3]) atomically:YES])return 4;puts([[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
}}
