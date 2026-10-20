#import "LensCompatibilityNotice.h"
#import "LensHostCompatibility.h"
#import "LensLiveDocument.h"
// Headless scheduling fixtures: no host app, photograph, or real window is used.
NSDictionary*LensHostCompatibilityReport(void){return @{@"passed":@YES,@"failures":@[],@"hostVersion":@"fixture",@"macOS":@"fixture"};}
id LensCopyScriptingReference(id script,NSString*field){return nil;}
@interface NoticeDocument:NSDocument
@property id scriptingCurrentLayer;
@end
@implementation NoticeDocument
@end
@interface NoticeWindowController:NSObject
@property NSDocument*document;
@end
@implementation NoticeWindowController
@end
@interface NoticeWindow:NSObject
@property NoticeWindowController*windowController;
@property(getter=isVisible) BOOL visible;
@property id attachedSheet;
@end
@implementation NoticeWindow
@end
@interface NoticeProbe:LensCompatibilityController
@property NSUInteger reports,presentations,unavailableReports;
@property BOOL exerciseSuppression;
@property(weak) NSWindow*lastOwner;
@end
@implementation NoticeProbe
- (NSTimeInterval)readinessRetryDelay{return .002;}
- (NSDictionary*)reportForDocument:(NSDocument*)document{
 self.reports++;
 return @{@"passed":@YES,@"rawReferenceCheck":self.reports<=self.unavailableReports?@"reference-unavailable":@"passed"};
}
- (void)presentReport:(NSDictionary*)report automatic:(BOOL)automatic forWindow:(NSWindow*)window{
 self.presentations++;
 self.lastOwner=window;
 // The real method must return without creating NSAlert when opted out.
 if(self.exerciseSuppression)[super presentReport:report automatic:automatic forWindow:window];
}
@end
static NoticeWindow*window(BOOL loaded){
 NoticeDocument*d=[NoticeDocument new];if(loaded)d.scriptingCurrentLayer=[NSObject new];
 NoticeWindow*w=[NoticeWindow new];w.visible=YES;w.windowController=[NoticeWindowController new];w.windowController.document=d;return w;
}
static void pump(NSTimeInterval duration){NSDate*end=[NSDate dateWithTimeIntervalSinceNow:duration];while(end.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];}
static void require(BOOL condition,const char*message){if(!condition){fprintf(stderr,"%s\n",message);exit(1);}}
int main(){@autoreleasepool{
 NoticeProbe*p=[NoticeProbe new];p.unavailableReports=3;NoticeWindow*w=window(NO);
 [p scheduleWindow:(NSWindow*)w];[p scheduleWindow:(NSWindow*)w];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_MSEC),dispatch_get_main_queue(),^{((NoticeDocument*)w.windowController.document).scriptingCurrentLayer=[NSObject new];});
 pump(.12);require(p.reports==4&&p.presentations==1&&p.lastOwner==(id)w,"Photo/reference readiness must retry without further window events and present once on the originating document");
 [p scheduleWindow:(NSWindow*)w];pump(.02);require(p.presentations==1,"Reactivation must not repeat a notice");
 NoticeWindow*second=window(YES);[p scheduleWindow:(NSWindow*)second];pump(.02);require(p.presentations==2,"A different opened photograph must be checked");
 NoticeProbe*bounded=[NoticeProbe new];bounded.unavailableReports=100;NoticeWindow*bad=window(YES);[bounded scheduleWindow:(NSWindow*)bad];pump(.12);
 require(bounded.reports==20&&bounded.presentations==1,"Unavailable references must stop retrying and report once");
 NoticeProbe*empty=[NoticeProbe new];NoticeWindow*blank=window(NO);[empty scheduleWindow:(NSWindow*)blank];pump(.12);
 require(empty.reports==0&&empty.presentations==0&&![empty.queuedWindows containsObject:blank],"An unloaded document must never receive a false pass or retry indefinitely");
 ((NoticeDocument*)blank.windowController.document).scriptingCurrentLayer=[NSObject new];[empty scheduleWindow:(NSWindow*)blank];pump(.02);require(empty.presentations==1,"A later load notification must still work after initial readiness timeout");
 NoticeProbe*closed=[NoticeProbe new];NoticeWindow*gone=window(YES);[closed scheduleWindow:(NSWindow*)gone];gone.visible=NO;pump(.02);require(closed.reports==0,"Closed windows must not produce stale notices");
 NoticeProbe*sheet=[NoticeProbe new];NoticeWindow*blocked=window(YES);blocked.attachedSheet=[NSObject new];[sheet scheduleWindow:(NSWindow*)blocked];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_MSEC),dispatch_get_main_queue(),^{blocked.attachedSheet=nil;});pump(.04);require(sheet.presentations==1,"A sheet must postpone rather than lose the notice");
 NSString*key=@"LensDockSuppressAutomaticCompatibilityNotice";id previous=[NSUserDefaults.standardUserDefaults objectForKey:key];
 [NSUserDefaults.standardUserDefaults setBool:YES forKey:key];NoticeProbe*suppressed=[NoticeProbe new];suppressed.exerciseSuppression=YES;NoticeWindow*optedOut=window(YES);[suppressed scheduleWindow:(NSWindow*)optedOut];pump(.02);
 require(suppressed.reports==1&&suppressed.presentations==1,"Opt-out must still run the document check and safely bypass the real alert");
 if(previous)[NSUserDefaults.standardUserDefaults setObject:previous forKey:key];else[NSUserDefaults.standardUserDefaults removeObjectForKey:key];
 NSDictionary*r=@{@"scope":@"Headless production-controller scheduling with fixture documents/windows; real Pixelmator GUI still pending",@"quietLoadRetries":@YES,@"sameDocumentDeduplicated":@YES,@"differentDocumentChecked":@YES,@"unavailableReferenceBoundedAt":@20,@"unloadedDocumentNeverPassed":@YES,@"closedWindowIgnored":@YES,@"sheetDeferral":@YES,@"optOutStillChecks":@YES,@"realGUIAcceptance":@NO};
 [[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/photo-open-notice-verification.json" atomically:YES];
 puts("Photo-open retry, deduplication, close/sheet deferral and opt-out safety passed (headless fixtures).");
}}
