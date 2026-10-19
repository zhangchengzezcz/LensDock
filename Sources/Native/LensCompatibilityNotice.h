#import <Cocoa/Cocoa.h>
@interface LensCompatibilityController:NSObject
@property NSHashTable*checkedDocuments;
@property NSHashTable*queuedWindows;
@property NSMapTable*readinessAttempts;
- (void)showCompatibility:(id)sender;
- (void)documentWindowReady:(NSNotification*)notification;
- (void)scheduleWindow:(NSWindow*)window;
- (NSTimeInterval)readinessRetryDelay;
- (NSDictionary*)reportForDocument:(NSDocument*)document;
- (void)presentReport:(NSDictionary*)report automatic:(BOOL)automatic;
@end
