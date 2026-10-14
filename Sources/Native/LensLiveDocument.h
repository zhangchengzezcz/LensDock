#import <Cocoa/Cocoa.h>
NSDictionary *LensProbeLiveRAWExport(NSDocument *document, id scriptingLayer);
NSDictionary *LensReadLiveRAWLayer(NSDocument *document, id scriptingLayer, NSURL *temporaryDirectory, NSError **error);
NSDictionary *LensLiveRAWFingerprint(NSDocument *document, id scriptingLayer);
BOOL LensRegisterLiveHistory(NSDocument *document, id scriptingLayer);
