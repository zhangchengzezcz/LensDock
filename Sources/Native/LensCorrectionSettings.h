#import <Foundation/Foundation.h>
id LensEffectsForCorrectionPlan(NSDictionary *plan,NSData *envelope,NSDictionary *settings,NSData *existingEffects,NSError **error);
NSDictionary *LensSavedCorrectionProfile(id effects);
NSDictionary *LensCorrectionSourceBinding(NSDictionary *liveFingerprint);
BOOL LensCorrectionSourceMatches(NSDictionary *binding, NSDictionary *liveFingerprint);
// Replaces our correction with data-aware readback. Other effects are retained;
// a failed replacement restores the captured effect state before returning.
BOOL LensReplaceLayerCorrection(id layer, id effects, NSError **error);
