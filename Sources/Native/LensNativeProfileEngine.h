#import <Foundation/Foundation.h>
// Reads metadata only. Does not develop RAW pixels.
NSDictionary *LensReadRawMetadata(NSURL *rawURL, NSURL *exiftoolURL, NSError **error);
// Public Apple RAW correction capability for this image; never renders pixels.
NSDictionary *LensReadNativeCorrectionSupport(NSURL *rawURL);
// Reads only original, grouped RW2 metadata fields for capture-mode evidence.
NSDictionary *LensReadRawCaptureMetadata(NSURL *rawURL, NSURL *exiftoolURL, NSError **error);
// Enumerates content-addressed camera modes and compatible calibrations. A
// manual selection in metadata["LensDockProfileSelection"] is revalidated on
// every plan generation; names, array order and saved indices are insufficient.
NSDictionary *LensNativeProfileCandidates(NSDictionary *metadata, NSURL *databaseURL, NSURL *libraryURL, NSError **error);
// Native Lensfun matching and profile gain data, independent of Python/Lightroom.
NSDictionary *LensNativeProfilePlan(NSDictionary *metadata, NSURL *databaseURL, NSURL *libraryURL, NSUInteger width, NSUInteger height, NSError **error);

NSDictionary *LensNativeProfilePlanIncludingGeometry(NSDictionary *metadata, NSURL *databaseURL, NSURL *libraryURL, NSUInteger width, NSUInteger height, NSError **error);
NSDictionary *LensNativeProfilePlanFullGeometry(NSDictionary *metadata, NSURL *databaseURL, NSURL *libraryURL, NSUInteger width, NSUInteger height, NSError **error);
NSDictionary *LensCompactGeometryPlan(NSDictionary *fullPlan, double tolerancePixels, NSError **error);
NSDictionary *LensCompactGainPlan(NSDictionary *fullPlan, double toleranceGain, NSError **error);
