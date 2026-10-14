#import <Foundation/Foundation.h>
// Read-only snapshot of a selected native RAW layer. Original bytes are copied
// into the caller's private temporary directory only for metadata inspection.
NSDictionary *LensReadNativeRAWLayer(NSURL *pxdURL, NSString *layerIdentifier, NSURL *temporaryDirectory, NSError **error);
NSString *LensNativeRAWExtension(NSString *contentUTI);
