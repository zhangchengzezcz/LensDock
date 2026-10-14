#import <Foundation/Foundation.h>
#import <math.h>

// Identity is a mathematical property of the recorded optical model, not a
// guess from scene shapes. Missing/unsupported models must never create a warp.
static inline BOOL LensGeometryCalibrationNeeded(NSDictionary *report,NSString *kind){
 if(![report[[kind stringByAppendingString:@"ProfileAvailable"]]boolValue])return NO;
 NSDictionary *calibration=report[@"interpolatedCalibration"][kind];NSArray *terms=calibration[@"terms"];
 int model=[calibration[@"model"]intValue];NSUInteger count=0;BOOL tca=[kind isEqual:@"tca"];
 if(tca)count=model==1?2:model==2?6:0;else count=model==1?1:model==2?2:model==3?3:0;
 if(!count||![terms isKindOfClass:NSArray.class]||terms.count<count)return NO;
 BOOL nonIdentity=NO;
 for(NSUInteger i=0;i<count;i++){
  if(![terms[i]isKindOfClass:NSNumber.class]||!isfinite([terms[i]doubleValue]))return NO;
  double identity=tca&&i<2?1:0;if([terms[i]doubleValue]!=identity)nonIdentity=YES;
 }
 NSNumber *measured=report[[kind stringByAppendingString:@"CorrectionNeeded"]];
 return nonIdentity&&(!measured||[measured boolValue]);
}
static inline double LensDisplayCorrectionAmount(NSDictionary *report,NSUInteger index,double strength){
 strength=fmax(0,fmin(200,strength));
 if(index==0)return [report[@"distortionPeakShiftPercent"]doubleValue]*strength/100.;
 if(index==1)return [report[@"tcaPeakSeparationPixels"]doubleValue]*strength/100.;
 double peak=[report[@"gain_range"][1]doubleValue];return peak>1?log2(1+strength/100.*(peak-1)):0;
}
static inline double LensCorrectionStrengthFromAmount(NSDictionary *report,NSUInteger index,double amount){
 if(!isfinite(amount)||amount<=0)return 0;double basis=LensDisplayCorrectionAmount(report,index,100),strength=0;
 if(index<2)strength=basis>0?amount/basis*100:0;
 else{double peak=[report[@"gain_range"][1]doubleValue];strength=peak>1?expm1(amount*M_LN2)/(peak-1)*100:0;}
 return fmax(0,fmin(200,strength));
}
