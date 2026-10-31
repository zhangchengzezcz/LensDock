#import "LensSonyGeometryImage.h"

// A versioned explicit mathematical frame, never an automatic frame selector.
// Stored source facts retain their original verification flags. This format
// does not convert Sony nodes into a Lensfun polynomial or certify optics.
static inline BOOL LensSonyArchiveNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]);
}
static inline BOOL LensSonyArchiveArray(id value, NSUInteger count) {
    if (![value isKindOfClass:NSArray.class] || [value count] != count) return NO;
    for (id number in value) if (!LensSonyArchiveNumber(number)) return NO;
    return YES;
}
static inline BOOL LensSonyArchiveFlag(id value) {
    return LensSonyArchiveNumber(value) && ([value doubleValue] == 0 || [value doubleValue] == 1);
}
static inline BOOL LensSonyReadExplicitGeometry(id value, NSDictionary **sourceOut, LensSonyExplicitPixelFrame *frameOut) {
    if (sourceOut) *sourceOut = nil;
    if (frameOut) *frameOut = (LensSonyExplicitPixelFrame){0};
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"provider"] isEqual:@"sony-explicit-frame-v1"] ||
        !LensSonyArchiveNumber(value[@"version"]) || [value[@"version"] doubleValue] != 1) return NO;
    NSDictionary *source = value[@"source"], *frame = value[@"frame"];
    if (![source isKindOfClass:NSDictionary.class] || ![frame isKindOfClass:NSDictionary.class] ||
        ![source[@"schema"] isEqual:@1] || ![source[@"provider"] isEqual:@"sony-subifd-radial-source-v1"] ||
        ![source[@"sourceGroup"] isEqual:@"SubIFD"] || ![source[@"cameraMake"] isEqual:@"SONY"] ||
        ![source[@"cameraModel"] isKindOfClass:NSString.class] || ![source[@"cameraModel"] length] ||
        !LensSonyDimension(source[@"storageWidth"]) || !LensSonyDimension(source[@"storageHeight"])) return NO;
    NSArray *size = frame[@"calibrationSize"], *region = frame[@"decodedRegion"], *output = frame[@"outputSize"];
    NSNumber *orientation = frame[@"orientation"];
    if (!LensSonyArchiveArray(size,2) || !LensSonyArchiveArray(region,4) || !LensSonyArchiveArray(output,2) ||
        !LensSonyArchiveNumber(orientation) || floor(orientation.doubleValue) != orientation.doubleValue) return NO;
    for (NSNumber *dimension in output) if (dimension.doubleValue < 2 || dimension.doubleValue > 16000 ||
        floor(dimension.doubleValue) != dimension.doubleValue) return NO;
    LensSonyExplicitPixelFrame decoded = {CGSizeMake([size[0] doubleValue],[size[1] doubleValue]),
        CGRectMake([region[0] doubleValue],[region[1] doubleValue],[region[2] doubleValue],[region[3] doubleValue]),
        CGSizeMake([output[0] doubleValue],[output[1] doubleValue]),orientation.unsignedIntegerValue};
    NSDictionary *tables = source[@"tables"];
    if (![tables isKindOfClass:NSDictionary.class] || (!tables[@"Distortion"] && !tables[@"ChromaticAberration"])) return NO;
    LensSonyGeometryTransform transform;
    if (!LensSonyPrepareGeometry(source,decoded,tables[@"Distortion"]?1:0,tables[@"ChromaticAberration"]?1:0,&transform)) return NO;
    if (sourceOut) *sourceOut = source;
    if (frameOut) *frameOut = decoded;
    return YES;
}
static inline NSDictionary *LensSonyExplicitGeometryPayload(NSDictionary *source, LensSonyExplicitPixelFrame frame) {
    if (!source) return nil;
    NSDictionary *value = @{@"version":@1,@"provider":@"sony-explicit-frame-v1",@"source":source,
        @"frame":@{@"calibrationSize":@[@(frame.calibrationSize.width),@(frame.calibrationSize.height)],
            @"decodedRegion":@[@(frame.decodedRegion.origin.x),@(frame.decodedRegion.origin.y),@(frame.decodedRegion.size.width),@(frame.decodedRegion.size.height)],
            @"outputSize":@[@(frame.outputSize.width),@(frame.outputSize.height)],@"orientation":@(frame.orientation)}};
    if (!LensSonyReadExplicitGeometry(value,NULL,NULL)) return nil;
    // Snapshot mutable metadata containers before a caller adjusts anything.
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil] : nil;
}
static inline BOOL LensSonyExplicitGeometryReport(NSDictionary *report) {
    LensSonyExplicitPixelFrame frame;
    NSDictionary *source;
    if (![report isKindOfClass:NSDictionary.class]) return NO;
    if (report[@"geometryMapEncoding"]) return NO;
    for (NSString *kind in @[@"distortion",@"tca"]) {
        if (!LensSonyArchiveFlag(report[[kind stringByAppendingString:@"ProfileAvailable"]])) return NO;
        id needed = report[[kind stringByAppendingString:@"CorrectionNeeded"]];
        if (needed && !LensSonyArchiveFlag(needed)) return NO;
    }
    for (NSString *flag in @[@"geometryHandledByNative",@"supplementalVignettingOnly"])
        if (report[flag] && !LensSonyArchiveFlag(report[flag])) return NO;
    id native = report[@"nativeCorrectionSupport"];
    if (native && (![native isKindOfClass:NSDictionary.class] || !LensSonyArchiveFlag(native[@"lensCorrectionSupported"]))) return NO;
    if (!LensSonyReadExplicitGeometry(report[@"explicitGeometry"],&source,&frame) ||
        ([report[@"distortionProfileAvailable"] boolValue] && !source[@"tables"][@"Distortion"]) ||
        ([report[@"tcaProfileAvailable"] boolValue] && !source[@"tables"][@"ChromaticAberration"])) return NO;
    return [report isKindOfClass:NSDictionary.class] && [report[@"geometryProvider"] isEqual:@"sony-explicit-frame-v1"] &&
        LensSonyArchiveNumber(report[@"width"]) && LensSonyArchiveNumber(report[@"height"]) &&
        frame.outputSize.width == [report[@"width"] doubleValue] && frame.outputSize.height == [report[@"height"] doubleValue];
}
static inline BOOL LensSonyExplicitGeometrySettings(id settings) {
    if (![settings isKindOfClass:NSDictionary.class]) return NO;
    for (NSString *kind in @[@"distortion",@"tca",@"vignetting"]) {
        id enabled = settings[[kind stringByAppendingString:@"Enabled"]], strength = settings[[kind stringByAppendingString:@"Strength"]];
        if (!LensSonyArchiveFlag(enabled) || !LensSonyArchiveNumber(strength) || [strength doubleValue] < 0 || [strength doubleValue] > 200) return NO;
    }
    return !settings[@"constrainCropEnabled"] || LensSonyArchiveFlag(settings[@"constrainCropEnabled"]);
}
static inline BOOL LensSonyExplicitGeometryNeeded(NSDictionary *report, NSString *kind) {
    NSDictionary *source;
    if (!LensSonyExplicitGeometryReport(report) || !LensSonyReadExplicitGeometry(report[@"explicitGeometry"],&source,NULL)) return NO;
    if ([report[@"geometryHandledByNative"] boolValue] || [report[@"supplementalVignettingOnly"] boolValue] ||
        [report[@"nativeCorrectionSupport"][@"lensCorrectionSupported"] boolValue]) return NO;
    BOOL tca = [kind isEqual:@"tca"];
    if (!tca && ![kind isEqual:@"distortion"]) return NO;
    NSDictionary *table = source[@"tables"][tca?@"ChromaticAberration":@"Distortion"];
    if (!table) return NO;
    for (NSString *component in tca?@[@"red",@"blue"]:@[@"values"])
        for (NSNumber *value in table[component]) if (value.doubleValue != 0) return YES;
    return NO;
}
static inline BOOL LensSonyExplicitGeometryBound(NSDictionary *report, id binding) {
    if (!LensSonyExplicitGeometryReport(report) || ![binding isKindOfClass:NSDictionary.class] ||
        ![binding[@"version"] isEqual:@1] || !LensSonyArchiveNumber(binding[@"width"]) || !LensSonyArchiveNumber(binding[@"height"]) ||
        [binding[@"width"] doubleValue] != [report[@"width"] doubleValue] || [binding[@"height"] doubleValue] != [report[@"height"] doubleValue]) return NO;
    NSDictionary *info = binding[@"sourceInformation"];
    NSArray *parameters = binding[@"rawParameters"];
    if (![info isKindOfClass:NSDictionary.class] || ![parameters isKindOfClass:NSArray.class] || parameters.count != 2 ||
        ![parameters[0] isEqual:@1] || ![parameters[1] isKindOfClass:NSDictionary.class] ||
        !LensSonyArchiveFlag(parameters[1][@"lc"]) || !LensSonyArchiveArray(binding[@"scale"],2) || !LensSonyArchiveNumber(binding[@"angle"]) ||
        ![binding[@"workingTransfer"] isEqual:report[@"workingTransfer"]] || ![binding[@"colorSpaceName"] isKindOfClass:NSString.class]) return NO;
    NSString *sha = info[@"rawSHA256"];
    return [sha isKindOfClass:NSString.class] && sha.length == 64 &&
        [sha rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location == NSNotFound &&
        LensSonyArchiveNumber(info[@"byteCount"]) && [info[@"byteCount"] doubleValue] > 0 &&
        floor([info[@"byteCount"] doubleValue]) == [info[@"byteCount"] doubleValue];
}
