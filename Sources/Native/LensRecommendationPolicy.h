#import <Foundation/Foundation.h>

// Recommendations are separate from a user's enabled state and chosen strength.
NSDictionary *LensRecommendationPolicy(NSDictionary *plan);
// Availability does not silently enable a user's native RAW correction switch.
BOOL LensPlanAllowsLiveNativeCorrection(NSDictionary *plan, NSDictionary *live);
