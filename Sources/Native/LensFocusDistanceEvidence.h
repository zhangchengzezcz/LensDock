#pragma once
#import <Foundation/Foundation.h>
#import <math.h>

// Canon ShotInfo distances are metres after ExifTool ValueConv. 655.35 is
// the unsigned 16-bit infinity sentinel, not a finite measured distance.
// A range is evidence only: never turn its midpoint into FocusDistance.
static inline NSDictionary *LensCanonFocusDistanceRange(NSDictionary *grouped) {
 if(![grouped isKindOfClass:NSDictionary.class]||![grouped[@"IFD0:Make"]isKindOfClass:NSString.class]||[grouped[@"IFD0:Make"]caseInsensitiveCompare:@"Canon"]!=NSOrderedSame)return nil;
 id low=grouped[@"Canon:FocusDistanceLower"],high=grouped[@"Canon:FocusDistanceUpper"];
 if(![low isKindOfClass:NSNumber.class]||![high isKindOfClass:NSNumber.class])return nil;
 double lower=[low doubleValue],upper=[high doubleValue];
 if(!isfinite(lower)||!isfinite(upper)||lower<=0||lower>655.345||upper<lower||upper>655.35)return nil;
 return upper>655.345?@{@"lower":@(lower),@"upperUnbounded":@YES,@"source":@"Canon MakerNote FocusDistanceLower/Upper"}:@{@"lower":@(lower),@"upper":@(upper),@"upperUnbounded":@NO,@"source":@"Canon MakerNote FocusDistanceLower/Upper"};
}

static inline NSDictionary *LensRecordedFocusDistanceRange(NSDictionary *metadata) {
 id range=metadata[@"FocusDistanceRangeMeters"];if(![range isKindOfClass:NSDictionary.class]||![range[@"source"]isEqual:@"Canon MakerNote FocusDistanceLower/Upper"])return nil;
 id lower=range[@"lower"],upper=range[@"upper"],unbounded=range[@"upperUnbounded"];
 if(![lower isKindOfClass:NSNumber.class]||!isfinite([lower doubleValue])||[lower doubleValue]<=0||[lower doubleValue]>655.345||![unbounded isKindOfClass:NSNumber.class])return nil;
 if([unbounded boolValue])return upper?nil:range;
 if(![upper isKindOfClass:NSNumber.class]||!isfinite([upper doubleValue])||[upper doubleValue]<[lower doubleValue]||[upper doubleValue]>655.345)return nil;
 return range;
}

static inline NSString *LensFocusRangeDisplay(NSDictionary *metadata) {
 NSDictionary *range=LensRecordedFocusDistanceRange(metadata);if(!range)return nil;
 NSNumberFormatter *format=[NSNumberFormatter new];format.numberStyle=NSNumberFormatterDecimalStyle;format.usesGroupingSeparator=NO;format.maximumFractionDigits=4;
 NSString *lower=[format stringFromNumber:range[@"lower"]];
 return [range[@"upperUnbounded"]boolValue]?[NSString stringWithFormat:@"≥ %@ m",lower]:[NSString stringWithFormat:@"%@–%@ m",lower,[format stringFromNumber:range[@"upper"]]];
}

static inline NSString *LensFocusRangeFallbackNote(NSDictionary *metadata) {
 NSString *range=LensFocusRangeDisplay(metadata);
 return range?[NSString stringWithFormat:@"相机仅记录对焦范围 %@；不是单一实测距离。当前标定仍采用 1000 m 远距离回退。",range]:@"原片未记录对焦距离；1000 m 表示远距离标定回退，并非实测距离。";
}

static inline NSString *LensFocusDistanceTextForReport(NSDictionary *report) {
 if([report[@"distance_source"]isEqual:@"infinity_fallback"]){
  NSString *range=LensFocusRangeDisplay(report);
  return range?[NSString stringWithFormat:@"对焦范围 %@ · 远距标定",range]:@"对焦距离未记录，采用远距离标定";
 }
 NSNumberFormatter *format=[NSNumberFormatter new];format.numberStyle=NSNumberFormatterDecimalStyle;format.usesGroupingSeparator=NO;format.maximumFractionDigits=4;
 return [NSString stringWithFormat:@"对焦距离 %@ m",[format stringFromNumber:report[@"focus_distance_m"]]?:@"—"];
}
