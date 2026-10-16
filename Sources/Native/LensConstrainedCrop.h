#pragma once
#import <Foundation/Foundation.h>

// Conservative, aspect-preserving centre crop, expressed as a fraction of the
// corrected frame. Bounds come only from the actual saved calibration fields.
// Applying it inside the effect changes framing, never RAW bytes or canvas size.
NSDictionary *LensConstrainedCrop(NSDictionary *plan, NSDictionary *settings, NSError **error);
