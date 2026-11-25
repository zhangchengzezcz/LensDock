#import "LensSonyRecordedSettings.h"
#import "LensNativeProfileEngine.h"
#import "LensRecommendationPolicy.h"
#import <CommonCrypto/CommonDigest.h>
static NSString*digest(NSData*d){unsigned char b[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,b);NSMutableString*s=[NSMutableString new];for(NSUInteger i=0;i<sizeof(b);i++)[s appendFormat:@"%02x",b[i]];return s;}
static void check(BOOL good,NSString*name,NSMutableArray*failures){if(!good)[failures addObject:name];}
int main(){@autoreleasepool{
    NSMutableArray*failures=[NSMutableArray new],*checks=[NSMutableArray new],*rawChecks=[NSMutableArray new],*missing=[NSMutableArray new];
    NSData*fixtureData=[NSData dataWithContentsOfFile:@"Tests/Fixtures/Sony-recorded-settings.json"];NSDictionary*fixture=[NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:nil];if(!fixture)return 2;
    NSDictionary*off=fixture[@"files"][0][@"expectedGroupedFields"];
    for(NSArray*example in @[@[@"distortion",@"SubIFD:DistortionCorrection",@0,@"off"],@[@"distortion",@"SubIFD:DistortionCorrection",@1,@"auto"],@[@"distortion",@"SubIFD:DistortionCorrection",@17,@"auto-fixed-by-lens"],@[@"distortion",@"SubIFD:DistortionCorrection",@255,@"unavailable"],@[@"tca",@"SubIFD:ChromaticAberrationCorrection",@0,@"off"],@[@"tca",@"SubIFD:ChromaticAberrationCorrection",@1,@"auto"],@[@"tca",@"SubIFD:ChromaticAberrationCorrection",@255,@"unavailable"],@[@"vignetting",@"SubIFD:VignettingCorrection",@256,@"off"],@[@"vignetting",@"SubIFD:VignettingCorrection",@257,@"auto"],@[@"vignetting",@"SubIFD:VignettingCorrection",@272,@"auto"],@[@"vignetting",@"SubIFD:VignettingCorrection",@511,@"unavailable"],@[@"vignetting",@"SubIFD:VignettingCorrection",@0,@"unknown"],@[@"tca",@"SubIFD:ChromaticAberrationCorrection",@17,@"unknown"],@[@"distortion",@"SubIFD:DistortionCorrection",@-1,@"unknown"]]){
        NSMutableDictionary*g=[off mutableCopy];g[example[1]]=example[2];NSDictionary*r=LensSonyRecordedCorrectionSettings(g),*component=r[@"components"][example[0]];
        check([component[@"setting"]isEqual:example[3]]&&[component[@"recordedCode"]isEqual:example[2]],@"group-specific enum and original code",failures);
        check(![r[@"provesBakedCorrection"]boolValue]&&![r[@"provesDecoderCorrection"]boolValue],@"capture settings never prove pixel processing",failures);
        [checks addObject:@{@"kind":example[0],@"code":example[2],@"setting":component[@"setting"]?:@"missing"}];
    }
    for(id value in @[@"257",@YES,NSNull.null,@257.25,@(NAN),@40000,@-40000]){
        NSMutableDictionary*g=[off mutableCopy];g[@"SubIFD:VignettingCorrection"]=value;NSDictionary*record=LensSonyRecordedCorrectionSettings(g);
        check([record[@"components"][@"vignetting"][@"setting"]isEqual:@"invalid"]&&!record[@"components"][@"vignetting"][@"recordedCode"],@"invalid code retained as invalid, never coerced",failures);
        check([record[@"components"][@"distortion"][@"setting"]isEqual:@"off"],@"malformed component does not replace other facts",failures);
    }
    NSMutableDictionary*g=[off mutableCopy];g[@"Sony:VignettingCorrection"]=@2;g[@"Sony:DistortionCorrection"]=@1;g[@"ExifIFD:ChromaticAberrationCorrection"]=@1;
    check([LensSonyRecordedCorrectionSettings(g)[@"components"][@"vignetting"][@"setting"]isEqual:@"off"],@"MakerNote duplicate cannot replace SubIFD enum",failures);
    [g removeObjectForKey:@"SubIFD:VignettingCorrection"];check([LensSonyRecordedCorrectionSettings(g)[@"components"][@"vignetting"][@"setting"]isEqual:@"not-recorded"],@"missing SubIFD does not fall back to another group",failures);
    [g removeObjectForKey:@"SubIFD:DistortionCorrection"];[g removeObjectForKey:@"SubIFD:ChromaticAberrationCorrection"];check(!LensSonyRecordedCorrectionSettings(g),@"no recorded fields produces no facts",failures);
    for(NSArray*bad in @[@[@"File:FileType",@"DNG"],@[@"IFD0:Make",@"NIKON"],@[@"IFD0:Model",@""],@[@"IFD0:Model",@1],@[@"SubIFD:PhotometricInterpretation",@2]]){g=[off mutableCopy];g[bad[0]]=bad[1];check(!LensSonyRecordedCorrectionSettings(g),@"non-Sony, non-CFA or invalid owner rejected",failures);}
    for(NSDictionary*item in fixture[@"files"]){
        NSURL*raw=[NSURL fileURLWithPath:[@"Tests/PrivateRAW"stringByAppendingPathComponent:item[@"file"]]];
        if(![NSFileManager.defaultManager fileExistsAtPath:raw.path]){[missing addObject:item[@"file"]];continue;}
        NSString*before=digest([NSData dataWithContentsOfURL:raw]);check([before isEqual:item[@"sha256"]],@"pinned public RAW digest",failures);
        NSDictionary*m=LensReadRawMetadata(raw,[NSURL fileURLWithPath:@"Resources/LensBridge/exiftool/exiftool"],nil),*expected=LensSonyRecordedCorrectionSettings(item[@"expectedGroupedFields"]);
        check(m&&[m[@"recordedLensCorrectionSettings"]isEqual:expected],@"production reader automatically captures exact grouped settings",failures);
        check(!m[@"DistortionCorrection"]&&!m[@"ChromaticAberrationCorrection"]&&!m[@"VignettingCorrection"],@"settings never flatten into unqualified capture fields",failures);
        NSMutableDictionary*without=[m mutableCopy];[without removeObjectForKey:@"recordedLensCorrectionSettings"];
        NSDictionary*a=LensNativeProfilePlan(m,[NSURL fileURLWithPath:@"Resources/LensBridge/db"],[NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"],96,64,nil),*b=LensNativeProfilePlan(without,[NSURL fileURLWithPath:@"Resources/LensBridge/db"],[NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"],96,64,nil);
        NSMutableDictionary*strip=a?[a mutableCopy]:nil,*report=[a[@"report"]mutableCopy];[report removeObjectForKey:@"recordedLensCorrectionSettings"];if(strip)strip[@"report"]=report;
        check((!a&&!b)||[strip isEqual:b],@"facts do not change calibration or rendering plans",failures);
        if(a)check([LensRecommendationPolicy(a)isEqual:LensRecommendationPolicy(b)],@"facts alone do not change recommendations",failures);
        if([m[@"nativeCorrectionSupport"][@"lensCorrectionSupported"]boolValue]){
            check(a&&[a[@"report"][@"supplementalVignettingOnly"]boolValue]&&![a[@"report"][@"distortionProfileAvailable"]boolValue]&&![a[@"report"][@"tcaProfileAvailable"]boolValue]&&![a[@"normalizedGeometryMapsLZFSE"]count],@"real native support skips extra geometry even when camera menu says Off",failures);
            check(![LensRecommendationPolicy(a)[@"vignettingAutomatic"]boolValue],@"native support leaves supplemental vignette automatic choice off",failures);
        }
        BOOL unchanged=[before isEqual:digest([NSData dataWithContentsOfURL:raw])];check(unchanged,@"original RAW unchanged",failures);
        [rawChecks addObject:@{@"fixture":item[@"file"],@"sha256":before,@"facts":m[@"recordedLensCorrectionSettings"]?:@{},@"nativeCorrectionSupport":m[@"nativeCorrectionSupport"]?:@{},@"calibrationSourcePresent":@(m[@"embeddedLensCorrectionSource"]!=nil),@"originalUnchanged":@(unchanged)}];
    }
    NSDictionary*result=@{@"scope":@"Source-owned Sony capture-menu settings and production readback only. Neither flags nor this test prove baked corrections, decoder processing, manufacturer frame, optical acceptance or new automatic coverage.",@"enumCases":checks,@"rawChecks":rawChecks,@"missingOptionalRAW":missing,@"fixtureSHA256":digest(fixtureData),@"sourceSHA256":@{@"Sources/Native/LensSonyRecordedSettings.h":digest([NSData dataWithContentsOfFile:@"Sources/Native/LensSonyRecordedSettings.h"]),@"Sources/Native/LensNativeProfileEngine.m":digest([NSData dataWithContentsOfFile:@"Sources/Native/LensNativeProfileEngine.m"]),@"Tests/verify-sony-recorded-settings.m":digest([NSData dataWithContentsOfFile:@"Tests/verify-sony-recorded-settings.m"])},@"failures":failures};
    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/sony-recorded-settings-verification.json"atomically:YES];
    printf("Sony recorded settings: %lu enum cases, %lu complete RAW readbacks, %lu failures.\n",(unsigned long)checks.count,(unsigned long)rawChecks.count,(unsigned long)failures.count);for(NSString*s in failures)fprintf(stderr,"%s\n",s.UTF8String);return failures.count?1:0;
}}
