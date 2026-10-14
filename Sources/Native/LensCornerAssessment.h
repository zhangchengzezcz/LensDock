#import <Foundation/Foundation.h>
// Scene observations and predicted highlight clipping. This does not infer a
// lens calibration from dark objects and never changes image pixels.
NSDictionary *LensAssessCorners(NSURL *previewURL, NSData *gainBottomUp, NSUInteger gainWidth, NSUInteger gainHeight, NSString *workingTransfer, NSError **error);
NSDictionary *LensAssessCornerPreviewData(NSData *previewData, NSData *gainBottomUp, NSUInteger gainWidth, NSUInteger gainHeight, NSString *workingTransfer, NSError **error);
