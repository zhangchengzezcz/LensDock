#import "LensNativeProfileEngine.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreImage/CoreImage.h>

static NSURL *database(void) { return [NSURL fileURLWithPath:@"Resources/LensBridge/db"]; }
static NSURL *library(void) { return [NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"]; }
static NSDictionary *report(NSDictionary *metadata) {
    return LensNativeProfilePlan(metadata, database(), library(), 96, 64, nil)[@"report"];
}
static BOOL sameCalibration(NSDictionary *first, NSDictionary *second) {
    return [first[@"matchedLensProfileID"] isEqual:second[@"matchedLensProfileID"]] &&
           [first[@"interpolatedCalibration"] isEqual:second[@"interpolatedCalibration"]];
}

static BOOL verifyNames(void) {
    NSArray *witnesses = @[
        @[@"SONY", @"ILCE-7M3", @"Sigma 24-70mm F2.8 DG DN A019", @"24-70mm F2.8 DG DN | Art 019", @24],
        @[@"SONY", @"ILCE-7M3", @"SIGMA 24-70mm F2.8 DG DN II A024", @"24-70mm F2.8 DG DN II | Art 024", @24],
        @[@"FUJIFILM", @"X-T3", @"Sigma 18-50mm F2.8 DC DN C021", @"Sigma 18-50mm F2.8 DC DN | Contemporary 021", @18],
        @[@"Canon", @"Canon EOS 6D", @"Sigma 70-200mm F2.8 DG OS HSM S018", @"70-200mm F2.8 DG OS HSM | Sports 018", @70],
        @[@"FUJIFILM", @"X-T3", @"33mmF1.4XM", @"Viltrox AF 33mm f/1.4 XF", @33],
    ];
    for (NSArray *witness in witnesses) {
        NSMutableDictionary *metadata = [@{@"Make":witness[0], @"Model":witness[1], @"LensModel":witness[2],
                                           @"FocalLength":witness[4], @"FNumber":@8} mutableCopy];
        NSDictionary *alternate = report(metadata);
        NSDictionary *picker = LensNativeProfileCandidates(metadata, database(), library(), nil);
        if (![alternate[@"matchingIdentityMethod"] isEqual:@"verified-recorded-name-alias"] ||
            ![picker[@"automaticLensID"] isEqual:alternate[@"matchedLensProfileID"]]) return NO;
        metadata[@"LensModel"] = witness[3];
        if (!sameCalibration(alternate, report(metadata))) return NO;
    }

    NSArray *rejected = @[@"Sigma 24-70mm F2.8 DG DN II A019", @"Sigma 24-70mm F2.8 DG DN A024",
                          @"Sigma 24-70mm F2.8 DG DN C019", @"Other 24-70mm F2.8 DG DN A019",
                          @"Sigma 24-70mm F2.8 DG DN A019 + 1.4x", @"Sigma 24-70mm F2.8 DG DN A19",
                          @"33mmF1.4XM"];
    for (NSString *name in rejected) {
        if (report(@{@"Make":@"SONY", @"Model":@"ILCE-7M3", @"LensModel":name, @"FocalLength":@30})) return NO;
    }
    return YES;
}

static BOOL verifyMakerNote(void) {
    NSArray *zoomWitnesses = @[
        @[@50517, @"Sigma 24-70mm F2.8 DG DN | A", @"24-70mm F2.8 DG DN | Art 019"],
        @[@50545, @"Sigma 24-70mm F2.8 DG DN II | A", @"24-70mm F2.8 DG DN II | Art 024"],
    ];
    for (NSArray *witness in zoomWitnesses) {
        NSMutableDictionary *metadata = [@{@"Make":@"SONY", @"Model":@"ILCE-7M3", @"FocalLength":@24, @"FNumber":@8,
                                           @"Sony:LensType2":witness[0], @"LensIDName":witness[1]} mutableCopy];
        NSDictionary *makerNote = report(metadata);
        NSDictionary *picker = LensNativeProfileCandidates(metadata, database(), library(), nil);
        if (![makerNote[@"matchingIdentitySource"] isEqual:@"Sony:LensType2"] ||
            ![picker[@"automaticLensID"] isEqual:makerNote[@"matchedLensProfileID"]]) return NO;
        metadata[@"Lens"] = [witness[1] stringByAppendingString:@" + 1.4x"];
        if (report(metadata)) return NO;
        [metadata removeObjectForKey:@"Lens"];
        metadata[@"Sony:LensType2"] = [witness[0] isEqual:@50517] ? @50545 : @50517;
        if (report(metadata)) return NO;
        metadata[@"Sony:LensType2"] = @50481; // A-mount/adapter ambiguity is outside this rule.
        if (report(metadata)) return NO;
        [metadata removeObjectForKey:@"Sony:LensType2"];
        if (report(metadata)) return NO;
        metadata[@"LensModel"] = witness[2];
        if (!sameCalibration(makerNote, report(metadata))) return NO;
    }
    return YES;
}

static NSString *digest(NSURL *raw) {
    NSData *data = [NSData dataWithContentsOfURL:raw options:NSDataReadingMappedIfSafe error:nil];
    if (!data.length || data.length > UINT32_MAX) return nil;
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    NSMutableString *hex = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) [hex appendFormat:@"%02x", bytes[i]];
    return hex;
}

static BOOL verifyRAW(NSURL *raw, NSString *expected, NSString *camera, NSString *edition, NSNumber *lensType, NSNumber *aperture) {
    if (![digest(raw) isEqual:expected]) return NO;
    NSDictionary *metadata = LensReadRawMetadata(raw, [NSURL fileURLWithPath:@"Resources/LensBridge/exiftool/exiftool"], nil);
    if (![metadata[@"Sony:LensType2"] isEqual:lensType] || ![metadata[@"FocalLength"] isEqual:@24] ||
        fabs([metadata[@"FNumber"] doubleValue] - aperture.doubleValue) > 0.001 ||
        ![metadata[@"Model"] isEqual:camera]) return NO;
    NSDictionary *exif = report(metadata);
    NSMutableDictionary *abbreviated = [metadata mutableCopy];
    [abbreviated removeObjectForKey:@"LensModel"];
    NSDictionary *fallback = report(abbreviated);
    if (![fallback[@"matchingIdentitySource"] isEqual:@"Sony:LensType2"] || !sameCalibration(exif, fallback)) return NO;
    NSDictionary *native = metadata[@"nativeCorrectionSupport"];
    if (![native[@"probeSucceeded"] boolValue] ||
        [exif[@"geometryHandledByNative"] boolValue] != [native[@"lensCorrectionSupported"] boolValue]) return NO;
    CIRAWFilter *decoder = [CIRAWFilter filterWithImageURL:raw];
    decoder.scaleFactor = 0.125f;
    CIImage *image = decoder.outputImage;
    if (!image || CGRectIsEmpty(image.extent) || CGRectIsInfinite(image.extent)) return NO;
    CGRect tile = CGRectMake(CGRectGetMidX(image.extent) - 16, CGRectGetMidY(image.extent) - 16, 32, 32);
    CGImageRef rendered = [[CIContext contextWithOptions:nil] createCGImage:image fromRect:tile];
    if (!rendered) return NO;
    CGImageRelease(rendered);
    if (![digest(raw) isEqual:expected]) return NO;
    printf("Complete %s RAW: Sigma %s at 24 mm f/%.3g, LensType2 %ld, native support=%s, decoded tile and unchanged SHA256.\n",
           camera.UTF8String, edition.UTF8String, aperture.doubleValue, (long)lensType.integerValue,
           [native[@"lensCorrectionSupported"] boolValue] ? "yes" : "no");
    return YES;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (!verifyNames()) return 1;
        if (!verifyMakerNote()) return 2;
        puts("Sigma edition names, Viltrox XF alias, both Sony Sigma lens codes and conflict boundaries passed.");
        // Optional review sample and public raw.pixls.us entry 8847.
        if (argc > 1 && !verifyRAW([NSURL fileURLWithPath:@(argv[1])],
            @"9a6cf2281f20c681a1e788982cab3f9ec033dc56c6395d27d33265a264f4a820", @"ILCE-7M3", @"A019", @50517, @8)) return 3;
        if (argc > 2 && !verifyRAW([NSURL fileURLWithPath:@(argv[2])],
            @"46d73475dfd8f96fd7e2f4d4a721a36cbbaba3d6ea95a4851809cd9d252b2a80", @"ILCE-7M5", @"A024", @50545, @2.8)) return 4;
    }
}
