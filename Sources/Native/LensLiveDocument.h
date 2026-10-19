#import <Cocoa/Cocoa.h>
id LensCopyScriptingReference(id script,NSString*field);
NSDictionary *LensProbeLiveRAWExport(NSDocument *document, id scriptingLayer);
NSDictionary *LensReadLiveRAWLayer(NSDocument *document, id scriptingLayer, NSURL *temporaryDirectory, NSError **error);
NSDictionary *LensLiveRAWFingerprint(NSDocument *document, id scriptingLayer);
BOOL LensRegisterLiveHistory(NSDocument *document, id scriptingLayer);
