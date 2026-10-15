#import "LensNativeState.h"
#import "LensCorrectionSettings.h"
#import <CoreImage/CoreImage.h>
#import <dlfcn.h>
typedef struct{void*items;void*context;} Effects;
typedef Effects __attribute__((swiftcall))(*Get)(void* __attribute__((swift_context)));
typedef BOOL __attribute__((swiftcall))(*Equal)(Effects,Effects);
typedef void* __attribute__((swiftcall))(*Create)(Effects,void* __attribute__((swift_context)));
@interface TestEffectLayer:NSObject
@property id effects;
@property NSUInteger attempts;
@property BOOL rejectNew;
@end
@implementation TestEffectLayer
@end
// Test-only layer symbols emulate the verified host's native no-op comparison.
// No PXMEngine object is created and no application document is touched.
Effects __attribute__((swiftcall))testGet(void* __attribute__((swift_context))) __asm__("_$s9PXMEngine5LayerC7effects12PTFoundation9PTEffectsVSgvg");
Effects __attribute__((swiftcall))testGet(void* __attribute__((swift_context))self){TestEffectLayer*layer=(__bridge id)self;Get get=dlsym(RTLD_DEFAULT,"$s12PTFoundation13PTEffectsObjCC7effectsAA0B0Vvg");return get((__bridge void*)layer.effects);}
void __attribute__((swiftcall))testSet(Effects,BOOL,void* __attribute__((swift_context))) __asm__("_$s9PXMEngine5LayerC10setEffects_20isIntermediateChangey12PTFoundation9PTEffectsVSg_SbtF");
void __attribute__((swiftcall))testSet(Effects value,BOOL intermediate,void* __attribute__((swift_context))self){
 TestEffectLayer*layer=(__bridge id)self;layer.attempts++;
 void*(*retainBridge)(void*)=dlsym(RTLD_DEFAULT,"swift_bridgeObjectRetain");void*(*retainObject)(void*)=dlsym(RTLD_DEFAULT,"objc_retain");if(value.items)retainBridge(value.items);if(value.context)retainObject(value.context);
 Create create=dlsym(RTLD_DEFAULT,"$s12PTFoundation13PTEffectsObjCC7effectsAcA0B0V_tcfC");id incoming=CFBridgingRelease(create(value,(__bridge void*)NSClassFromString(@"PTFoundation.PTEffectsObjC")));
 if(layer.rejectNew&&[LensSavedCorrectionProfile(incoming)[@"metadata"][@"Model"]isEqual:@"B"])return;
 Get get=dlsym(RTLD_DEFAULT,"$s12PTFoundation13PTEffectsObjCC7effectsAA0B0Vvg");Effects old=get((__bridge void*)layer.effects);Equal equal=dlsym(RTLD_DEFAULT,"$s12PTFoundation9PTEffectsV2eeoiySbAC_ACtFZ");BOOL same=equal(old,value);
 void(*releaseBridge)(void*)=dlsym(RTLD_DEFAULT,"swift_bridgeObjectRelease");void(*releaseObject)(void*)=dlsym(RTLD_DEFAULT,"objc_release");if(old.items)releaseBridge(old.items);if(old.context)releaseObject(old.context);
 if(!same)layer.effects=incoming;
}
int main(){@autoreleasepool{
 if(!dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL))return 1;
 if(!dlsym(RTLD_DEFAULT,"$s9PXMEngine5LayerC7effects12PTFoundation9PTEffectsVSgvg")||!dlsym(RTLD_DEFAULT,"$s9PXMEngine5LayerC10setEffects_20isIntermediateChangey12PTFoundation9PTEffectsVSg_SbtF"))return 2;
 NSData*envelope=[NSData dataWithContentsOfFile:@"Resources/native-effects-template.json"];NSMutableArray*other=[NSJSONSerialization JSONObjectWithData:envelope options:NSJSONReadingMutableContainers error:nil];CIFilter*color=[CIFilter filterWithName:@"CIColorControls"];[color setDefaults];[color setValue:@.8 forKey:@"inputSaturation"];
 NSMutableDictionary*otherItem=other[1][@"w"][0][@"versionSpecifiContainer"][@"effectUnkeyedContainer"][0][@"versionSpecifiContainer"];otherItem[@"CIFilterNSCodingData"]=[[NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:nil]base64EncodedStringWithOptions:0];NSData*otherJSON=[NSJSONSerialization dataWithJSONObject:other options:0 error:nil];
 NSDictionary*settings=@{@"distortionEnabled":@NO,@"tcaEnabled":@NO,@"vignettingEnabled":@NO,@"distortionStrength":@0,@"tcaStrength":@0,@"vignettingStrength":@0};
 NSDictionary*plan=@{@"report":@{@"width":@4,@"height":@4,@"workingTransfer":@"encoded_sRGB"},@"metadata":@{@"Model":@"A"}};
 id original=LensEffectsForCorrectionPlan(plan,envelope,settings,otherJSON,nil);NSMutableDictionary*changed=[plan mutableCopy];changed[@"metadata"]=@{@"Model":@"B"};id target=LensEffectsForCorrectionPlan(changed,envelope,settings,otherJSON,nil);
 TestEffectLayer*layer=[TestEffectLayer new];layer.effects=original;if(LensSetLayerEffects(layer,target)||!LensEffectsEquivalent(LensEffectsJSON(layer.effects,nil),LensEffectsJSON(original,nil)))return 3;
 layer.attempts=0;NSError*error=nil;if(!LensReplaceLayerCorrection(layer,target,&error)||layer.attempts!=3||![LensSavedCorrectionProfile(layer.effects)[@"metadata"][@"Model"]isEqual:@"B"])return 4;
 NSArray*final=[NSJSONSerialization JSONObjectWithData:LensEffectsJSON(layer.effects,nil) options:0 error:nil];if([final[1][@"w"]count]!=2||!LensEffectsEquivalent(LensEffectsJSON(layer.effects,nil),LensEffectsJSON(target,nil)))return 5;
 layer.effects=original;layer.rejectNew=YES;error=nil;if(LensReplaceLayerCorrection(layer,target,&error)||error.code!=1||!LensEffectsEquivalent(LensEffectsJSON(layer.effects,nil),LensEffectsJSON(original,nil)))return 6;
 NSDictionary*out=@{@"scope":@"Real PTFoundation native value equality with a test-only layer setter, not a GUI persistence claim",@"nativeIgnoredOpaqueMetadataReproduced":@YES,@"directSetterDoesNotReportFalseSuccess":@YES,@"replacementWritesChangedMetadata":@YES,@"otherEffectRetained":@YES,@"failedReplacementRestoresOriginalEffects":@YES};[[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/effect-replacement-verification.json" atomically:YES];puts("Opaque-profile updates are verified, other effects retained, and failed writes roll back.");
}}
