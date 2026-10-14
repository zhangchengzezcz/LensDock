#import "LensNativeState.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <CoreImage/CoreImage.h>
typedef struct {void*items;void*context;} NativeEffects;
typedef NativeEffects __attribute__((swiftcall)) (*GetEffects)(void* __attribute__((swift_context)));
typedef void __attribute__((swiftcall)) (*SetEffects)(NativeEffects,BOOL,void* __attribute__((swift_context)));
typedef void* __attribute__((swiftcall)) (*CreateEffects)(NativeEffects,void* __attribute__((swift_context)));
static void releaseEffects(NativeEffects value){
 void(*bridgeRelease)(void*)=dlsym(RTLD_DEFAULT,"swift_bridgeObjectRelease");void(*objcRelease)(void*)=dlsym(RTLD_DEFAULT,"objc_release");
 if(value.items)bridgeRelease(value.items);if(value.context)objcRelease(value.context);
}
id LensCopyLayerEffects(id layer){
 GetEffects get=dlsym(RTLD_DEFAULT,"$s9PXMEngine5LayerC7effects12PTFoundation9PTEffectsVSgvg");CreateEffects create=dlsym(RTLD_DEFAULT,"$s12PTFoundation13PTEffectsObjCC7effectsAcA0B0V_tcfC");Class cls=NSClassFromString(@"PTFoundation.PTEffectsObjC");
 if(!layer||!get||!create||!cls)return nil;
 NativeEffects value=get((__bridge void*)layer);if(!value.items){
  // The Swift class has no usable NSObject.init; decode its valid empty schema.
  // Optional.none has no owned payload; the second word is unspecified.
  return LensEffectsFromJSON([@"[1,{\"w\":[],\"o\":1,\"ctx\":[1,{\"cs\":[1,{\"map\":{}}]}]}]" dataUsingEncoding:NSUTF8StringEncoding]);
 }
 // The allocating initializer consumes the two owned getter results.
 return CFBridgingRelease(create(value,(__bridge void*)cls));
}
BOOL LensSetLayerEffects(id layer,id effects){
 GetEffects get=dlsym(RTLD_DEFAULT,"$s12PTFoundation13PTEffectsObjCC7effectsAA0B0Vvg");SetEffects set=dlsym(RTLD_DEFAULT,"$s9PXMEngine5LayerC10setEffects_20isIntermediateChangey12PTFoundation9PTEffectsVSg_SbtF");
 if(!layer||!effects||!get||!set||!dlsym(RTLD_DEFAULT,"swift_bridgeObjectRelease")||!dlsym(RTLD_DEFAULT,"objc_release"))return NO;
 NativeEffects value=get((__bridge void*)effects);set(value,NO,(__bridge void*)layer);
 // Layer.setEffects borrows the value (its owned property setter releases it
 // after this call in the verified arm64 binary); release our getter results.
 releaseEffects(value);return YES;
}
@interface LensStateCoder:NSCoder
@property NSData*data;
@end
@implementation LensStateCoder
- (BOOL)allowsKeyedCoding{return YES;}
- (id)decodeObjectForKey:(NSString*)key{return self.data;}
- (id)decodeObjectOfClass:(Class)cls forKey:(NSString*)key{return self.data;}
@end
NSData*LensEffectsJSON(id effects,NSError**error){
 NSData*archive=[NSKeyedArchiver archivedDataWithRootObject:effects requiringSecureCoding:NO error:error];if(!archive)return nil;
 NSDictionary*p=[NSPropertyListSerialization propertyListWithData:archive options:0 format:nil error:error];
 for(id object in p[@"$objects"]){if([object isKindOfClass:NSData.class]){id value=[NSJSONSerialization JSONObjectWithData:object options:0 error:nil];if([value isKindOfClass:NSArray.class]&&[value count]==2&&[value[1] isKindOfClass:NSDictionary.class])return object;}}
 return nil;
}
id LensEffectsFromJSON(NSData*json){if(!json)return nil;LensStateCoder*c=[LensStateCoder new];c.data=json;return [[NSClassFromString(@"PTFoundation.PTEffectsObjC")alloc]initWithCoder:c];}
static id comparableEffects(NSData*json){
 id state=json?[NSJSONSerialization JSONObjectWithData:json options:NSJSONReadingMutableContainers error:nil]:nil;
 if(![state isKindOfClass:NSArray.class]||[state count]!=2)return nil;
 for(NSMutableDictionary*wrapper in state[1][@"w"])for(NSMutableDictionary*item in wrapper[@"versionSpecifiContainer"][@"effectUnkeyedContainer"]){
  NSMutableDictionary*box=item[@"versionSpecifiContainer"];NSString*archive=box[@"CIFilterNSCodingData"];
  if(![archive isKindOfClass:NSString.class])continue;
  CIFilter*filter=[NSKeyedUnarchiver unarchiveTopLevelObjectWithData:[[NSData alloc]initWithBase64EncodedString:archive options:0] error:nil];
  if(![NSStringFromClass(object_getClass(filter))isEqual:@"LensBridgeProfileVignettingFilter"])continue;
  // Keyed archives can reorder object references across decode/copy/encode.
  // Compare calibrated data and scalar controls, not incidental archive bytes.
  NSMutableDictionary*properties=[NSMutableDictionary new];properties[@"lensProfile"]=[filter valueForKey:@"lensProfile"]?:@{};
  for(NSString*key in filter.inputKeys){id value=[filter valueForKey:key];if([value isKindOfClass:NSNumber.class]||[value isKindOfClass:NSString.class]||[value isKindOfClass:NSValue.class])properties[key]=value;}
  box[@"CIFilterNSCodingData"]=properties;
 }
 return state;
}
BOOL LensEffectsEquivalent(NSData*left,NSData*right){id a=comparableEffects(left),b=comparableEffects(right);return a&&b&&[a isEqual:b];}
