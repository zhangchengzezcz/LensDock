// Optional developer benchmark. Run each mode/view in a fresh process.
// Procedural source + real recorded nodes in a hypothetical explicit frame;
// not decoded-photo optics, PXD I/O, launch time or all-Mac performance.
#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <dlfcn.h>
#import <libproc.h>
#import <sys/resource.h>
#import <time.h>
#import <CommonCrypto/CommonDigest.h>
#import "LensSonyGeometryArchive.h"
#import "LensCorrectionSettings.h"
#import "LensNativeState.h"
#ifndef LENS_SONY_BENCH_IMPLEMENTATION_SHA
#define LENS_SONY_BENCH_IMPLEMENTATION_SHA "unrecorded"
#endif
typedef struct { double v[8]; } BenchTransform;
@interface NSObject(SonyBench)
- (CIImage *)applyFor:(CIImage *)input scale:(CGPoint)scale extent:(CGRect)extent bounds:(CGRect)bounds layerOriginalSizeInBacking:(CGSize)size layerCombinedTransformInBacking:(BenchTransform)transform;
@end
static double seconds(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec*1e-9;}
static NSDictionary *memory(void){
    struct rusage r={0};getrusage(RUSAGE_SELF,&r);struct rusage_info_v4 info={0};
    BOOL ok=proc_pid_rusage(getpid(),RUSAGE_INFO_V4,(rusage_info_t*)&info)==0;
    return @{@"peakResidentBytes":@(r.ru_maxrss),@"physicalFootprintBytes":@(ok?info.ri_phys_footprint:0),@"peakPhysicalFootprintBytes":@(ok?info.ri_lifetime_max_phys_footprint:0)};
}
static NSString *digest(NSData *d){unsigned char b[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,b);NSMutableString *s=[NSMutableString new];for(NSUInteger i=0;i<sizeof(b);i++)[s appendFormat:@"%02x",b[i]];return s;}
int main(int argc,char **argv){@autoreleasepool{
    if(argc!=4){fputs("usage: benchmark-sony-geometry-effect control|D|T|DT full|preview|roi output.json\n",stderr);return 2;}
    NSString *mode=@(argv[1]),*view=@(argv[2]);if(![@[@"control",@"D",@"T",@"DT"]containsObject:mode]||![@[@"full",@"preview",@"roi"]containsObject:view])return 2;
    void *library=dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL);
    BenchTransform *identity=library?dlsym(library,"PTProjectiveTransformIdentity"):NULL;if(!identity)return 3;
    const NSUInteger w=6000,h=4000;CGRect full=CGRectMake(0,0,w,h);CGSize size=full.size;
    NSDictionary *fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Tests/Fixtures/Sony-embedded-metadata.json"]options:0 error:nil];
    NSDictionary *source=LensSonyEmbeddedSourceEvidence(fixture[@"files"][0][@"expectedGroupedFields"]);
    LensSonyExplicitPixelFrame frame={size,full,size,1};NSDictionary *payload=LensSonyExplicitGeometryPayload(source,frame);
    NSDictionary *report=@{@"width":@(w),@"height":@(h),@"workingTransfer":@"linear",@"geometryProvider":@"sony-explicit-frame-v1",@"explicitGeometry":payload,@"distortionProfileAvailable":@YES,@"tcaProfileAvailable":@YES,@"vignettingProfileAvailable":@NO};
    NSDictionary *saved=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Tests/Fixtures/A6000-reopen-binding.json"]options:0 error:nil];NSMutableDictionary *live=[saved[@"savedBinding"]mutableCopy];live[@"workingTransfer"]=@"linear";
    NSDictionary *plan=@{@"report":report,@"sourceBinding":LensCorrectionSourceBinding(live)};
    double ds=[mode containsString:@"D"]?1:0,ts=[mode containsString:@"T"]?1:0;
    NSDictionary *config=@{@"distortionEnabled":@(ds>0),@"distortionStrength":@100,@"tcaEnabled":@(ts>0),@"tcaStrength":@100,@"vignettingEnabled":@NO,@"vignettingStrength":@50,@"constrainCropEnabled":@YES};
    CIContext *context=[CIContext contextWithOptions:@{kCIContextWorkingColorSpace:NSNull.null,kCIContextOutputColorSpace:NSNull.null,kCIContextWorkingFormat:@(kCIFormatRGBAf),kCIContextCacheIntermediates:@NO}];
    CIColorKernel *ramp=[CIColorKernel kernelWithString:@"kernel vec4 ramp(vec2 size) { vec2 p=vec2(destCoord().x,size.y-destCoord().y)/size; return vec4(0.1+0.2*p.x,0.1+0.2*p.y,0.1+0.1*(p.x+p.y),1.0); }"];
    CIImage *input=[ramp applyWithExtent:full arguments:@[[CIVector vectorWithX:size.width Y:size.height]]];if(!input)return 4;
    unsigned char warm[16*16*4];[context render:input toBitmap:warm rowBytes:16*4 bounds:CGRectMake(0,0,16,16) format:kCIFormatRGBA8 colorSpace:nil];
    double scale=[view isEqual:@"preview"]?.25:1;CGRect bounds=[view isEqual:@"roi"]?CGRectMake(2800,1800,400,400):CGRectMake(0,0,w*scale,h*scale);
    NSUInteger bw=bounds.size.width,bh=bounds.size.height;NSMutableData *pixels=[NSMutableData dataWithLength:bw*bh*4];memset(pixels.mutableBytes,1,pixels.length);
    NSDictionary *before=memory();double start=seconds();id effects=LensEffectsForCorrectionPlan(plan,[NSData dataWithContentsOfFile:@"Resources/native-effects-template.json"],config,nil,nil);NSData *archive=LensEffectsJSON(effects,nil);effects=LensEffectsFromJSON(archive);
    CIImage *image=[effects applyFor:input scale:CGPointMake(1,1) extent:full bounds:full layerOriginalSizeInBacking:size layerCombinedTransformInBacking:*identity];
    if(!image)return 5;if(scale!=1)image=[image imageByApplyingTransform:CGAffineTransformMakeScale(scale,scale)];double preparationMS=(seconds()-start)*1000;
    LensSonyGeometryTransform transform;LensSonyPrepareGeometry(source,frame,ds,ts,&transform);double crop=(ds||ts)?LensSonyGeometryCropScale(&transform,size):1;
    NSMutableArray *runs=[NSMutableArray new];BOOL passed=YES;
    for(NSUInteger run=0;run<2;run++){@autoreleasepool{
        double t=seconds();[context render:image toBitmap:pixels.mutableBytes rowBytes:bw*4 bounds:bounds format:kCIFormatRGBA8 colorSpace:nil];double elapsed=(seconds()-t)*1000;
        const unsigned char *p=pixels.bytes;NSUInteger nonopaque=0;for(NSUInteger i=0;i<bw*bh;i++)nonopaque+=p[4*i+3]!=255;
        double maximum=0;
        for(NSUInteger iy=1;iy<=7;iy++)for(NSUInteger ix=1;ix<=9;ix++){
            NSUInteger x=bw*ix/10,y=bh*iy/8;CGPoint q=CGPointMake((bounds.origin.x+x+.5)/scale,(h*scale-CGRectGetMaxY(bounds)+y+.5)/scale);
            q=CGPointMake((q.x-w/2.)*crop+w/2.,(q.y-h/2.)*crop+h/2.);CGPoint points[3];BOOL valid=YES;for(NSUInteger c=0;c<3;c++)valid&=LensSonyMapGeometryPoint(&transform,q,c,&points[c]);
            if(!valid){passed=NO;continue;}double expected[]={.1+.2*points[0].x/w,.1+.2*points[1].y/h,.1+.1*(points[2].x/w+points[2].y/h)};
            for(NSUInteger c=0;c<3;c++)maximum=fmax(maximum,fabs(p[(y*bw+x)*4+c]/255.-expected[c]));
        }
        BOOL okay=nonopaque==0&&maximum<=2./255.;passed&=okay;
        [runs addObject:@{@"run":@(run),@"renderMS":@(elapsed),@"memoryAfter":memory(),@"nonopaquePixels":@(nonopaque),@"maximumProbeError":@(maximum),@"passed":@(okay)}];
    }}
    NSDictionary *result=@{@"scope":@"Fresh-process synthetic 24MP native archived effect benchmark, real recorded nodes in a hypothetical 6000x4000 frame. Excludes RAW decode, PXD I/O and application launch. Not optical or all-Mac acceptance.",@"mode":mode,@"view":view,@"sourcePixels":@[@(w),@(h)],@"renderBounds":@[@(bounds.origin.x),@(bounds.origin.y),@(bw),@(bh)],@"outputFormat":@"RGBA8, no color conversion",@"contextCacheIntermediates":@NO,@"sourceKernelWarmedBeforeMeasurement":@YES,@"memoryBeforePreparation":before,@"preparationMS":@(preparationMS),@"effectArchiveBytes":@(archive.length),@"outputBufferBytes":@(pixels.length),@"outputSHA256":digest(pixels),@"runs":runs,@"passed":@(passed),@"compiledImplementationSHA256":[NSString stringWithUTF8String:LENS_SONY_BENCH_IMPLEMENTATION_SHA],@"benchmarkSourceSHA256":digest([NSData dataWithContentsOfFile:@"Tests/benchmark-sony-geometry-effect.m"])};
    if(![[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@(argv[3])atomically:YES])return 6;
    printf("%s/%s: prepare %.2f ms, render %.2f / %.2f ms, peak footprint %.1f MiB, %s.\n",mode.UTF8String,view.UTF8String,preparationMS,[runs[0][@"renderMS"]doubleValue],[runs[1][@"renderMS"]doubleValue],[runs[1][@"memoryAfter"][@"peakPhysicalFootprintBytes"]doubleValue]/1048576.,passed?"passed":"FAILED");return passed?0:1;
}}
