#import "LensConstrainedCrop.h"
#import "LensCalibrationEvidence.h"
#import <math.h>

static NSDictionary *cropError(NSError **error) {
    if (error) *error = [NSError errorWithDomain:@"LensDockCrop" code:1 userInfo:@{
        NSLocalizedDescriptionKey:@"无法确认安全裁切范围，未应用。可关闭“约束边缘”保留完整视角。"
    }];
    return nil;
}

NSDictionary *LensConstrainedCrop(NSDictionary *plan, NSDictionary *settings, NSError **error) {
    NSDictionary *report = plan[@"report"];
    NSUInteger w = [report[@"width"] unsignedIntegerValue], h = [report[@"height"] unsignedIntegerValue];
    if (w < 2 || h < 2 || w > 16000 || h > 16000) return cropError(error);
    double ds = [settings[@"distortionEnabled"] boolValue] ? [settings[@"distortionStrength"] doubleValue]/100 : 0;
    double ts = [settings[@"tcaEnabled"] boolValue] ? [settings[@"tcaStrength"] doubleValue]/100 : 0;
    if ([report[@"supplementalVignettingOnly"] boolValue]) ds = ts = 0;
    if (!LensGeometryCalibrationNeeded(report,@"distortion")) ds = 0;
    if (!LensGeometryCalibrationNeeded(report,@"tca")) ts = 0;
    if (!isfinite(ds) || !isfinite(ts) || ds < 0 || ts < 0 || ds > 2 || ts > 2) return cropError(error);
    if ((!ds && !ts) || ![settings[@"constrainCropEnabled"] boolValue])
        return @{@"version":@1, @"scale":@1, @"maximumDisplacementPixels":@[@0,@0]};

    NSString *encoding = report[@"geometryMapEncoding"];
    BOOL residual = [encoding isEqual:@"pixel-displacement-residual-RG8-bottom-up-grid-v4"];
    BOOL offsets = residual || [encoding isEqual:@"pixel-displacement-RGf-bottom-up-grid-v3"];
    if (!offsets && encoding && ![encoding isEqual:@"normalized-source-RGf-bottom-up-v1"])
        return cropError(error);
    NSUInteger mw = [report[@"geometryMapWidth"] unsignedIntegerValue] ?: w;
    NSUInteger mh = [report[@"geometryMapHeight"] unsignedIntegerValue] ?: h;
    if (mw < 2 || mh < 2 || mw > 16000 || mh > 16000) return cropError(error);
    double step = residual ? [report[@"geometryResidualStepPixels"] doubleValue] : 0;
    if (residual && (!isfinite(step) || step <= 0 || step > 1)) return cropError(error);

    NSArray *keys = @[@"D",@"T0",@"T1",@"T2",@"C0",@"C1",@"C2"];
    double low[7][2] = {{0}}, high[7][2] = {{0}};
    for (NSUInteger plane = 0; plane < keys.count; plane++) {
        double weight = plane == 0 ? ds*(1-ts) : plane < 4 ? ts*(1-ds) : ds*ts;
        if (weight == 0) continue;
        @autoreleasepool {
            NSData *data = [plan[@"normalizedGeometryMapsLZFSE"][keys[plane]]
                decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];
            if (data.length != mw*mh*8) return cropError(error);
            const float *values = data.bytes;
            low[plane][0] = low[plane][1] = INFINITY;
            high[plane][0] = high[plane][1] = -INFINITY;
            for (NSUInteger y = 0; y < mh; y++) for (NSUInteger x = 0; x < mw; x++) {
                for (int axis = 0; axis < 2; axis++) {
                    double value = values[(y*mw+x)*2+axis];
                    if (!offsets) value = value*(axis ? h : w) -
                        ((double)(axis ? y : x)*(axis ? h-1 : w-1)/(axis ? mh-1 : mw-1)+.5);
                    if (!isfinite(value)) return cropError(error);
                    low[plane][axis] = fmin(low[plane][axis],value);
                    high[plane][axis] = fmax(high[plane][axis],value);
                }
            }
            if (residual) {
                NSData *bytes = [plan[@"geometryResidualMapsLZFSE"][keys[plane]]
                    decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];
                if (bytes.length != w*h*2) return cropError(error);
                const unsigned char *r = bytes.bytes;
                unsigned char minimum[2] = {255,255}, maximum[2] = {0,0};
                for (NSUInteger i = 0; i < w*h; i++) for (int axis = 0; axis < 2; axis++) {
                    minimum[axis] = MIN(minimum[axis],r[i*2+axis]);
                    maximum[axis] = MAX(maximum[axis],r[i*2+axis]);
                }
                for (int axis = 0; axis < 2; axis++) {
                    low[plane][axis] += ((int)minimum[axis]-128)*step;
                    high[plane][axis] += ((int)maximum[axis]-128)*step;
                }
            }
        }
    }
    double maximum[2] = {0,0};
    // Bilinear samples stay within their node extrema. Interval arithmetic also
    // covers negative weights at strengths above 100%, and residual extrema
    // between grid knots. It does not assume a monotonic lens or sample corners.
    for (int channel = 0; channel < 3; channel++) for (int axis = 0; axis < 2; axis++) {
        NSUInteger planes[3] = {0,1+channel,4+channel};
        double weights[3] = {ds*(1-ts),ts*(1-ds),ds*ts}, lower = 0, upper = 0;
        for (int k = 0; k < 3; k++) {
            double a = weights[k]*low[planes[k]][axis], b = weights[k]*high[planes[k]][axis];
            lower += fmin(a,b); upper += fmax(a,b);
        }
        maximum[axis] = fmax(maximum[axis],fmax(fabs(lower),fabs(upper)));
    }
    double scale = 1;
    if (fmax(maximum[0],maximum[1]) > 1e-6) {
        // Two source pixels cover pixel-centre constraints, interpolation at
        // the cropped boundary, and float rounding. No image pixels are filled.
        scale = fmin(1-2*(maximum[0]+2)/w,1-2*(maximum[1]+2)/h);
        if (!isfinite(scale) || scale <= 0) return cropError(error);
    }
    return @{@"version":@1, @"scale":@(scale),
        @"maximumDisplacementPixels":@[@(maximum[0]),@(maximum[1])],
        @"safetyMarginPixels":@2,
        @"method":@"conservative-all-field-extrema-centred-uniform-scale-v1"};
}
