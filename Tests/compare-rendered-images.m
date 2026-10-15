#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#import <math.h>

// Read-only comparison of images exported by the real host during manual QA.
// Exports are private test artifacts, never part of the RAW editing workflow.
static NSData*decode(NSString*path,size_t*width,size_t*height){
 CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);if(!source)return nil;
 CGImageRef image=CGImageSourceCreateImageAtIndex(source,0,NULL);CFRelease(source);if(!image)return nil;
 *width=CGImageGetWidth(image);*height=CGImageGetHeight(image);if(!*width||!*height||*width>16000||*height>16000||(*width)*(*height)>120000000){CGImageRelease(image);return nil;}
 NSMutableData*data=[NSMutableData dataWithLength:(*width)*(*height)*4];CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
 CGContextRef context=CGBitmapContextCreate(data.mutableBytes,*width,*height,8,*width*4,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);CGColorSpaceRelease(space);
 if(!context){CGImageRelease(image);return nil;}CGContextDrawImage(context,CGRectMake(0,0,*width,*height),image);CGContextRelease(context);CGImageRelease(image);return data;
}
static NSString*checksum(NSData*data){unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString*hex=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[hex appendFormat:@"%02x",digest[i]];return hex;}
int main(int argc,char**argv){@autoreleasepool{
 if(argc!=4){fprintf(stderr,"Usage: compare-rendered-images baseline.png candidate.png report.json\n");return 1;}
 size_t aw=0,ah=0,bw=0,bh=0;NSData*a=decode(@(argv[1]),&aw,&ah),*b=decode(@(argv[2]),&bw,&bh);if(!a||!b||aw!=bw||ah!=bh){fprintf(stderr,"Image decoding failed or dimensions differ.\n");return 2;}
 const unsigned char*left=a.bytes,*right=b.bytes;NSUInteger changed=0;unsigned maximum=0;double sum=0,squares=0;
 for(NSUInteger pixel=0;pixel<aw*ah;pixel++){BOOL differs=NO;for(NSUInteger c=0;c<4;c++){unsigned delta=(unsigned)abs((int)left[pixel*4+c]-(int)right[pixel*4+c]);differs|=delta!=0;maximum=MAX(maximum,delta);sum+=delta;squares+=(double)delta*delta;}changed+=differs;}
 NSDictionary*report=@{@"scope":@"Host export or PXD rendered-preview comparison after decoding to premultiplied 8-bit sRGB RGBA; not optical correction accuracy",@"width":@(aw),@"height":@(ah),@"pixelEqual":@(changed==0),@"changedPixelFraction":@((double)changed/(aw*ah)),@"maximumChannelDelta8Bit":@(maximum),@"meanAbsoluteChannelDelta8Bit":@(sum/a.length),@"rootMeanSquareChannelDelta8Bit":@(sqrt(squares/a.length)),@"baselineDecodedPixelSHA256":checksum(a),@"candidateDecodedPixelSHA256":checksum(b)};
 NSError*error=nil;NSData*json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];if(![json writeToFile:@(argv[3]) options:NSDataWritingAtomic error:&error]){fprintf(stderr,"Report write failed.\n");return 3;}puts([[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
}}
