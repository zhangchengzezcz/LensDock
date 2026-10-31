#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <dlfcn.h>
#import <CommonCrypto/CommonDigest.h>
#import "LensSonyGeometryArchive.h"
#import "LensCorrectionSettings.h"
#import "LensNativeState.h"
#import "LensCalibrationEvidence.h"

typedef struct { double v[8]; } EffectTransform;
@interface NSObject(SonyEffectTest)
- (CIImage *)applyFor:(CIImage *)input scale:(CGPoint)scale extent:(CGRect)extent bounds:(CGRect)bounds layerOriginalSizeInBacking:(CGSize)size layerCombinedTransformInBacking:(EffectTransform)transform;
@end
static void check(BOOL ok, NSString *name, NSMutableArray *failures) { if (!ok && failures.count < 32) [failures addObject:name]; }
static NSString *digest(NSData *data) { unsigned char bytes[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,bytes); NSMutableString *s=[NSMutableString new]; for(NSUInteger i=0;i<sizeof(bytes);i++)[s appendFormat:@"%02x",bytes[i]];return s; }
static NSData *pattern(NSUInteger w, NSUInteger h) {
    NSMutableData *data=[NSMutableData dataWithLength:w*h*16];float *p=data.mutableBytes;
    for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++) {
        double a=(x+.5)/w,b=(y+.5)/h,alpha=.4+.3*a+.15*b;NSUInteger i=(y*w+x)*4;
        p[i]=(.1+.2*a)*alpha;p[i+1]=(.1+.2*b)*alpha;p[i+2]=(.1+.1*(a+b))*alpha;p[i+3]=alpha;
    }return data;
}
static NSDictionary *settings(double ds, double ts, BOOL crop) {
    return @{@"distortionEnabled":@(ds>0),@"distortionStrength":@(ds*100),@"tcaEnabled":@(ts>0),@"tcaStrength":@(ts*100),
             @"vignettingEnabled":@NO,@"vignettingStrength":@50,@"constrainCropEnabled":@(crop)};
}
int main(){@autoreleasepool{
    void *lib=dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL);
    EffectTransform *identity=lib?dlsym(lib,"PTProjectiveTransformIdentity"):NULL;if(!identity)return 2;
    NSMutableArray *failures=[NSMutableArray new],*renders=[NSMutableArray new];
    NSDictionary *fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Tests/Fixtures/Sony-embedded-metadata.json"] options:0 error:nil];
    NSDictionary *source=LensSonyEmbeddedSourceEvidence(fixture[@"files"][0][@"expectedGroupedFields"]);
    NSDictionary *bindingFixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Tests/Fixtures/A6000-reopen-binding.json"] options:0 error:nil];
    NSData *envelope=[NSData dataWithContentsOfFile:@"Resources/native-effects-template.json"];
    CIContext *context=[CIContext contextWithOptions:@{kCIContextWorkingColorSpace:NSNull.null,kCIContextOutputColorSpace:NSNull.null,kCIContextWorkingFormat:@(kCIFormatRGBAf),kCIContextCacheIntermediates:@NO}];
    double strengths[][2]={{0,0},{1,0},{0,1},{1,1},{.6,1.4}};double worst=0;
    NSDictionary *samplePlan=nil,*sampleSettings=nil;NSData *sampleJSON=nil;
    for(NSUInteger orientation=1;orientation<=8;orientation++)for(NSUInteger encoded=0;encoded<2;encoded++)for(NSUInteger setting=0;setting<5;setting++)for(NSUInteger crop=0;crop<2;crop++){@autoreleasepool{
        NSUInteger w=orientation>=5?160:240,h=orientation>=5?240:160;CGRect rect=CGRectMake(0,0,w,h);
        LensSonyExplicitPixelFrame frame={CGSizeMake(6024,4024),CGRectMake(12,12,6000,4000),rect.size,orientation};
        NSDictionary *payload=LensSonyExplicitGeometryPayload(source,frame);check(payload!=nil,@"recorded source and explicit frame payload",failures);if(!payload)continue;
        NSString *transfer=encoded?@"encoded_sRGB":@"linear";
        NSDictionary *report=@{@"width":@(w),@"height":@(h),@"workingTransfer":transfer,@"geometryProvider":@"sony-explicit-frame-v1",@"explicitGeometry":payload,
            @"distortionProfileAvailable":@YES,@"tcaProfileAvailable":@YES,@"vignettingProfileAvailable":@NO};
        NSMutableDictionary *live=[bindingFixture[@"savedBinding"] mutableCopy];live[@"width"]=@(w);live[@"height"]=@(h);live[@"workingTransfer"]=transfer;
        NSDictionary *binding=LensCorrectionSourceBinding(live),*plan=@{@"report":report,@"sourceBinding":binding};
        double ds=strengths[setting][0],ts=strengths[setting][1];NSDictionary *config=settings(ds,ts,crop);
        id initial=LensEffectsForCorrectionPlan(plan,envelope,config,nil,nil);NSData *json=LensEffectsJSON(initial,nil);id effects=LensEffectsFromJSON(json);
        NSDictionary *saved=LensSavedCorrectionProfile(effects);check(effects&&[saved[@"profileFormatVersion"]isEqual:@6]&&[saved[@"workingTransfer"]isEqual:@"lensdock-explicit-v6"],@"native wrapper v6 archive roundtrip",failures);if(!effects)continue;
        check([saved[@"matchedProfile"]isEqual:report]&&[saved[@"sourceBinding"]isEqual:binding]&&[saved[@"correctionSettings"]isEqual:config],@"roundtrip retains source, explicit frame, binding and controls",failures);
        check(![saved[@"normalizedGeometryMapsLZFSE"]count]&&!saved[@"geometryResidualMapsLZFSE"]&&!saved[@"linearGainFloat32BottomUp"],@"no fabricated maps or vignette gain",failures);
        check(![saved[@"matchedProfile"][@"explicitGeometry"][@"source"][@"pixelFrameVerified"]boolValue],@"mathematical payload does not claim optical verification",failures);
        NSData *data=pattern(w,h);CIImage *input=[CIImage imageWithBitmapData:data bytesPerRow:w*16 size:rect.size format:kCIFormatRGBAf colorSpace:nil];
        CIImage *actual=[effects applyFor:input scale:CGPointMake(1,1) extent:rect bounds:rect layerOriginalSizeInBacking:rect.size layerCombinedTransformInBacking:*identity];
        CIImage *reference=input;
        if(ds||ts){if(encoded)reference=[reference imageByApplyingFilter:@"CISRGBToneCurveToLinear"];reference=LensSonyExplicitGeometryImage(reference,source,frame,ds,ts,crop,nil);if(encoded)reference=[reference imageByApplyingFilter:@"CILinearToSRGBToneCurve"];}
        check(actual&&reference,@"native wrapper produces explicit geometry",failures);if(!actual||!reference)continue;
        NSMutableData *a=[NSMutableData dataWithLength:w*h*16],*b=[NSMutableData dataWithLength:w*h*16];
        [context render:actual toBitmap:a.mutableBytes rowBytes:w*16 bounds:rect format:kCIFormatRGBAf colorSpace:nil];[context render:reference toBitmap:b.mutableBytes rowBytes:w*16 bounds:rect format:kCIFormatRGBAf colorSpace:nil];
        const float *pa=a.bytes,*pb=b.bytes;double maximum=0;for(NSUInteger i=0;i<w*h*4;i++)maximum=fmax(maximum,fabs(pa[i]-pb[i]));
        check(maximum<3e-5,@"archived native effect agrees with verified image primitive",failures);worst=fmax(worst,maximum);
        [renders addObject:@{@"orientation":@(orientation),@"encodedSRGB":@(encoded),@"distortionStrength":@(ds),@"tcaStrength":@(ts),@"constrain":@(crop),@"maximumRGBAError":@(maximum),@"archiveBytes":@(json.length)}];
        if(orientation==1&&!encoded&&setting==3&&crop){samplePlan=plan;sampleSettings=config;sampleJSON=json;}
    }}
    check(renders.count==160,@"all native archive/render combinations ran",failures);
    NSDictionary *saved=LensSavedCorrectionProfile(LensEffectsFromJSON(sampleJSON));
    NSDictionary *restored=LensPlanRestoringExplicitGeometry(saved,samplePlan[@"sourceBinding"]);
    check(restored&&[restored[@"report"]isEqual:samplePlan[@"report"]],@"reopened plan keeps the explicit provider and frame",failures);
    check(LensEffectsForCorrectionPlan(restored,envelope,settings(.8,1.2,YES),nil,nil)!=nil,@"restored plan remains editable",failures);
    NSMutableDictionary *otherLive=[samplePlan[@"sourceBinding"]mutableCopy],*otherInfo=[otherLive[@"sourceInformation"]mutableCopy];otherInfo[@"rawSHA256"]=@"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";otherLive[@"sourceInformation"]=otherInfo;
    check(!LensPlanRestoringExplicitGeometry(saved,otherLive),@"restoring on another RAW is rejected",failures);
    // Native wrapper output must keep its finite canvas under later fractional
    // preview transforms, including the partial coverage of the control.
    NSUInteger previewChecks=0;id effect=LensEffectsFromJSON(sampleJSON);CGRect full=CGRectMake(0,0,240,160);
    CIImage *opaque=[[CIImage imageWithColor:[CIColor colorWithRed:.2 green:.3 blue:.4 alpha:1]]imageByCroppingToRect:full];
    CIImage *warped=[effect applyFor:opaque scale:CGPointMake(1,1) extent:full bounds:full layerOriginalSizeInBacking:full.size layerCombinedTransformInBacking:*identity];
    for(NSNumber *s in @[@1,@.5,@.61875]) {
        CGAffineTransform transform=CGAffineTransformMake(s.doubleValue,0,0,s.doubleValue,17.25,-31.125);
        CIImage *actual=[warped imageByApplyingTransform:transform],*reference=[opaque imageByApplyingTransform:transform];CGRect bounds=CGRectIntegral(reference.extent);NSUInteger w=bounds.size.width,h=bounds.size.height;
        NSMutableData *a=[NSMutableData dataWithLength:w*h],*b=[NSMutableData dataWithLength:w*h];[context render:actual toBitmap:a.mutableBytes rowBytes:w bounds:bounds format:kCIFormatA8 colorSpace:nil];[context render:reference toBitmap:b.mutableBytes rowBytes:w bounds:bounds format:kCIFormatA8 colorSpace:nil];
        check([a isEqual:b],@"archived wrapper preview alpha equals uncorrected canvas",failures);previewChecks++;
    }
    NSArray *state=[NSJSONSerialization JSONObjectWithData:sampleJSON options:0 error:nil];NSString *archive=state[1][@"w"][0][@"versionSpecifiContainer"][@"effectUnkeyedContainer"][0][@"versionSpecifiContainer"][@"CIFilterNSCodingData"];
    CIFilter *filter=[NSKeyedUnarchiver unarchiveTopLevelObjectWithData:[[NSData alloc]initWithBase64EncodedString:archive options:0] error:nil];
    CIFilter *copied=[filter copy];check([[copied valueForKey:@"lensProfile"]isEqual:saved],@"copying a native filter keeps explicit payload and settings",failures);
    CGRect reducedRect=CGRectMake(17,-31,120,80);CIImage *reduced=[[CIImage imageWithColor:[CIColor colorWithRed:.2 green:.3 blue:.4 alpha:1]]imageByCroppingToRect:reducedRect];[copied setValue:reduced forKey:kCIInputImageKey];CIImage *reducedOutput=copied.outputImage;
    NSMutableData *alpha=[NSMutableData dataWithLength:120*80];[context render:reducedOutput toBitmap:alpha.mutableBytes rowBytes:120 bounds:reducedRect format:kCIFormatA8 colorSpace:nil];BOOL opaqueOutput=YES;for(NSUInteger i=0;i<alpha.length;i++)if(((const unsigned char*)alpha.bytes)[i]!=255)opaqueOutput=NO;
    check(CGRectEqualToRect(reducedOutput.extent,reducedRect)&&opaqueOutput,@"reduced and translated filter input keeps framing and opaque coverage",failures);
    for(NSString *corruption in @[@"workingTransfer",@"sourceBinding",@"constrainedCrop",@"compactWorkingTransfer",@"width"]){
        NSMutableDictionary *broken=[saved mutableCopy];if([corruption isEqual:@"workingTransfer"])broken[corruption]=@"lensdock-explicit-v7";else if([corruption isEqual:@"sourceBinding"])broken[corruption]=@{};else if([corruption isEqual:@"constrainedCrop"])broken[corruption]=@{@"scale":@.5};else if([corruption isEqual:@"width"])broken[corruption]=@241;else broken[corruption]=@"encoded_sRGB";
        [copied setValue:broken forKey:@"lensProfile"];[copied setValue:opaque forKey:kCIInputImageKey];check(copied.outputImage==opaque,@"unknown/corrupt explicit archive leaves original image",failures);
    }
    // Reject ambiguous formats, malformed frames, unbound/replaced canvases,
    // simultaneous map providers, native correction and invented components.
    NSMutableDictionary *bad=[samplePlan mutableCopy];[bad removeObjectForKey:@"sourceBinding"];
    check(!LensEffectsForCorrectionPlan(bad,envelope,sampleSettings,nil,nil),@"missing source binding rejected",failures);
    bad=[samplePlan mutableCopy];NSMutableDictionary *report=[bad[@"report"] mutableCopy];report[@"geometryProvider"]=@"unknown";bad[@"report"]=report;
    check(!LensEffectsForCorrectionPlan(bad,envelope,sampleSettings,nil,nil),@"unknown provider rejected",failures);
    bad=[samplePlan mutableCopy];NSMutableDictionary *bound=[bad[@"sourceBinding"]mutableCopy];bound[@"width"]=@241;bad[@"sourceBinding"]=bound;
    check(!LensEffectsForCorrectionPlan(bad,envelope,sampleSettings,nil,nil),@"changed bound canvas rejected",failures);
    bad=[samplePlan mutableCopy];bad[@"normalizedGeometryMapsLZFSE"]=@{@"D":NSData.data};
    check(!LensEffectsForCorrectionPlan(bad,envelope,sampleSettings,nil,nil),@"mixed node/map providers rejected",failures);
    bad=[samplePlan mutableCopy];bad[@"geometryResidualMapsLZFSE"]=@{};
    check(!LensEffectsForCorrectionPlan(bad,envelope,sampleSettings,nil,nil),@"legacy residual field rejected even when empty",failures);
    bad=[samplePlan mutableCopy];report=[bad[@"report"]mutableCopy];report[@"geometryMapEncoding"]=@"pixel-displacement-RGf-bottom-up-grid-v3";bad[@"report"]=report;
    check(!LensEffectsForCorrectionPlan(bad,envelope,sampleSettings,nil,nil),@"mixed encoding declarations rejected",failures);
    for(NSUInteger kind=0;kind<3;kind++) {
        bad=[samplePlan mutableCopy];report=[bad[@"report"] mutableCopy];
        if(kind==0)report[@"nativeCorrectionSupport"]=@{@"lensCorrectionSupported":@YES};
        if(kind==1)report[@"geometryHandledByNative"]=@YES;
        if(kind==2)report[@"supplementalVignettingOnly"]=@YES;
        bad[@"report"]=report;check(!LensEffectsForCorrectionPlan(bad,envelope,sampleSettings,nil,nil),@"native priority prevents explicit geometry",failures);
    }
    bad=[samplePlan mutableCopy];bound=[bad[@"sourceBinding"]mutableCopy];NSMutableArray *raw=[bound[@"rawParameters"]mutableCopy];NSMutableDictionary *params=[raw[1]mutableCopy];params[@"lc"]=@YES;raw[1]=params;bound[@"rawParameters"]=raw;bad[@"sourceBinding"]=bound;
    check(!LensEffectsForCorrectionPlan(bad,envelope,sampleSettings,nil,nil),@"native RAW switch prevents duplicate correction",failures);
    NSMutableDictionary *config=[sampleSettings mutableCopy];config[@"vignettingEnabled"]=@YES;
    check(!LensEffectsForCorrectionPlan(samplePlan,envelope,config,nil,nil),@"missing vignette calibration never invents gain",failures);
    config=[sampleSettings mutableCopy];config[@"distortionStrength"]=@"100";
    check(!LensEffectsForCorrectionPlan(samplePlan,envelope,config,nil,nil),@"mistyped strength rejected",failures);
    bad=[samplePlan mutableCopy];report=[bad[@"report"]mutableCopy];NSMutableDictionary *payload=[report[@"explicitGeometry"]mutableCopy],*frame=[payload[@"frame"]mutableCopy];frame[@"orientation"]=@9;payload[@"frame"]=frame;report[@"explicitGeometry"]=payload;bad[@"report"]=report;
    check(!LensEffectsForCorrectionPlan(bad,envelope,sampleSettings,nil,nil),@"invalid archived orientation rejected",failures);
    // Zero table identity is determined by coefficients, regardless of report
    // claims. A missing component never acquires a substitute correction.
    NSDictionary *originalSource;LensSonyExplicitPixelFrame originalFrame;LensSonyReadExplicitGeometry(samplePlan[@"report"][@"explicitGeometry"],&originalSource,&originalFrame);
    NSMutableDictionary *zeroSource=[originalSource mutableCopy],*zeroTables=[originalSource[@"tables"]mutableCopy];NSMutableArray *zeros=[NSMutableArray new];for(NSUInteger i=0;i<11;i++)[zeros addObject:@0];
    zeroTables[@"Distortion"]=@{@"nodeCount":@11,@"values":zeros};zeroTables[@"ChromaticAberration"]=@{@"nodeCount":@11,@"red":zeros,@"blue":zeros};zeroSource[@"tables"]=zeroTables;
    bad=[samplePlan mutableCopy];report=[bad[@"report"]mutableCopy];report[@"explicitGeometry"]=LensSonyExplicitGeometryPayload(zeroSource,originalFrame);report[@"distortionCorrectionNeeded"]=@YES;report[@"tcaCorrectionNeeded"]=@YES;bad[@"report"]=report;
    check(!LensGeometryCalibrationNeeded(report,@"distortion")&&!LensGeometryCalibrationNeeded(report,@"tca")&&!LensEffectsForCorrectionPlan(bad,envelope,sampleSettings,nil,nil),@"zero coefficients cannot create geometry",failures);
    zeroSource=[originalSource mutableCopy];zeroTables=[originalSource[@"tables"]mutableCopy];[zeroTables removeObjectForKey:@"ChromaticAberration"];zeroSource[@"tables"]=zeroTables;
    bad=[samplePlan mutableCopy];report=[bad[@"report"]mutableCopy];report[@"explicitGeometry"]=LensSonyExplicitGeometryPayload(zeroSource,originalFrame);report[@"tcaProfileAvailable"]=@NO;bad[@"report"]=report;
    check(!LensEffectsForCorrectionPlan(bad,envelope,sampleSettings,nil,nil)&&LensEffectsForCorrectionPlan(bad,envelope,settings(1,0,YES),nil,nil),@"missing TCA is rejected independently of available distortion",failures);
    NSMutableArray *negative=[NSMutableArray new];for(NSUInteger i=0;i<11;i++)[negative addObject:@-10000];zeroSource=[originalSource mutableCopy];zeroTables=[originalSource[@"tables"]mutableCopy];zeroTables[@"Distortion"]=@{@"nodeCount":@11,@"values":negative};zeroSource[@"tables"]=zeroTables;
    bad=[samplePlan mutableCopy];report=[bad[@"report"]mutableCopy];report[@"explicitGeometry"]=LensSonyExplicitGeometryPayload(zeroSource,originalFrame);bad[@"report"]=report;
    check(LensEffectsForCorrectionPlan(bad,envelope,settings(1,0,NO),nil,nil)&&!LensEffectsForCorrectionPlan(bad,envelope,settings(2,0,NO),nil,nil),@"strength producing nonpositive geometry rejected even without crop",failures);
    // The existing native color effect and effects context survive replacement.
    NSData *existing=[NSData dataWithContentsOfFile:@"Tests/Fixtures/color-fill-effects.json"];
    id composed=LensEffectsForCorrectionPlan(samplePlan,envelope,sampleSettings,existing,nil);
    id replaced=LensEffectsForCorrectionPlan(samplePlan,envelope,settings(.8,1.2,YES),LensEffectsJSON(composed,nil),nil);
    NSArray *old=[NSJSONSerialization JSONObjectWithData:existing options:0 error:nil],*final=[NSJSONSerialization JSONObjectWithData:LensEffectsJSON(replaced,nil) options:0 error:nil];
    check(final&&[final[1][@"ctx"]isEqual:old[1][@"ctx"]]&&[[final[1][@"w"]subarrayWithRange:NSMakeRange(1,[final[1][@"w"]count]-1)]isEqual:old[1][@"w"]],@"replacement retains other native effects and context",failures);
    check(!LensEffectsEquivalent(sampleJSON,LensEffectsJSON(LensEffectsForCorrectionPlan(samplePlan,envelope,settings(.8,1.2,YES),nil,nil),nil)),@"editable node strengths affect semantic effect comparison",failures);
    NSDictionary *result=@{@"scope":@"Explicit hypothetical frames and pinned source tables through native PTFoundation effect serialization/rendering. No automatic manufacturer-frame selection, actual PXD save/reopen, photo optics or added lens coverage.",@"renders":renders,@"renderCount":@(renders.count),@"maximumRGBAError":@(worst),@"fractionalPreviewChecks":@(previewChecks),@"reducedTranslatedInputOpaque":@(opaqueOutput),@"preservesExistingEffects":@YES,@"restoredPlanEditable":@(restored!=nil),@"productAutomaticRouteEnabled":@NO,@"manufacturerFrameProven":@NO,@"failures":failures,
        @"sourceSHA256":@{@"Sources/Native/LensSonyGeometryArchive.h":digest([NSData dataWithContentsOfFile:@"Sources/Native/LensSonyGeometryArchive.h"]),@"Sources/Native/LensVignettingFilter.m":digest([NSData dataWithContentsOfFile:@"Sources/Native/LensVignettingFilter.m"]),@"Sources/Native/LensCorrectionSettings.m":digest([NSData dataWithContentsOfFile:@"Sources/Native/LensCorrectionSettings.m"]),@"Tests/verify-sony-geometry-effect.m":digest([NSData dataWithContentsOfFile:@"Tests/verify-sony-geometry-effect.m"])}};
    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/sony-geometry-effect-verification.json" atomically:YES];
    printf("Sony explicit archived effect: %lu renders, %lu failures.\n",(unsigned long)renders.count,(unsigned long)failures.count);for(NSString *message in failures)fprintf(stderr,"%s\n",message.UTF8String);return failures.count?1:0;
}}
