#import "LensSonyGeometryImage.h"
#import <CommonCrypto/CommonDigest.h>
static NSString *digest(NSData*d){unsigned char b[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,b);NSMutableString*s=[NSMutableString new];for(NSUInteger i=0;i<sizeof(b);i++)[s appendFormat:@"%02x",b[i]];return s;}
// Native GPU sampler coordinates are float32. The predeclared budgets are
// .003 pixels up to 6000 and .008 up to 16000 (several float ULPs), not optics.
int main(){@autoreleasepool{
    CIContext *context=[CIContext contextWithOptions:@{kCIContextWorkingColorSpace:NSNull.null,kCIContextOutputColorSpace:NSNull.null,kCIContextWorkingFormat:@(kCIFormatRGBAf),kCIContextCacheIntermediates:@NO}];
    CIColorKernel *ramp=[CIColorKernel kernelWithString:@"kernel vec4 coordinates(vec2 size, float axis) { float v=axis<0.5?destCoord().x:size.y-destCoord().y;return vec4(v,v,v,1.0); }"];
    NSMutableArray *failures=[NSMutableArray new],*cases=[NSMutableArray new];NSUInteger samples=0;double worst=0;
    for(NSUInteger orientation=1;orientation<=8;orientation++)for(NSUInteger count=2;count<=16;count++)for(NSUInteger large=0;large<2;large++){@autoreleasepool{
        NSMutableArray *d=[NSMutableArray new],*r=[NSMutableArray new],*b=[NSMutableArray new];
        for(NSUInteger i=0;i<count;i++){[d addObject:@(((NSInteger)(i*7%9)-4)*64)];[r addObject:@(((NSInteger)(i*11%7)-3)*256)];[b addObject:@(((NSInteger)(i*5%9)-4)*256)];}
        NSDictionary *source=@{@"provider":@"sony-subifd-radial-source-v1",@"tables":@{@"Distortion":@{@"nodeCount":@(count),@"values":d},@"ChromaticAberration":@{@"nodeCount":@(count),@"red":r,@"blue":b}}};
        BOOL swapped=orientation>=5,scaled=count%2==0;CGSize size=swapped?(scaled?CGSizeMake(2731,4096):CGSizeMake(4000,6000)):(scaled?CGSizeMake(4096,2731):CGSizeMake(6000,4000));
        if(large)size=swapped?CGSizeMake(10000,16000):CGSizeMake(16000,10000);
        LensSonyExplicitPixelFrame frame={CGSizeMake(6400,4400),CGRectMake(211,83,6000,4000),size,orientation};
        double ds=count%2?.6:1.8,ts=count%3?1.4:.25;LensSonyGeometryTransform transform;
        if(!LensSonyPrepareGeometry(source,frame,ds,ts,&transform)){[failures addObject:@"coordinate test preparation failed"];continue;}
        double crop=LensSonyGeometryCropScale(&transform,size);CGPoint origin=orientation%2?CGPointZero:CGPointMake(17,-31);CGRect extent=CGRectMake(origin.x,origin.y,size.width,size.height);
        CGPoint centers[]={CGPointMake(12,12),CGPointMake(size.width-12,12),CGPointMake(size.width/2,size.height/2),CGPointMake(12,size.height-12),CGPointMake(size.width-12,size.height-12)};
        double maximum=0;
        for(NSUInteger axis=0;axis<2;axis++){@autoreleasepool{
            CIImage *input=[[ramp applyWithExtent:CGRectMake(0,0,size.width,size.height) arguments:@[[CIVector vectorWithX:size.width Y:size.height],@(axis)]]imageByApplyingTransform:CGAffineTransformMakeTranslation(origin.x,origin.y)];
            CIImage *image=LensSonyExplicitGeometryImage(input,source,frame,ds,ts,YES,nil);
            if(!image){[failures addObject:@"GPU coordinate image failed"];continue;}
            for(NSUInteger region=0;region<5;region++){
                CGRect bounds=CGRectMake(origin.x+floor(centers[region].x)-4,origin.y+floor(centers[region].y)-4,8,8);float actual[8*8*4];
                [context render:image toBitmap:actual rowBytes:8*16 bounds:bounds format:kCIFormatRGBAf colorSpace:nil];
                for(NSUInteger y=0;y<8;y++)for(NSUInteger x=0;x<8;x++){
                    CGPoint point=CGPointMake(bounds.origin.x-origin.x+x+.5,CGRectGetMaxY(extent)-CGRectGetMaxY(bounds)+y+.5);
                    point=CGPointMake((point.x-size.width/2)*crop+size.width/2,(point.y-size.height/2)*crop+size.height/2);
                    for(NSUInteger c=0;c<3;c++){
                        CGPoint q;BOOL valid=LensSonyMapGeometryPoint(&transform,point,c,&q);double expected=axis?q.y:q.x;
                        if(!valid||!isfinite(expected)||actual[(y*8+x)*4+3]!=1){if(failures.count<32)[failures addObject:@"GPU coordinate probe invalid or transparent"];continue;}
                        maximum=fmax(maximum,fabs(actual[(y*8+x)*4+c]-expected));samples++;
                    }
                }
            }
        }}
        double budget=large?.008:.003;
        if(maximum>budget&&failures.count<32)[failures addObject:[NSString stringWithFormat:@"GPU coordinate error o%lu n%lu large%lu: %.9g",orientation,count,large,maximum]];
        worst=fmax(worst,maximum);[cases addObject:@{@"orientation":@(orientation),@"nodeCount":@(count),@"outputSize":@[@(size.width),@(size.height)],@"translated":@(orientation%2==0),@"toleranceOutputPixels":@(budget),@"maximumCoordinateErrorPixels":@(maximum)}];
    }}
    if(cases.count!=240||samples!=460800)[failures addObject:@"incomplete GPU coordinate matrix"];
    NSDictionary *result=@{@"scope":@"Large explicit mathematical-frame GPU coordinate probes: synthetic nonmonotonic tables, all 2-16 node counts and EXIF orientations, up to the 16000-pixel product axis limit. Only small ROIs rendered, not complete 160MP photos. CPU scalar map was separately independently verified. Not manufacturer frame, optical, PXD or added lens coverage evidence.",@"cases":cases,@"caseCount":@(cases.count),@"coordinateSamples":@(samples),@"maximumCoordinateErrorPixels":@(worst),@"failures":failures,@"sourceSHA256":@{@"Sources/Native/LensSonyGeometryImage.m":digest([NSData dataWithContentsOfFile:@"Sources/Native/LensSonyGeometryImage.m"]),@"Tests/verify-sony-gpu-coordinates.m":digest([NSData dataWithContentsOfFile:@"Tests/verify-sony-gpu-coordinates.m"])}};
    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/sony-gpu-coordinate-verification.json"atomically:YES];
    printf("Sony GPU coordinates: %lu cases, %lu samples, max %.9g pixels, %lu failures.\n",(unsigned long)cases.count,(unsigned long)samples,worst,(unsigned long)failures.count);for(NSString *message in failures)fprintf(stderr,"%s\n",message.UTF8String);return failures.count?1:0;
}}
