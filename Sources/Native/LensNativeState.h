#import <Foundation/Foundation.h>
// Version-gated private bridge used only by the isolated research host.
id LensCopyLayerEffects(id layer);
BOOL LensSetLayerEffects(id layer,id effects);
NSData *LensEffectsJSON(id effects,NSError **error);
id LensEffectsFromJSON(NSData *json);
BOOL LensEffectsEquivalent(NSData *left, NSData *right);
