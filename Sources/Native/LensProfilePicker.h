#import <Cocoa/Cocoa.h>
@interface LensProfilePicker:NSObject
- (instancetype)initWithMetadata:(NSDictionary*)metadata databaseURL:(NSURL*)database libraryURL:(NSURL*)library completion:(void(^)(NSDictionary*selection))completion;
- (void)beginSheetForWindow:(NSWindow*)window;
@end
