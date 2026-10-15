#import "LensCorrectionSettings.h"
#import "LensNativeState.h"
#import <CoreImage/CoreImage.h>
#import <objc/message.h>
#import <math.h>
#import "LensCalibrationEvidence.h"
Class LensRegisterVignettingFilter(void);
NSDictionary *LensCorrectionSourceBinding(NSDictionary *live){
 if(![live isKindOfClass:NSDictionary.class])return nil;
 NSDictionary *source=live[@"sourceInformation"];NSString *sha=source[@"rawSHA256"];
 NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"]invertedSet];
 if(![sha isKindOfClass:NSString.class]||sha.length!=64||[sha rangeOfCharacterFromSet:invalid].location!=NSNotFound||![source[@"byteCount"]unsignedLongLongValue])return nil;
 NSMutableDictionary *binding=[@{@"version":@1}mutableCopy];
 for(NSString *key in @[@"sourceInformation",@"rawParameters",@"width",@"height",@"scale",@"angle",@"workingTransfer",@"colorSpaceName"]){if(!live[key])return nil;binding[key]=live[key];}
 return binding;
}
BOOL LensCorrectionSourceMatches(NSDictionary *binding,NSDictionary *live){
 NSDictionary *current=LensCorrectionSourceBinding(live);
 return [binding isKindOfClass:NSDictionary.class]&&current&&[binding isEqual:current];
}
static CIFilter*filterFromItem(NSDictionary*item){NSString*s=item[@"versionSpecifiContainer"][@"CIFilterNSCodingData"];if(![s isKindOfClass:NSString.class])return nil;return [NSKeyedUnarchiver unarchiveTopLevelObjectWithData:[[NSData alloc]initWithBase64EncodedString:s options:0] error:nil];}
NSDictionary*LensSavedCorrectionProfile(id effects){
 NSArray*data=[NSJSONSerialization JSONObjectWithData:LensEffectsJSON(effects,nil)?:NSData.data options:0 error:nil];if(![data isKindOfClass:NSArray.class]||data.count!=2)return nil;
 for(NSDictionary*wrapper in data[1][@"w"])for(NSDictionary*item in wrapper[@"versionSpecifiContainer"][@"effectUnkeyedContainer"]){CIFilter*f=filterFromItem(item);if([f isKindOfClass:LensRegisterVignettingFilter()])return ((id(*)(id,SEL))objc_msgSend)(f,NSSelectorFromString(@"lensProfile"));}
 return nil;
}
static NSData*effectsWithoutCorrection(NSData*existing,NSError**error){
 NSMutableArray*data=[NSJSONSerialization JSONObjectWithData:existing options:NSJSONReadingMutableContainers error:error];if(![data isKindOfClass:NSArray.class]||data.count!=2)return nil;
 NSMutableArray*keep=[NSMutableArray new];for(NSDictionary*wrapper in data[1][@"w"]){NSMutableArray*retained=[NSMutableArray new];for(NSDictionary*item in wrapper[@"versionSpecifiContainer"][@"effectUnkeyedContainer"]){CIFilter*q=filterFromItem(item);if(![q isKindOfClass:LensRegisterVignettingFilter()])[retained addObject:item];}
  if(retained.count){NSMutableDictionary*copy=[wrapper mutableCopy],*box=[wrapper[@"versionSpecifiContainer"]mutableCopy];box[@"effectUnkeyedContainer"]=retained;copy[@"versionSpecifiContainer"]=box;[keep addObject:copy];}}
 data[1][@"w"]=keep;return [NSJSONSerialization dataWithJSONObject:data options:0 error:error];
}
BOOL LensReplaceLayerCorrection(id layer,id effects,NSError**error){
 if(!NSThread.isMainThread)return NO;id original=LensCopyLayerEffects(layer);NSData*before=LensEffectsJSON(original,error);if(!original||!before||!effects)return NO;
 if(LensSetLayerEffects(layer,effects))return YES;
 // Same class and visible CI inputs can compare equal despite a changed
 // archived calibration. Replace only our effect inside one main-thread turn;
 // register history after the final verified state in the caller.
 NSData*without=LensSavedCorrectionProfile(original)?effectsWithoutCorrection(before,error):nil;id intermediate=without?LensEffectsFromJSON(without):nil;
 if(intermediate&&LensSetLayerEffects(layer,intermediate)&&LensSetLayerEffects(layer,effects))return YES;
 BOOL restored=LensSetLayerEffects(layer,original);
 if(!restored&&intermediate)restored=LensSetLayerEffects(layer,intermediate)&&LensSetLayerEffects(layer,original);
 if(error)*error=[NSError errorWithDomain:@"LensBridgeCommit" code:restored?1:2 userInfo:@{NSLocalizedDescriptionKey:restored?@"配置未能完整写入，已恢复原有图层效果。":@"效果回读不一致，未确认应用成功；请保留文档并重新打开核对。"}];
 return NO;
}
id LensEffectsForCorrectionPlan(NSDictionary*plan,NSData*envelope,NSDictionary*settings,NSData*existing,NSError**error){
 NSDictionary*r=plan[@"report"];NSUInteger w=[r[@"width"]unsignedIntegerValue],h=[r[@"height"]unsignedIntegerValue];NSString*transfer=r[@"workingTransfer"];
 if(!w||!h||w>16000||h>16000||(![transfer isEqual:@"linear"]&&![transfer isEqual:@"encoded_sRGB"]))return nil;
 NSDictionary*maps=plan[@"normalizedGeometryMapsLZFSE"];
 if([r[@"supplementalVignettingOnly"]boolValue]&&([settings[@"distortionEnabled"]boolValue]||[settings[@"tcaEnabled"]boolValue]))return nil;
 for(NSString*key in @[@"distortion",@"tca",@"vignetting"]){double strength=[settings[[key stringByAppendingString:@"Strength"]]doubleValue];if(!isfinite(strength)||strength<0||strength>200)return nil;}
 if([settings[@"distortionEnabled"]boolValue]&&!maps[@"D"])return nil;
 if([settings[@"distortionEnabled"]boolValue]&&!LensGeometryCalibrationNeeded(r,@"distortion"))return nil;
 if([settings[@"tcaEnabled"]boolValue]&&(!maps[@"T0"]||!maps[@"T1"]||!maps[@"T2"]))return nil;
 if([settings[@"tcaEnabled"]boolValue]&&!LensGeometryCalibrationNeeded(r,@"tca"))return nil;
 if([settings[@"vignettingEnabled"]boolValue]&&(![r[@"vignettingCorrectionNeeded"]boolValue]||[plan[@"linearGainFloat32BottomUp"]length]!=w*h*4))return nil;
 NSMutableDictionary*profile=[@{@"width":@(w),@"height":@(h),@"workingTransfer":transfer,@"matchedProfile":r,@"gainModeVersion":@3,@"correctionSettings":settings,@"normalizedGeometryMapsLZFSE":maps?:@{}}mutableCopy];
 if(plan[@"linearGainFloat32BottomUp"])profile[@"linearGainFloat32BottomUp"]=plan[@"linearGainFloat32BottomUp"];
 for(NSString*key in @[@"metadata",@"baseMetadata",@"parameterOverrides",@"cornerAssessment",@"assessmentPreviewData"])if(plan[key])profile[key]=plan[key];
 NSDictionary *binding=plan[@"sourceBinding"]?:LensCorrectionSourceBinding(plan[@"liveFingerprint"]);
 if(binding)profile[@"sourceBinding"]=binding;
 CIFilter*f=[[LensRegisterVignettingFilter() alloc]init];[f setDefaults];[f setValue:@100 forKey:@"inputAmount"];((void(*)(id,SEL,id))objc_msgSend)(f,NSSelectorFromString(@"setLensProfile:"),profile);
 NSData*archive=[NSKeyedArchiver archivedDataWithRootObject:f requiringSecureCoding:NO error:error];if(!archive)return nil;
 NSMutableArray*template=[NSJSONSerialization JSONObjectWithData:envelope options:NSJSONReadingMutableContainers error:error],*data=existing?[NSJSONSerialization JSONObjectWithData:existing options:NSJSONReadingMutableContainers error:error]:nil;
 if(![template isKindOfClass:NSArray.class]||template.count!=2)return nil;NSDictionary*baseWrapper=template[1][@"w"][0];if(!data)data=[NSJSONSerialization JSONObjectWithData:envelope options:NSJSONReadingMutableContainers error:error];
 NSMutableArray*wrappers=data[1][@"w"];
 if(existing){NSData*stripped=effectsWithoutCorrection(existing,error);if(!stripped)return nil;data=[NSJSONSerialization JSONObjectWithData:stripped options:NSJSONReadingMutableContainers error:error];wrappers=data[1][@"w"];}else{data[1][@"w"]=[NSMutableArray new];wrappers=data[1][@"w"];}
 NSMutableDictionary*wrapper=[baseWrapper mutableCopy];NSMutableDictionary*container=[wrapper[@"versionSpecifiContainer"]mutableCopy];container[@"type"]=@"PTCustomCIEffect";NSMutableArray*items=[container[@"effectUnkeyedContainer"]mutableCopy];NSMutableDictionary*item=[items[0]mutableCopy],*spec=[item[@"versionSpecifiContainer"]mutableCopy];
 spec[@"CIFilterNSCodingData"]=[archive base64EncodedStringWithOptions:0];spec[@"identifier"]=NSUUID.UUID.UUIDString;spec[@"controlSetCommons"][@"versionSpecifiContainer"][@"isEnabled"]=@YES;item[@"versionSpecifiContainer"]=spec;items[0]=item;container[@"effectUnkeyedContainer"]=items;wrapper[@"versionSpecifiContainer"]=container;[wrappers insertObject:wrapper atIndex:0];
 NSData*json=[NSJSONSerialization dataWithJSONObject:data options:0 error:error];return LensEffectsFromJSON(json);
}
