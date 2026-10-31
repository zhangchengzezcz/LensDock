#import "LensSonyGeometry.h"
#import <CoreImage/CoreImage.h>

// Explicit-frame image primitive only. Does not identify/verify a manufacturer
// frame, choose an automatic profile, read a RAW or write a document.
double LensSonyGeometryCropScale(const LensSonyGeometryTransform*transform,CGSize size);
CGRect LensSonyGeometrySourceROI(const LensSonyGeometryTransform*transform,CGRect extent,CGRect request,double cropScale);
CIImage*LensSonyExplicitGeometryImage(CIImage*input,NSDictionary*source,LensSonyExplicitPixelFrame frame,double distortionStrength,double tcaStrength,BOOL constrainEdges,NSError**error);
