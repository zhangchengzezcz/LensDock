#import "LensRecommendationPolicy.h"
#import <math.h>
#import "LensCalibrationEvidence.h"

BOOL LensPlanAllowsLiveNativeCorrection(NSDictionary *plan, NSDictionary *live) {
 if(!live)return NO;
 BOOL enabled=[live[@"rawParameters"][1][@"lc"]boolValue];
 NSDictionary*r=plan[@"report"],*native=r[@"nativeCorrectionSupport"];
 if([r[@"supplementalVignettingOnly"]boolValue])return [native[@"probeSucceeded"]boolValue]&&[native[@"lensCorrectionSupported"]boolValue]&&![plan[@"normalizedGeometryMapsLZFSE"]count];
 return !enabled;
}

NSDictionary *LensRecommendationPolicy(NSDictionary *plan) {
 NSDictionary *report=[plan[@"report"]isKindOfClass:NSDictionary.class]?plan[@"report"]:@{};
 NSDictionary *assessment=[plan[@"cornerAssessment"]isKindOfClass:NSDictionary.class]?plan[@"cornerAssessment"]:@{};
 BOOL calibrated=[report[@"vignettingProfileAvailable"] boolValue];
 BOOL needed=calibrated&&[report[@"vignettingCorrectionNeeded"] boolValue];
 if([report[@"supplementalVignettingOnly"]boolValue])return @{@"strengths":@[@0,@0,@0],@"vignettingAutomatic":@NO,@"vignettingMeasured":@NO,@"vignettingState":needed?@"native-supplement":@"native-no-independent-profile"};
 NSArray *curve=assessment[@"clippingFractionByStrengthPercent"];
 double previous=-1, budget=[assessment[@"highlightBudgetFraction"] doubleValue];
 BOOL measured=needed&&[curve isKindOfClass:NSArray.class]&&curve.count==201&&isfinite(budget)&&budget>0&&budget<=.005;
 if(measured)for(id value in curve){
  if(![value isKindOfClass:NSNumber.class]){measured=NO;break;}
  double fraction=[value doubleValue];
  if(!isfinite(fraction)||fraction<0||fraction>1||fraction<previous){measured=NO;break;}
  previous=fraction;
 }
 if(measured&&[curve[0] doubleValue]!=0)measured=NO;
 double proposed=[assessment[@"recommendedStrengthPercent"] doubleValue];
 if(![assessment[@"recommendedStrengthPercent"] isKindOfClass:NSNumber.class]||!isfinite(proposed)||proposed<0||proposed>100)measured=NO;
 BOOL trial=[assessment[@"sceneContentAmbiguous"] boolValue]||![assessment[@"consistentCornerFalloffObserved"] boolValue];
 int safe=0;
 if(measured)for(int i=0;i<=100;i++)if([curve[i] doubleValue]<=budget)safe=i;
 double strength=measured?MIN(proposed,MIN(safe,trial?50:100)):0;
 BOOL automatic=measured&&!trial&&strength>0&&[assessment[@"automaticRecommendedStrengthSuitable"] boolValue];
 NSString *state=!calibrated?@"missing-calibration":!needed?@"identity":!measured?@"unmeasured":strength==0?@"highlight-limited":trial?@"trial":@"recommended";
 return @{@"strengths":@[@(LensGeometryCalibrationNeeded(report,@"distortion")?100:0),@(LensGeometryCalibrationNeeded(report,@"tca")?100:0),@(strength)],
          @"vignettingAutomatic":@(automatic),@"vignettingState":state,@"vignettingMeasured":@(measured)};
}
