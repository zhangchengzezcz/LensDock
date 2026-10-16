#pragma once
#import <CoreImage/CoreImage.h>
// Numeric calibration only: one replicated node surrounds the original field.
// Original data remains immutable; Core Image requests bounded tiles lazily.
CIImage *LensCalibrationImage(NSData *data,NSUInteger width,NSUInteger height,NSUInteger bytesPerPixel,CIFormat format);
CGRect LensCalibrationROI(CGRect request,CGRect imageExtent,NSUInteger imageWidth,NSUInteger imageHeight,NSUInteger mapWidth,NSUInteger mapHeight);
CIImage *LensApplyCalibrationKernel(CIKernel *kernel,CGRect extent,CIKernelROICallback callback,NSArray *arguments);
