#import <Cocoa/Cocoa.h>
#import "LensHostDiagnostics.h"

// Boolean method names alone cannot establish that a host method is read-only.
// These traps emulate a close/save flow without opening any window or document.
@interface DiagnosticDocument : NSDocument
@property NSUInteger unsafeCalls;
@property NSUInteger safeCalls;
@end
@implementation DiagnosticDocument
- (BOOL)canCloseDocument { self.unsafeCalls++; return YES; }
- (BOOL)canSaveForDiagnosticTest { self.unsafeCalls++; return YES; }
- (BOOL)isDocumentEdited { self.safeCalls++; return NO; }
- (BOOL)validateMenuItem:(NSMenuItem *)item { return YES; }
@end
int main(void) { @autoreleasepool {
 setenv("LENSDOCK_DIAGNOSTICS","1",1);
 DiagnosticDocument *document=[DiagnosticDocument new];
 NSString *event=[@"diagnostic-regression-" stringByAppendingString:NSUUID.UUID.UUIDString];
 LensWriteHostState(document,event);
 if(document.unsafeCalls) { fprintf(stderr,"Diagnostics invoked action-like Boolean methods.\n"); return 3; }
 if(!document.safeCalls)return 4;
 NSString *path=[[NSTemporaryDirectory()stringByAppendingPathComponent:@"LensHostState"]stringByAppendingPathComponent:[event stringByAppendingPathExtension:@"json"]];
 NSDictionary *snapshot=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil];
 if(!snapshot||snapshot[@"document"][@"queries"][@"canCloseDocument"]||snapshot[@"document"][@"queries"][@"canSaveForDiagnosticTest"])return 5;
 BOOL recorded=NO;
 for(NSDictionary *method in snapshot[@"document"][@"methods"])if([method[@"name"]isEqual:@"canCloseDocument"])recorded=YES;
 if(!recorded)return 6;
 [NSFileManager.defaultManager removeItemAtPath:path error:nil];
 puts("Diagnostics read allowed getters and record action-like Boolean methods without invoking them.");
 return 0;
}}
