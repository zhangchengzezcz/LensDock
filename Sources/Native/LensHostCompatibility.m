#import "LensHostCompatibility.h"
#import "LensNativeState.h"
#import <objc/runtime.h>
NSDictionary*LensInspectHostCompatibility(NSDictionary*contract,NSString*version,BOOL requireUI){
 NSMutableArray*failures=[NSMutableArray new];NSMutableDictionary*layouts=[NSMutableDictionary new];
 if(!LensHostVersionSupported(version))[failures addObject:@"需要 Pixelmator Pro 4.3 或更新版本"];
 NSDictionary*groups=contract[@"requiredHostSymbols"];
 if(![groups isKindOfClass:NSDictionary.class]||groups.count!=3)[failures addObject:@"缺少通用接口契约"];
 NSUInteger exports=0;
 for(NSString*file in groups)for(NSString*symbol in groups[file]){
  exports++;if(!dlsym(RTLD_DEFAULT,symbol.UTF8String))[failures addObject:[@"缺少接口：" stringByAppendingString:symbol]];
 }
 NSDictionary*types=@{@"RAW":@[@"$s12PTFoundation15PTRawParametersVMa",@280,@280],@"Effects":@[@"$s12PTFoundation9PTEffectsVMa",@16,@16],@"Bitmap":@[@"$s9PXMEngine12ContentStateC08RawLayerbC4DataV10BitmapInfoVMa",@16,@16]};
 for(NSString*name in types){NSArray*t=types[name];BOOL ok=LensHostValueLayout([t[0]UTF8String],[t[1]unsignedLongLongValue],[t[2]unsignedLongLongValue]);layouts[name]=@(ok);if(!ok)[failures addObject:[name stringByAppendingString:@" 数据布局不兼容"]];}
 BOOL effectsRoundtrip=NO;
 if([layouts[@"Effects"]boolValue]){
  @try {
  NSData*empty=[@"[1,{\"w\":[],\"o\":1,\"ctx\":[1,{\"cs\":[1,{\"map\":{}}]}]}]" dataUsingEncoding:NSUTF8StringEncoding];
  effectsRoundtrip=LensEffectsEquivalent(empty,LensEffectsJSON(LensEffectsFromJSON(empty),nil));
  } @catch(NSException*exception){effectsRoundtrip=NO;}
 }
 if(!effectsRoundtrip)[failures addObject:@"效果数据序列化自检未通过"];
 if(requireUI){
  for(NSString*name in @[@"PXMPro.Document",@"Pixelmator.ScriptingLayer",@"PXMEngine.RawLayer",@"PTFoundation.PTRawParametersObjC",@"PTFoundation.PTEffectsObjC"])
   if(!NSClassFromString(name))[failures addObject:[@"缺少类型：" stringByAppendingString:name]];

 }
 return @{@"policy":@"capability-check-v1",@"passed":@(failures.count==0),@"hostVersion":version?:@"",@"macOS":NSProcessInfo.processInfo.operatingSystemVersionString,@"architecture":@"arm64",@"requiredExports":@(exports),@"valueLayouts":layouts,@"referenceAccess":@"Swift Mirror; runtime reference classes checked on RAW selection",@"effectsRoundtrip":@(effectsRoundtrip),@"checkedHostUI":@(requireUI),@"failures":failures,@"issueURL":@"https://github.com/zhangchengzezcz/LensDock/issues/new",@"scope":@"接口与数据布局自检；不代表所有未来版本、镜头和照片都已实测。诊断不含照片、文件路径或 EXIF。"};
}
NSDictionary*LensHostCompatibilityReport(void){
 static NSDictionary*contract,*passedReport;static dispatch_once_t once;dispatch_once(&once,^{
  NSURL*url=[NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"LensDock-HostInterfaces.json"];
  contract=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url]?:NSData.data options:0 error:nil];
 });
 @synchronized(NSBundle.mainBundle){
  if(passedReport)return passedReport;
  NSDictionary*report=LensInspectHostCompatibility(contract,[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],YES);
  if([report[@"passed"]boolValue])passedReport=report;
  return report;
 }
}
BOOL LensHostCompatibilityReady(void){return [LensHostCompatibilityReport()[@"passed"]boolValue];}
