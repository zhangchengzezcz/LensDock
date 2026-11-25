#import "LensNativeProfileEngine.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreImage/CoreImage.h>

static NSDictionary *makePlan(NSDictionary *metadata, BOOL includeGeometry) {
    NSURL *database = [NSURL fileURLWithPath:@"Resources/LensBridge/db"];
    NSURL *library = [NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"];
    if (includeGeometry) return LensNativeProfilePlanIncludingGeometry(metadata, database, library, 96, 64, nil);
    return LensNativeProfilePlan(metadata, database, library, 96, 64, nil);
}

static NSDictionary *fixedLensMetadata(NSString *model, double focal, NSInteger equivalent, NSDictionary *makerNote) {
    NSString *make = @"RICOH IMAGING COMPANY, LTD.";
    NSMutableDictionary *tags = [@{@"File:FileType": @"DNG", @"IFD0:Make": make, @"IFD0:Model": model,
                                  @"ExifIFD:FocalLengthIn35mmFormat": @(equivalent)} mutableCopy];
    [tags addEntriesFromDictionary:makerNote];
    return @{@"Make": make, @"Model": model, @"FocalLength": @(focal), @"FNumber": @4, @"ricohLensMetadata": tags};
}

static BOOL usedFixedLens(NSDictionary *plan, NSString *mount) {
    NSDictionary *report = plan[@"report"];
    return [report[@"matchingIdentitySource"] isEqual:@"ricohLensMetadata"] &&
           [report[@"matchingIdentityMethod"] isEqual:@"fixed-built-in-camera-lens"] &&
           [report[@"cameraMount"] isEqual:mount];
}

static BOOL verifyGuards(void) {
    NSDictionary *gr = fixedLensMetadata(@"GR", 18.3, 28, @{@"Ricoh:WideAdapter": @0, @"Ricoh:CropMode": @0});
    NSDictionary *grx = fixedLensMetadata(@"RICOH GR IIIx", 26, 40, @{@"Pentax:LensType": @"31 4"});
    NSDictionary *gr4 = fixedLensMetadata(@"RICOH GR IV", 18.3, 28, @{@"Pentax:LensType": @"31 8"});
    if (!usedFixedLens(makePlan(gr, NO), @"ricohGR") || !usedFixedLens(makePlan(grx, NO), @"ricohGRIIIx") ||
        !usedFixedLens(makePlan(gr4, NO), @"ricohGRIV")) return NO;

    NSArray *invalidTags = @[
        @[gr, @"Ricoh:WideAdapter", @2], @[gr, @"Ricoh:WideAdapter", NSNull.null],
        @[gr, @"Ricoh:CropMode", @1], @[gr, @"Ricoh:CropMode", NSNull.null],
        @[grx, @"Pentax:LensType", @"31 5"], @[grx, @"Pentax:LensType", NSNull.null],
        @[grx, @"ExifIFD:FocalLengthIn35mmFormat", @50], @[grx, @"ExifIFD:FocalLengthIn35mmFormat", NSNull.null],
        @[grx, @"File:FileType", @"JPEG"], @[grx, @"IFD0:Model", @"RICOH GR III"],
        @[grx, @"IFD0:Make", @"Other maker"], @[gr4, @"Pentax:LensType", @"31 1"],
    ];
    for (NSArray *change in invalidTags) {
        NSMutableDictionary *metadata = [change[0] mutableCopy];
        NSMutableDictionary *tags = [metadata[@"ricohLensMetadata"] mutableCopy];
        tags[change[1]] = change[2] == NSNull.null ? nil : change[2];
        metadata[@"ricohLensMetadata"] = tags;
        if (makePlan(metadata, NO)) return NO;
        if ([metadata[@"Model"] isEqual:@"RICOH GR IIIx"]) {
            metadata[@"LensModel"] = @"Ricoh GR IIIx & compatibles";
            if (makePlan(metadata, NO)) return NO;
        }
    }
    NSMutableDictionary *conflict = [grx mutableCopy];
    conflict[@"LensIDName"] = @"26.1mm F2.8 GT-2 TC";
    if (makePlan(conflict, NO)) return NO;
    conflict[@"LensIDName"] = @"26.1mm F2.8";
    conflict[@"LensModel"] = @"GR LENS 26.1mm F2.8";
    return usedFixedLens(makePlan(conflict, NO), @"ricohGRIIIx");
}

static NSString *sha256(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
    if (!data.length || data.length > UINT32_MAX) return nil;
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    NSMutableString *digest = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) [digest appendFormat:@"%02x", bytes[i]];
    return digest;
}

static BOOL verifyCompleteRAW(NSURL *raw, NSString *digest, NSString *mount, double focal, double aperture) {
    if (![sha256(raw) isEqual:digest]) return NO;
    NSURL *exifTool = [NSURL fileURLWithPath:@"Resources/LensBridge/exiftool/exiftool"];
    NSDictionary *metadata = LensReadRawMetadata(raw, exifTool, nil);
    NSDictionary *native = metadata[@"nativeCorrectionSupport"];
    if (![native[@"probeSucceeded"] boolValue] || fabs([metadata[@"FocalLength"] doubleValue] - focal) > 0.001 ||
        fabs([metadata[@"FNumber"] doubleValue] - aperture) > 0.001) return NO;
    NSDictionary *plan = makePlan(metadata, YES);
    if (!usedFixedLens(plan, mount)) return NO;
    NSMutableDictionary *withoutMakerNote = [metadata mutableCopy];
    [withoutMakerNote removeObjectForKey:@"ricohLensMetadata"];
    if ([makePlan(withoutMakerNote, NO)[@"report"][@"matchedLensProfileID"] length]) return NO;
    BOOL handledByNative = [native[@"lensCorrectionSupported"] boolValue];
    if (handledByNative && (plan[@"normalizedGeometryMapsLZFSE"] ||
        ![plan[@"report"][@"geometryHandledByNative"] boolValue])) return NO;
    if (!handledByNative && ![plan[@"report"][@"distortionProfileAvailable"] boolValue]) return NO;

    CIRAWFilter *decoder = [CIRAWFilter filterWithImageURL:raw];
    decoder.scaleFactor = 0.125f;
    CIImage *image = decoder.outputImage;
    if (!image || CGRectIsEmpty(image.extent) || CGRectIsInfinite(image.extent)) return NO;
    CGRect tile = CGRectMake(CGRectGetMidX(image.extent) - 16, CGRectGetMidY(image.extent) - 16, 32, 32);
    CGImageRef rendered = [[CIContext contextWithOptions:nil] createCGImage:image fromRect:tile];
    if (!rendered) return NO;
    CGImageRelease(rendered);
    if (![sha256(raw) isEqual:digest]) return NO;
    printf("%s complete RAW: %.3g mm f/%.3g, auto-matched, native support=%s, Core Image tile rendered, SHA256 unchanged.\n",
           mount.UTF8String, focal, aperture, handledByNative ? "yes" : "no");
    return YES;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (!verifyGuards()) return 1;
        puts("Ricoh GR, GR IIIx and GR IV fixed lens guards passed, including converter, crop and identity rejection.");
        // Optional complete CC0 RAWs from raw.pixls.us, entries 996 and 5818.
        NSString *gr = argc > 1 ? @(argv[1]) : @"Tests/PrivateRAW/Ricoh-GR.dng";
        NSString *grx = argc > 2 ? @(argv[2]) : @"Tests/PrivateRAW/Ricoh-GR-IIIx.dng";
        if (![gr isEqual:@"-"] && (argc > 1 || [NSFileManager.defaultManager fileExistsAtPath:gr]) &&
            !verifyCompleteRAW([NSURL fileURLWithPath:gr],
            @"7ceec1ea31c56b6e0414202504581b915f17818ffe018b4c8bba1393332c405e", @"ricohGR", 18.3, 5.6)) return 2;
        if (![grx isEqual:@"-"] && (argc > 2 || [NSFileManager.defaultManager fileExistsAtPath:grx]) &&
            !verifyCompleteRAW([NSURL fileURLWithPath:grx],
            @"1e318af31be4baa9949f0ed4af5cfe8ffb2c180e2c12926cd75ac1d029bb0fae", @"ricohGRIIIx", 26, 4)) return 3;
    }
}
