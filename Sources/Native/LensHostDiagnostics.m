#import "LensHostDiagnostics.h"
#import "LensHostCompatibility.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

typedef BOOL __attribute__((swiftcall)) (*HostBoolGetter)(void * __attribute__((swift_context)));

static BOOL relevant(NSString *name){
 for(NSString *term in @[@"load",@"busy",@"progress",@"sav",@"edit",@"closed",@"operation",@"transaction",@"undo",@"read",@"offline",@"lock"])
  if([name rangeOfString:term options:NSCaseInsensitiveSearch].location!=NSNotFound)return YES;
 return NO;
}
static NSDictionary *state(id object){
 if(!object)return @{};
 NSMutableDictionary *values=[NSMutableDictionary new];NSMutableArray *methods=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];
 for(Class c=object_getClass(object);c&&c!=NSObject.class;c=class_getSuperclass(c)){
  unsigned count=0;Method *list=class_copyMethodList(c,&count);
  for(unsigned i=0;i<count;i++){
   SEL selector=method_getName(list[i]);NSString *name=NSStringFromSelector(selector);
   if(!relevant(name)||[seen containsObject:name])continue;
   [seen addObject:name];[methods addObject:@{@"name":name,@"encoding":@(method_getTypeEncoding(list[i]))}];
   // A Boolean-looking name does not imply a pure query. In this host,
   // canCloseDocument enters the close/save-confirmation flow. Invoke only
   // known state getters; retain all other relevant methods as metadata.
   if(method_getNumberOfArguments(list[i])!=2||![@[@"isDocumentEdited",@"isEntireFileLoaded",@"isLocked",@"isClosed",@"hasUndoManager",@"hasUnautosavedChanges"] containsObject:name])continue;
   char *type=method_copyReturnType(list[i]);BOOL boolean=type&&(strcmp(type,"B")==0||strcmp(type,"c")==0);free(type);
   if(boolean)@try{values[name]=@(((BOOL(*)(id,SEL))objc_msgSend)(object,selector));}@catch(NSException *e){values[name]=@"query-exception";}
  }
  free(list);
 }
 return @{@"class":NSStringFromClass(object_getClass(object)),@"queries":values,@"methods":methods};
}
void LensWriteHostState(NSDocument *document,NSString *event){
 if(!getenv("LENSDOCK_DIAGNOSTICS")||!NSThread.isMainThread||!document)return;
 NSMutableArray *windows=[NSMutableArray new];
 for(NSWindowController *controller in document.windowControllers){
  NSWindow *window=controller.window;
  [windows addObject:@{@"controller":state(controller),@"contentController":state(window.contentViewController),@"visible":@(window.visible),@"key":@(window.keyWindow),@"main":@(window.mainWindow),@"attachedSheet":@(window.attachedSheet!=nil)}];
 }
 NSMutableDictionary *validation=[NSMutableDictionary new];
 for(NSString *action in @[@"saveDocument:",@"saveDocumentAs:",@"performClose:",@"revertDocumentToSaved:"]){
  NSMenuItem *item=[[NSMenuItem alloc]initWithTitle:@"Lens diagnostic" action:NSSelectorFromString(action) keyEquivalent:@""];
  if([document respondsToSelector:@selector(validateMenuItem:)])validation[action]=@([(id<NSMenuItemValidation>)document validateMenuItem:item]);
 }
 NSMutableDictionary *swiftState=[NSMutableDictionary new];
 if(LensHostVersionSupported([NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"])&&[document isKindOfClass:NSClassFromString(@"PXMPro.Document")]){
  NSDictionary *queries=@{@"isShowingProgress":@"$s6PXMKit0A8DocumentC17isShowingProgressSbvg",@"initialDrawHappened":@"$s6PXMKit0A8DocumentC19initialDrawHappenedSbvg",@"fullContentHasBeenLoaded":@"$s6PXMKit0A8DocumentC24fullContentHasBeenLoadedSbvg",@"isCurrenlyLoadingFullContent":@"$s6PXMKit0A8DocumentC28isCurrenlyLoadingFullContentSbvg"};
  for(NSString *key in queries){HostBoolGetter get=dlsym(RTLD_DEFAULT,[queries[key]UTF8String]);if(get)swiftState[key]=@(get((__bridge void*)document));}
 }
 NSMutableArray *savePanels=[NSMutableArray new];
 for(NSWindow *window in NSApp.windows)if([window isKindOfClass:NSSavePanel.class]){
  NSSavePanel *panel=(NSSavePanel*)window;NSMutableArray *types=[NSMutableArray new];for(id type in panel.allowedContentTypes)[types addObject:[type identifier]];
  [savePanels addObject:@{@"class":NSStringFromClass(object_getClass(panel)),@"delegate":state(panel.delegate),@"name":panel.nameFieldStringValue?:@"",@"allowedContentTypes":types,@"URLPresent":@(panel.URL!=nil),@"directoryPresent":@(panel.directoryURL!=nil)}];
 }
 NSDictionary *snapshot=@{@"event":event?:@"",@"time":@(NSDate.date.timeIntervalSince1970),@"document":state(document),@"swiftDocumentState":swiftState,@"windows":windows,@"savePanels":savePanels,@"menuValidation":validation,@"fileType":document.fileType?:@"nil",@"filePresent":@(document.fileURL!=nil),@"edited":@(document.documentEdited),@"undo":@(document.undoManager.canUndo),@"active":@(NSApp.active)};
 NSData *data=[NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
 NSString *root=[NSTemporaryDirectory()stringByAppendingPathComponent:@"LensHostState"];
 [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 [data writeToFile:[root stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json",event?:@"current"]] atomically:YES];
}
