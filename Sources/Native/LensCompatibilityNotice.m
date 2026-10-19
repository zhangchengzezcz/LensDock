#import "LensCompatibilityNotice.h"
#import "LensHostCompatibility.h"
#import "LensLiveDocument.h"
#import <objc/runtime.h>
#import <objc/message.h>
static id noticeGetter(id obj,NSString*name){SEL s=NSSelectorFromString(name);Method m=class_getInstanceMethod([obj class],s);if(!m||method_getNumberOfArguments(m)!=2)return nil;char*t=method_copyReturnType(m);BOOL object=t&&t[0]=='@';free(t);return object?((id(*)(id,SEL))objc_msgSend)(obj,s):nil;}
@implementation LensCompatibilityController
- (instancetype)init{
 if((self=[super init])){self.checkedDocuments=NSHashTable.weakObjectsHashTable;self.queuedWindows=NSHashTable.weakObjectsHashTable;self.readinessAttempts=NSMapTable.weakToStrongObjectsMapTable;}
 return self;
}
- (NSDictionary*)reportForDocument:(NSDocument*)document{
 NSMutableDictionary*r=[LensHostCompatibilityReport()mutableCopy];NSMutableArray*failures=[r[@"failures"]mutableCopy];
 id script=noticeGetter(document,@"scriptingCurrentLayer");
 r[@"photoOpened"]=@(document!=nil);r[@"selectedLayerAvailable"]=@(script!=nil);
 if([r[@"passed"]boolValue]&&script){
  id layer=LensCopyScriptingReference(script,@"layer");
  if([layer isKindOfClass:NSClassFromString(@"PXMEngine.RawLayer")]){
   id uid=LensCopyScriptingReference(script,@"identifier");
   BOOL valid=[uid isKindOfClass:NSClassFromString(@"PTFoundation.PTHashableString")];
   r[@"rawReferenceCheck"]=valid?@"passed":@"failed";
   if(!valid)[failures addObject:@"当前 RAW 资源引用不兼容"];
  }else {
   r[@"rawReferenceCheck"]=layer?@"not-RAW-layer":@"reference-unavailable";
   if(!layer)[failures addObject:@"当前照片图层引用尚未就绪或不可用"];
  }
 }
 r[@"failures"]=failures;r[@"passed"]=@(failures.count==0);
 return r;
}
- (void)presentReport:(NSDictionary*)report automatic:(BOOL)automatic{
 NSData*json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
 NSString*text=[[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding]?:@"无法生成诊断";
 [text writeToFile:[NSTemporaryDirectory()stringByAppendingPathComponent:@"LensDock-Compatibility.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 NSString*key=@"LensDockSuppressAutomaticCompatibilityNotice";
 if(automatic&&[NSUserDefaults.standardUserDefaults boolForKey:key])return;
 NSAlert*alert=[NSAlert new];alert.messageText=[report[@"passed"]boolValue]?@"照片兼容性检查通过":@"照片兼容性检查未通过";
 NSString*detail=[report[@"passed"]boolValue]?([report[@"rawReferenceCheck"]isEqual:@"passed"]?@"必要接口、数据布局与当前 RAW 图层引用正常。镜头矫正仍会按照片自动匹配可靠标定。":@"必要接口与数据布局正常。镜头矫正需要打开 RAW 并选中 RAW 图层。"): [report[@"failures"]componentsJoinedByString:@"\n"];
 alert.informativeText=[NSString stringWithFormat:@"Pixelmator %@ · Apple 芯片\n%@\n\n%@\n诊断不包含照片、文件路径或拍摄信息。",report[@"hostVersion"],report[@"macOS"],detail];
 alert.showsSuppressionButton=YES;alert.suppressionButton.title=@"以后不再自动提示";alert.suppressionButton.state=[NSUserDefaults.standardUserDefaults boolForKey:key]?NSControlStateValueOn:NSControlStateValueOff;
 [alert addButtonWithTitle:@"继续"];[alert addButtonWithTitle:@"复制诊断"];[alert addButtonWithTitle:@"前往 GitHub Issues"];
 NSModalResponse response=[alert runModal];[NSUserDefaults.standardUserDefaults setBool:alert.suppressionButton.state==NSControlStateValueOn forKey:key];
 if(response==NSAlertSecondButtonReturn){[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:text forType:NSPasteboardTypeString];}
 if(response==NSAlertThirdButtonReturn)[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:report[@"issueURL"]]];
}
- (void)showCompatibility:(id)sender{
 NSDocument*document=NSDocumentController.sharedDocumentController.currentDocument;
 if(!document){NSAlert*alert=[NSAlert new];alert.messageText=@"请先打开照片";alert.informativeText=@"照片载入后会自动检查，也可随时从此菜单重新检查。";[alert addButtonWithTitle:@"好"];[alert runModal];return;}
 [self presentReport:[self reportForDocument:document] automatic:NO];
}
- (void)documentWindowReady:(NSNotification*)notification{
 NSWindow*window=[notification.object isKindOfClass:NSWindow.class]?notification.object:nil;
 [self scheduleWindow:window];
}
- (NSTimeInterval)readinessRetryDelay{return .25;}
- (void)scheduleWindow:(NSWindow*)window{
 if(!window||[self.queuedWindows containsObject:window])return;
 NSDocument*document=window.windowController.document;
 if(![document isKindOfClass:NSDocument.class]||[self.checkedDocuments containsObject:document])return;
 [self.queuedWindows addObject:window];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(self.readinessRetryDelay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  [self.queuedWindows removeObject:window];
  if(!window.visible||window.windowController.document!=document||[self.checkedDocuments containsObject:document])return;
  // Retry independently of window-update notifications; a quiet window can
  // finish loading without generating another notification. Never show over
  // a sheet/modal, or turn a document with no loaded photo into a false pass.
  BOOL waiting=window.attachedSheet||NSApp.modalWindow||!noticeGetter(document,@"scriptingCurrentLayer");
  if(waiting){NSUInteger attempt=[[self.readinessAttempts objectForKey:document]unsignedIntegerValue]+1;[self.readinessAttempts setObject:@(attempt) forKey:document];if(attempt<20)[self scheduleWindow:window];return;}
  NSDictionary*report=[self reportForDocument:document];
  if([report[@"rawReferenceCheck"]isEqual:@"reference-unavailable"]){NSUInteger attempt=[[self.readinessAttempts objectForKey:document]unsignedIntegerValue]+1;[self.readinessAttempts setObject:@(attempt) forKey:document];if(attempt<20){[self scheduleWindow:window];return;}}
  [self.checkedDocuments addObject:document];
  [self presentReport:report automatic:YES];
 });
}
@end
