#import <Foundation/Foundation.h>
id LensEffectsForCorrectionPlan(NSDictionary *plan,NSData *envelope,NSDictionary *settings,NSData *existingEffects,NSError **error);
NSDictionary *LensSavedCorrectionProfile(id effects);
NSDictionary *LensCorrectionSourceBinding(NSDictionary *liveFingerprint);
BOOL LensCorrectionSourceMatches(NSDictionary *binding, NSDictionary *liveFingerprint);
