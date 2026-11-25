#import "LensSonyFallbackPlan.h"
#import "LensSonyRecordedSettings.h"
#import "LensNativeProfileEngine.h"
#import "LensRecommendationPolicy.h"
#import "LensCorrectionSettings.h"
#import "LensNativeState.h"
#import <dlfcn.h>
#import <CommonCrypto/CommonDigest.h>
static void check(BOOL ok,NSString *name,NSMutableArray *failures){if(!ok)[failures addObject:name];}
static NSString *digest(NSData *data){unsigned char bytes[32];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);NSMutableString *out=[NSMutableString new];for(int i=0;i<32;i++)[out appendFormat:@"%02x",bytes[i]];return out;}
int main(){@autoreleasepool{
 NSMutableArray *failures=[NSMutableArray new],*orientations=[NSMutableArray new],*actual=[NSMutableArray new];
 NSDictionary *fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Tests/Fixtures/Sony-embedded-metadata.json"] options:0 error:nil];
 NSDictionary *source=LensSonyEmbeddedSourceEvidence(fixture[@"files"][0][@"expectedGroupedFields"]);
 NSDictionary *native=@{@"probeSucceeded":@YES,@"lensCorrectionSupported":@NO,@"lensCorrectionEnabledByDefault":@NO,@"nativePixelSize":@[@6000,@4000],@"decoderOrientation":@1};
 // An intentionally unlisted lens exercises failure of catalogue identity.
 // Its owned, fixed public tables remain unchanged; this is a routing fixture,
 // not evidence for another lens or a manufacturer coordinate convention.
 NSDictionary *metadata=@{@"Make":@"SONY",@"Model":source[@"cameraModel"],@"LensModel":@"Unlisted routing fixture 27",@"FocalLength":@30,@"FNumber":@5.6,@"Orientation":@1,@"embeddedLensCorrectionSource":source,@"nativeCorrectionSupport":native};
 NSURL *db=[NSURL fileURLWithPath:@"Resources/LensBridge/db"],*lib=[NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"];
 NSDictionary *candidate=LensSonyDecodedFrameFallbackPlan(metadata,96,64);
 check(candidate&&LensSonyExplicitGeometryReport(candidate[@"report"]),@"aligned frame produces valid explicit candidate",failures);
 NSError *error=nil;NSDictionary *plan=LensNativeProfilePlan(metadata,db,lib,96,64,&error);
 check(plan&&[plan isEqual:candidate]&&!error,@"catalogue no-match automatically finds candidate without stale error",failures);
 NSDictionary *policy=LensRecommendationPolicy(plan);
 check([policy[@"geometryTrial"]boolValue]&&![policy[@"distortionAutomatic"]boolValue]&&![policy[@"tcaAutomatic"]boolValue]&&![policy[@"vignettingAutomatic"]boolValue],@"unproven frame never automatically enables correction",failures);
 check([policy[@"strengths"][0]doubleValue]>0&&[policy[@"strengths"][1]doubleValue]>0&&[policy[@"strengths"][2]doubleValue]==0,@"independent nonzero trial amounts and zero vignette recommendation",failures);
 check(!plan[@"linearGainFloat32BottomUp"]&&![plan[@"normalizedGeometryMapsLZFSE"]count]&&![plan[@"report"][@"manufacturerFrameProven"]boolValue]&&![source[@"pixelFrameVerified"]boolValue],@"no dense field, invented gain or manufacturer proof",failures);
 for(NSUInteger orientation=1;orientation<=8;orientation++){
  NSMutableDictionary *m=[metadata mutableCopy],*n=[native mutableCopy];m[@"Orientation"]=@(orientation);n[@"decoderOrientation"]=@(orientation);m[@"nativeCorrectionSupport"]=n;
  NSUInteger w=orientation>=5?64:96,h=orientation>=5?96:64;NSDictionary *p=LensNativeProfilePlan(m,db,lib,w,h,nil);
  NSDictionary *payload=p[@"report"][@"explicitGeometry"];
  check(p&&[payload[@"frame"][@"orientation"]unsignedIntegerValue]==orientation&&[p[@"report"][@"width"]unsignedIntegerValue]==w&&[p[@"report"][@"height"]unsignedIntegerValue]==h,@"oriented fallback bypasses second orientation transform",failures);
  [orientations addObject:@{@"orientation":@(orientation),@"width":@(w),@"height":@(h),@"produced":@(p!=nil)}];
 }
 for(NSDictionary *change in @[@{@"probeSucceeded":@NO},@{@"lensCorrectionSupported":@YES},@{@"lensCorrectionSupported":@2},@{@"lensCorrectionEnabledByDefault":@YES},@{@"nativePixelSize":@[@6024,@4024]},@{@"decoderOrientation":@6},@{@"nativePixelSize":NSNull.null}]){
  NSMutableDictionary *m=[metadata mutableCopy],*n=[native mutableCopy];[n addEntriesFromDictionary:change];m[@"nativeCorrectionSupport"]=n;check(!LensSonyDecodedFrameFallbackPlan(m,96,64),@"native/decoder conflict refuses candidate",failures);
 }
 for(NSDictionary *change in @[@{@"Model":@"different source owner"},@{@"embeddedLensCorrectionSource":NSNull.null},@{@"Orientation":@1.5},@{@"LensDockProfileSelection":@{@"lensID":@"missing"}}]){
  NSMutableDictionary *m=[metadata mutableCopy];[m addEntriesFromDictionary:change];check(!LensSonyDecodedFrameFallbackPlan(m,96,64),@"invalid owner/orientation or manual selection refuses fallback",failures);
 }
 check(!LensSonyDecodedFrameFallbackPlan(metadata,96,54)&&!LensSonyDecodedFrameFallbackPlan(metadata,16000,16000)&&!LensSonyDecodedFrameFallbackPlan(metadata,1,1),@"aspect, total pixels and invalid size refused",failures);
 NSMutableDictionary *cropped=[metadata mutableCopy],*s=[source mutableCopy],*n=[native mutableCopy];s[@"recordedFullImageSize"]=@[@3000,@2000];n[@"nativePixelSize"]=s[@"recordedFullImageSize"];cropped[@"embeddedLensCorrectionSource"]=s;cropped[@"nativeCorrectionSupport"]=n;
 check(!LensSonyDecodedFrameFallbackPlan(cropped,96,64),@"reduced capture rejected despite equal decoded dimensions",failures);
 error=nil;check(!LensNativeProfilePlan(metadata,db,[NSURL fileURLWithPath:@"/nonexistent/lensfun.dylib"],96,64,&error)&&error.code!=3,@"broken runtime dependency cannot be hidden by fallback",failures);
 error=nil;check(!LensNativeProfilePlan(metadata,[NSURL fileURLWithPath:@"/nonexistent/db"],lib,96,64,&error)&&error.code!=3,@"missing database cannot be hidden by fallback",failures);
 NSMutableDictionary *manual=[metadata mutableCopy];manual[@"LensDockProfileSelection"]=@{@"lensID":@"missing"};check(!LensNativeProfilePlan(manual,db,lib,96,64,nil),@"invalid explicit selection never replaced automatically",failures);
 NSDictionary *flags=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Tests/Fixtures/Sony-recorded-settings.json"] options:0 error:nil];
 for(NSDictionary *item in flags[@"files"]){
  NSMutableDictionary *m=[metadata mutableCopy];m[@"recordedLensCorrectionSettings"]=LensSonyRecordedCorrectionSettings(item[@"expectedGroupedFields"]);
  check([LensRecommendationPolicy(LensSonyDecodedFrameFallbackPlan(m,96,64))isEqual:policy],@"Auto/Off/mismatched capture settings cannot enable candidate",failures);
 }
 for(NSString *kind in @[@"Distortion",@"ChromaticAberration"]){
  NSMutableDictionary *m=[metadata mutableCopy],*modified=[source mutableCopy],*tables=[source[@"tables"]mutableCopy];[tables removeObjectForKey:kind];modified[@"tables"]=tables;m[@"embeddedLensCorrectionSource"]=modified;NSDictionary *r=LensSonyDecodedFrameFallbackPlan(m,96,64)[@"report"];
  check(r&&!LensGeometryCalibrationNeeded(r,[kind isEqual:@"Distortion"]?@"distortion":@"tca")&&![r[@"vignettingProfileAvailable"]boolValue],@"missing component stays absent independently",failures);
 }
 NSMutableDictionary *zero=[metadata mutableCopy],*zs=[source mutableCopy],*zt=[source[@"tables"]mutableCopy];for(NSString *kind in @[@"Distortion",@"ChromaticAberration"]){NSMutableDictionary *table=[zt[kind]mutableCopy];NSMutableArray *values=[NSMutableArray new];for(NSUInteger i=0;i<[table[@"nodeCount"]unsignedIntegerValue];i++)[values addObject:@0];for(NSString *key in [kind isEqual:@"Distortion"]?@[@"values"]:@[@"red",@"blue"])table[key]=values;zt[kind]=table;}zs[@"tables"]=zt;zero[@"embeddedLensCorrectionSource"]=zs;
 NSDictionary *zp=LensSonyDecodedFrameFallbackPlan(zero,96,64);check(zp&&[LensRecommendationPolicy(zp)[@"strengths"]isEqual:@[@0,@0,@0]],@"zero tables cannot manufacture a warp or gain",failures);
 // Persist through the real native effect wrapper with the same RAW binding.
 void *framework=dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL);check(framework!=NULL,@"native archive framework loaded",failures);
 NSDictionary *bindingFixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Tests/Fixtures/A6000-reopen-binding.json"] options:0 error:nil];NSMutableDictionary *live=[bindingFixture[@"savedBinding"]mutableCopy];live[@"width"]=@96;live[@"height"]=@64;live[@"workingTransfer"]=@"linear";
 NSMutableDictionary *bound=[plan mutableCopy];bound[@"sourceBinding"]=LensCorrectionSourceBinding(live);
 NSDictionary *settings=@{@"distortionEnabled":@YES,@"distortionStrength":@80,@"tcaEnabled":@YES,@"tcaStrength":@120,@"vignettingEnabled":@NO,@"vignettingStrength":@0,@"constrainCropEnabled":@YES};
 id effects=LensEffectsForCorrectionPlan(bound,[NSData dataWithContentsOfFile:@"Resources/native-effects-template.json"],settings,nil,nil);NSDictionary *saved=LensSavedCorrectionProfile(LensEffectsFromJSON(LensEffectsJSON(effects,nil)));
 NSDictionary *restored=LensPlanRestoringExplicitGeometry(saved,live);check(restored&&[saved[@"correctionSettings"]isEqual:settings]&&[restored[@"report"]isEqual:plan[@"report"]],@"candidate source/frame/user choices survive real native effect serialization",failures);
 for(NSString *file in @[@"ILCE-6000.ARW",@"ILCE-7RM2-1315.ARW",@"ILCE-7RM2-1318.ARW"]){
  NSURL *url=[NSURL fileURLWithPath:[@"Tests/PrivateRAW"stringByAppendingPathComponent:file]];NSData *before=[NSData dataWithContentsOfURL:url];if(!before)continue;
  NSDictionary *m=LensReadRawMetadata(url,[NSURL fileURLWithPath:@"Resources/LensBridge/exiftool/exiftool"],nil),*p=LensNativeProfilePlan(m,db,lib,96,64,nil);NSMutableDictionary *without=[m mutableCopy];[without removeObjectForKey:@"embeddedLensCorrectionSource"];NSDictionary *existing=LensNativeProfilePlan(without,db,lib,96,64,nil);
  check(p&&[p isEqual:existing]&&!p[@"report"][@"geometryProvider"],@"actual native or successful Lensfun plan takes precedence",failures);check([before isEqual:[NSData dataWithContentsOfURL:url]],@"RAW bytes unchanged",failures);
  [actual addObject:@{@"fixture":file,@"sha256":digest(before),@"nativeSupported":m[@"nativeCorrectionSupport"][@"lensCorrectionSupported"]?:@NO,@"existingPlanPreserved":@([p isEqual:existing])}];
 }
 NSDictionary *result=@{@"scope":@"Automatic discovery of an explicitly unverified Sony decoded-frame candidate, disabled by default. Routing fixtures and native archive serialization, not optical proof or real PXD acceptance.",@"orientations":orientations,@"actualRAW":actual,@"manufacturerFrameProven":@NO,@"automaticGeometryEnabled":@NO,@"vignetteGainGenerated":@NO,@"failures":failures};
 [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/sony-fallback-verification.json"atomically:YES];
 for(NSString *failure in failures)fprintf(stderr,"%s\n",failure.UTF8String);printf("Sony fallback: %lu orientations, %lu original RAW priority checks, %lu failures.\n",orientations.count,actual.count,failures.count);return failures.count?1:0;
}}
