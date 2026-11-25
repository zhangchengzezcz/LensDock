#import "LensNativeProfileEngine.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreImage/CoreImage.h>
#import <math.h>

static NSDictionary *plan(NSString *make, NSString *camera, NSString *lens,
                         double focal, double aperture, double distance, NSURL *db) {
    NSDictionary *metadata = @{@"Make": make, @"Model": camera, @"LensModel": lens,
                               @"FocalLength": @(focal), @"FNumber": @(aperture),
                               @"FocusDistance": @(distance)};
    NSURL *lib = [NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"];
    return LensNativeProfilePlan(metadata, db, lib, 96, 64, nil);
}

static BOOL near(double observed, double expected) {
    return isfinite(observed) && fabs(observed - expected) < 1e-6;
}

static NSString *sha256(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
    if (!data.length || data.length > UINT32_MAX) return nil;
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *digest = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof(hash); i++) [digest appendFormat:@"%02x", hash[i]];
    return digest;
}

// Optional independent CC0 camera RAW from raw.pixls.us, entry 1435.
static BOOL checkPublicGFX(NSURL *raw, NSURL *db, NSURL *oldDB) {
    NSString *digest = @"a7124d13910e0241a6b035154bc1fcdb7be4439371d043b1e1950a0251feb51e";
    if (![sha256(raw) isEqual:digest]) return NO;
    NSURL *tool = [NSURL fileURLWithPath:@"Resources/LensBridge/exiftool/exiftool"];
    NSURL *lib = [NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"];
    NSDictionary *metadata = LensReadRawMetadata(raw, tool, nil);
    NSDictionary *native = metadata[@"nativeCorrectionSupport"];
    if (![metadata[@"Model"] isEqual:@"GFX 50S"] || ![metadata[@"LensModel"] isEqual:@"GF63mmF2.8 R WR"] ||
        !near([metadata[@"FocalLength"] doubleValue], 63) || !near([metadata[@"FNumber"] doubleValue], 14) ||
        ![native[@"probeSucceeded"] boolValue]) return NO;

    BOOL official = [native[@"lensCorrectionSupported"] boolValue];
    NSDictionary *newPlan = LensNativeProfilePlan(metadata, db, lib, 96, 72, nil);
    NSDictionary *prior = LensNativeProfilePlan(metadata, oldDB, lib, 96, 72, nil);
    NSDictionary *report = newPlan[@"report"], *previous = prior[@"report"];
    if (![report[@"matchedLensIdentityNames"] containsObject:@"GF63mmF2.8 R WR"] ||
        ![report[@"vignettingProfileAvailable"] boolValue] || [previous[@"vignettingProfileAvailable"] boolValue] ||
        [report[@"supplementalVignettingOnly"] boolValue] != official ||
        [report[@"distortionProfileAvailable"] boolValue] == official ||
        [report[@"tcaProfileAvailable"] boolValue] == official) return NO;

    CIRAWFilter *decoder = [CIRAWFilter filterWithImageURL:raw];
    decoder.scaleFactor = 0.125f;
    CIImage *image = decoder.outputImage;
    if (!image || CGRectIsEmpty(image.extent) || CGRectIsInfinite(image.extent)) return NO;
    CGRect tile = CGRectMake(CGRectGetMidX(image.extent) - 16, CGRectGetMidY(image.extent) - 16, 32, 32);
    CGImageRef rendered = [[CIContext contextWithOptions:nil] createCGImage:image fromRect:tile];
    if (!rendered) return NO;
    CGImageRelease(rendered);
    if (![sha256(raw) isEqual:digest]) return NO;

    BOOL wasSupported = [previous[@"distortionProfileAvailable"] boolValue];
    printf("Public GFX 50S RAW: GF63mm, 63 mm f/14, rendered Core Image tile, native=%s, prior catalogue distortion=%s, new catalogue vignetting=yes, unchanged SHA256.\n",
           official ? "yes" : "no", wasSupported ? "yes" : "no");
    return YES;
}

static BOOL checkSavedOMChoices(NSURL *db) {
    NSString *camera = @"camera-v1-d9f874005abb9eca9ac86dba9718df479793c15e31788d1b61de4e9a71269160";
    NSArray *choices = @[
        @[@"OM 12-100mm F4.0", @"M.Zuiko Digital ED 12-100mm F4.0 IS PRO", @12,
          @"lens-v1-32d18ef87e5c0db3b25bf5382ed69b05bbd43efd72cb3abf44f08610c14d2ce6"],
        @[@"OM 20mm F1.4", @"M.Zuiko Digital ED 20mm F1.4 PRO", @20,
          @"lens-v1-ae5beda09078f1bd0fca2e08eb28b2ee9a5c033e997cdd371a7b90d3a0310dd3"],
        @[@"OM 17mm F1.8 II", @"M.Zuiko Digital 17mm F1.8 II", @17,
          @"lens-v1-b3c77421b82576b104cafd09dbb90ef4fb593462a928ac86398d56e62aaeac7d"],
        @[@"OM 12-45mm F4.0", @"M.Zuiko Digital ED 12-45mm F4.0 PRO", @12,
          @"lens-v1-df2d7b712ee8da525a96d85a00021fae54d94f92e2591ada1d87393cd9e5eafe"],
    ];
    NSURL *lib = [NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"];
    for (NSArray *choice in choices) {
        NSDictionary *saved = @{@"cameraID": camera, @"lensID": choice[3]};
        NSDictionary *metadata = @{@"Make": @"OM Digital Solutions", @"Model": @"OM-1", @"LensModel": choice[0],
                                   @"FocalLength": choice[2], @"FNumber": @4, @"LensDockProfileSelection": saved};
        NSDictionary *manual = LensNativeProfilePlan(metadata, db, lib, 96, 72, nil)[@"report"];
        NSDictionary *alternate = plan(@"OM Digital Solutions", @"OM-1", choice[1], [choice[2] doubleValue], 4, 1000, db)[@"report"];
        if (![manual[@"manualProfileSelection"] isEqual:saved] ||
            ![manual[@"matchedLensProfileID"] isEqual:choice[3]] || ![alternate[@"matchedLensProfileID"] isEqual:choice[3]] ||
            ![alternate[@"matchedLensIdentityNames"] containsObject:choice[1]] ||
            ![manual[@"interpolatedCalibration"] isEqual:alternate[@"interpolatedCalibration"]]) return NO;
    }
    return YES;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSURL *db = [NSURL fileURLWithPath:argc > 1 ? @(argv[1]) : @"Resources/LensBridge/db"];
        // Fixed witnesses copied from the version 1 upstream export, independent
        // of the installed XML. Compare the actual terms as well as identity.
        NSArray *cases = @[
            @[@"Fujifilm", @"GFX 50S", @"GF63mmF2.8 R WR", @63, @2.8, @0.5, @"Fujifilm G", @0.79, @3, @0.00540535, @YES, @YES],
            @[@"Nikon Corporation", @"Nikon Z 6", @"Nikkor Z 24mm f/1.8 S", @24, @1.8, @10, @"Nikon Z", @1, @3, @0.0047993, @NO, @NO],
            @[@"Nikon Corporation", @"Nikon Z 6", @"NIKKOR Z 24-70mm f/2.8 S II", @24, @2.8, @10, @"Nikon Z", @1, @3, @0.015, @NO, @YES],
            @[@"OM Digital Solutions", @"OM-1", @"OM 40-150mm F4.0-5.6 R", @40, @4, @10, @"Micro 4/3 System", @2, @1, @(-0.01246), @NO, @NO],
            @[@"OM Digital Solutions", @"OM-1", @"OM 75-300mm F4.8-6.7 II", @75, @4.8, @10, @"Micro 4/3 System", @2, @1, @0.0019, @YES, @YES],
            @[@"OM Digital Solutions", @"OM-1", @"OM 14-42mm F3.5-5.6 EZ", @14, @3.5, @10, @"Micro 4/3 System", @2, @3, @0.01468, @NO, @NO],
            @[@"Nikon Corporation", @"Nikon D750", @"Nikon AF VR Zoom-Nikkor 80-400mm f/4.5-5.6D ED", @80, @4.5, @10, @"Nikon F AF", @1, @3, @(-0.0226566), @NO, @NO],
            @[@"Ricoh Imaging Company, Ltd.", @"Pentax K-3", @"Super-Multi-Coated Takumar 28mm f/3.5", @28, @3.5, @10, @"Pentax KAF2", @1.526, @3, @0.0014309, @YES, @NO],
        ];
        for (NSArray *sample in cases) {
            NSDictionary *r = plan(sample[0], sample[1], sample[2], [sample[3] doubleValue],
                                   [sample[4] doubleValue], [sample[5] doubleValue], db)[@"report"];
            NSDictionary *calibration = r[@"interpolatedCalibration"];
            NSString *source = r[@"matchingIdentitySource"];
            BOOL exactName = NO;
            for (NSString *name in r[@"matchedLensIdentityNames"])
                if ([name caseInsensitiveCompare:sample[2]] == NSOrderedSame) exactName = YES;
            if (!exactName || ![source isEqual:@"LensModel"] || ![r[@"cameraMount"] isEqual:sample[6]] ||
                !near([calibration[@"lensCropFactor"] doubleValue], [sample[7] doubleValue]) ||
                ![calibration[@"distortion"][@"model"] isEqual:sample[8]] ||
                !near([calibration[@"distortion"][@"terms"][0] doubleValue], [sample[9] doubleValue]) ||
                ![r[@"tcaProfileAvailable"] isEqual:sample[10]] || ![r[@"vignettingProfileAvailable"] isEqual:sample[11]]) {
                fprintf(stderr, "Incorrect catalogue plan for %s\n", [sample[2] UTF8String]);
                return 1;
            }
        }

        NSString *shared = @"Nikkor AF 80-400mm f/4.5-5.6D ED VR";
        NSDictionary *ff = plan(@"Nikon Corporation", @"Nikon D750", shared, 80, 8, 10, db)[@"report"];
        NSDictionary *dx = plan(@"Nikon Corporation", @"Nikon D70", shared, 80, 8, 10, db)[@"report"];
        if (!near([ff[@"interpolatedCalibration"][@"lensCropFactor"] doubleValue], 1) ||
            !near([dx[@"interpolatedCalibration"][@"lensCropFactor"] doubleValue], 1.528) ||
            [ff[@"matchedLensProfileID"] isEqual:dx[@"matchedLensProfileID"]]) return 2;

        NSDictionary *first = plan(@"Nikon Corporation", @"Nikon Z 6", @"NIKKOR Z 24-70mm f/2.8 S", 24, 2.8, 10, db)[@"report"];
        NSDictionary *invalid = plan(@"Nikon Corporation", @"Nikon Z 6", @"NIKKOR Z 24-70mm f/2.8 S III", 24, 2.8, 10, db);
        if (invalid || ![first[@"matchedLensIdentityNames"] containsObject:@"Nikkor Z 24-70mm f/2.8 S"] ||
            !near([first[@"interpolatedCalibration"][@"distortion"][@"terms"][0] doubleValue], 0.03963)) return 3;

        puts("Eight updated Lensfun routes passed; Nikon F sensor variants and Nikon Z generation boundaries stayed distinct.");
        if (!checkSavedOMChoices(db)) return 5;
        puts("Four prior manual IDs still select their original optical data, and all four new names match automatically.");
        if (argc == 4 && !checkPublicGFX([NSURL fileURLWithPath:@(argv[2])], db, [NSURL fileURLWithPath:@(argv[3])])) return 4;
    }
    return 0;
}
