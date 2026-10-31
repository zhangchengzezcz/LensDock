#import <Foundation/Foundation.h>
id LensEffectsForCorrectionPlan(NSDictionary *plan,NSData *envelope,NSDictionary *settings,NSData *existingEffects,NSError **error);
NSDictionary *LensSavedCorrectionProfile(id effects);
// Restores a v6 node-based plan only for the same RAW/development state.
// Does not infer a manufacturer frame or choose a new automatic provider.
NSDictionary *LensPlanRestoringExplicitGeometry(NSDictionary *savedProfile, NSDictionary *liveFingerprint);
NSDictionary *LensCorrectionSourceBinding(NSDictionary *liveFingerprint);
BOOL LensCorrectionSourceMatches(NSDictionary *binding, NSDictionary *liveFingerprint);
// Replaces our correction with data-aware readback. Other effects are retained;
// a failed replacement restores the captured effect state before returning.
BOOL LensReplaceLayerCorrection(id layer, id effects, NSError **error);
