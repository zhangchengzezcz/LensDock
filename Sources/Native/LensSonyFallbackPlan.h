#import "LensSonyGeometryArchive.h"
#import "LensCalibrationEvidence.h"

// A declared normalized-image interpretation, not a recovered manufacturer
// coordinate contract. Used only after native and catalogue matching fail.
static inline double LensSonyCaptureValue(id value){return [value isKindOfClass:NSNumber.class]&&isfinite([value doubleValue])&&[value doubleValue]>0?[value doubleValue]:0;}
static inline NSDictionary *LensSonyDecodedFrameFallbackPlan(NSDictionary *metadata,NSUInteger w,NSUInteger h){
    NSDictionary *source=metadata[@"embeddedLensCorrectionSource"],*native=metadata[@"nativeCorrectionSupport"];
    if(![source isKindOfClass:NSDictionary.class]||![native isKindOfClass:NSDictionary.class]||![native[@"probeSucceeded"]boolValue]||
       !LensSonyArchiveFlag(native[@"lensCorrectionSupported"])||[native[@"lensCorrectionSupported"]boolValue]||
       !LensSonyArchiveFlag(native[@"lensCorrectionEnabledByDefault"])||[native[@"lensCorrectionEnabledByDefault"]boolValue]||
       ![metadata[@"Model"]isEqual:source[@"cameraModel"]]||metadata[@"LensDockProfileSelection"]||w<2||h<2||w>16000||h>16000||w*h>120000000)return nil;
    NSArray *full=source[@"recordedFullImageSize"],*decoded=native[@"nativePixelSize"];
    if(!LensSonyArchiveArray(full,2)||!LensSonyArchiveArray(decoded,2)||![full isEqual:decoded]||!LensSonyDimension(full[0])||!LensSonyDimension(full[1]))return nil;
    double fw=[full[0]doubleValue],fh=[full[1]doubleValue],sw=[source[@"storageWidth"]doubleValue],sh=[source[@"storageHeight"]doubleValue];
    // Reject large capture crops/reduced modes instead of assuming a sensor
    // table can be normalized to an arbitrary smaller recorded rectangle.
    if(fw<=0||fh<=0||sw<fw||sh<fh||fw/sw<.98||fh/sh<.98)return nil;
    id orient=metadata[@"Orientation"]?:@1,decoderOrientation=native[@"decoderOrientation"];
    if(!LensSonyArchiveNumber(orient)||!LensSonyArchiveNumber(decoderOrientation)||[orient doubleValue]!=[decoderOrientation doubleValue]||
       floor([orient doubleValue])!=[orient doubleValue]||[orient doubleValue]<1||[orient doubleValue]>8)return nil;
    NSUInteger orientation=[orient unsignedIntegerValue];double ow=orientation>=5?h:w,oh=orientation>=5?w:h;
    if(fabs((ow/oh)/(fw/fh)-1)>MAX(.001,1/MIN(ow,oh)))return nil;
    LensSonyExplicitPixelFrame frame={CGSizeMake(fw,fh),CGRectMake(0,0,fw,fh),CGSizeMake(w,h),orientation};
    NSDictionary *payload=LensSonyExplicitGeometryPayload(source,frame);if(!payload)return nil;
    NSDictionary *tables=source[@"tables"];BOOL hasD=tables[@"Distortion"]!=nil,hasT=tables[@"ChromaticAberration"]!=nil;
    NSMutableDictionary *report=[@{@"camera":source[@"cameraModel"],@"lens":[metadata[@"LensModel"]isKindOfClass:NSString.class]&&[metadata[@"LensModel"]length]?metadata[@"LensModel"]:@"相机内嵌镜头标定",
        @"width":@(w),@"height":@(h),@"workingTransfer":@"linear",@"geometryProvider":@"sony-explicit-frame-v1",@"explicitGeometry":payload,
        @"frameConvention":@"recorded-full-image-aligned-decoder-v1",@"manufacturerFrameProven":@NO,@"matchingIdentityMethod":@"raw-embedded-source-owner",
        @"matchingIdentitySource":@"embeddedLensCorrectionSource",@"databaseFiles":@0,@"nativeCorrectionSupport":native,@"geometryHandledByNative":@NO,@"supplementalVignettingOnly":@NO,
        @"focal_mm":@(LensSonyCaptureValue(metadata[@"FocalLength"])),@"aperture":@(LensSonyCaptureValue(metadata[@"FNumber"])),
        @"focus_distance_m":@(LensSonyCaptureValue(metadata[@"FocusDistance"])?:1000),@"distance_source":LensSonyCaptureValue(metadata[@"FocusDistance"])?@"metadata":@"infinity_fallback",
        @"distortionProfileAvailable":@(hasD),@"tcaProfileAvailable":@(hasT),@"vignettingProfileAvailable":@NO,@"vignettingCorrectionNeeded":@NO,
        @"geometryCalibrationInferredFromContent":@NO,@"geometryAmountAssessment":@"embedded-profile-sampled-65x65"}mutableCopy];
    double peaks[2]={0,0};
    for(NSUInteger pass=0;pass<2;pass++){
        if(pass?!hasT:!hasD)continue;LensSonyGeometryTransform transform;
        if(!LensSonyPrepareGeometry(source,frame,pass?0:1,pass?1:0,&transform))return nil;
        for(NSUInteger y=0;y<=64;y++)for(NSUInteger x=0;x<=64;x++){
            CGPoint p=CGPointMake(.5+x*(w-1.)/64,.5+y*(h-1.)/64),q[3];
            for(NSUInteger c=0;c<3;c++)if(!LensSonyMapGeometryPoint(&transform,p,c,&q[c]))return nil;
            double amount=pass?fmax(hypot(q[0].x-q[1].x,q[0].y-q[1].y),hypot(q[2].x-q[1].x,q[2].y-q[1].y)):hypot(q[1].x-p.x,q[1].y-p.y);
            if(!isfinite(amount))return nil;peaks[pass]=fmax(peaks[pass],amount);
        }
    }
    report[@"distortionCorrectionNeeded"]=@(peaks[0]>.001);report[@"tcaCorrectionNeeded"]=@(peaks[1]>.001);
    report[@"distortionPeakShiftPixels"]=@(peaks[0]);report[@"distortionPeakShiftPercent"]=@(100*peaks[0]/MIN(w,h));report[@"tcaPeakSeparationPixels"]=@(peaks[1]);
    LensSonyGeometryTransform combined;if(!LensSonyPrepareGeometry(source,frame,hasD?1:0,hasT?1:0,&combined))return nil;
    NSDictionary *recorded=metadata[@"recordedLensCorrectionSettings"];
    // Matching dimensions qualify a candidate, not manufacturer coordinates
    // or proof that the decoder leaves pixels untouched. Require an explicit
    // user choice; the camera's Auto/Off flags cannot enable this candidate.
    report[@"automaticGeometryEnabled"]=@{@"distortion":@NO,@"tca":@NO};
    if(recorded)report[@"recordedLensCorrectionSettings"]=recorded;
    return @{@"report":report,@"metadata":metadata,@"normalizedGeometryMapsLZFSE":@{}};
}
