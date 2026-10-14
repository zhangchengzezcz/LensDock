#import <Foundation/Foundation.h>
// Reads metadata only. Does not develop RAW pixels.
NSDictionary *LensReadRawMetadata(NSURL *rawURL, NSURL *exiftoolURL, NSError **error);
// Public Apple RAW correction capability for this image; never renders pixels.
NSDictionary *LensReadNativeCorrectionSupport(NSURL *rawURL);
// Native Lensfun matching and profile gain data, independent of Python/Lightroom.
NSDictionary *LensNativeProfilePlan(NSDictionary *metadata, NSURL *databaseURL, NSURL *libraryURL, NSUInteger width, NSUInteger height, NSError **error);

NSDictionary *LensNativeProfilePlanIncludingGeometry(NSDictionary *metadata, NSURL *databaseURL, NSURL *libraryURL, NSUInteger width, NSUInteger height, NSError **error);
NSDictionary *LensNativeProfilePlanFullGeometry(NSDictionary *metadata, NSURL *databaseURL, NSURL *libraryURL, NSUInteger width, NSUInteger height, NSError **error);
NSDictionary *LensCompactGeometryPlan(NSDictionary *fullPlan, double tolerancePixels, NSError **error);
