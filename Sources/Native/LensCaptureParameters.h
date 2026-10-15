#import <Foundation/Foundation.h>
#import <math.h>
#import "LensFocusDistanceEvidence.h"

static inline NSNumber *LensPositiveCaptureNumber(id value) {
 if(![value respondsToSelector:@selector(doubleValue)])return nil;
 double n=[value doubleValue];return isfinite(n)&&n>0?@(n):nil;
}

// Absence is meaningful: clearing an unknown aperture/distance must not revive
// the original value when a saved effect is reopened.
static inline NSDictionary *LensMetadataRestoringCaptureParameters(NSDictionary *original, NSDictionary *saved) {
 NSMutableDictionary *metadata=[original mutableCopy];
 for(NSString *key in @[@"FocalLength",@"FNumber",@"FocusDistance",@"SubjectDistance",@"FocusDistanceRangeMeters"]){
  [metadata removeObjectForKey:key];if(saved[key])metadata[key]=saved[key];
 }
 return metadata;
}

// Edit only the effective interpolation metadata. The caller retains the
// original metadata separately and never writes these values into the RAW.
static inline NSDictionary *LensMetadataWithCaptureParameterText(NSDictionary *original, NSDictionary *current, NSArray<NSString *> *fields, NSLocale *locale, BOOL reset, NSError **error) {
 NSMutableDictionary *metadata=[original mutableCopy];
 if(!metadata)return nil;
 [metadata removeObjectForKey:@"LensDockProfileSelection"];
 if(current[@"LensDockProfileSelection"])metadata[@"LensDockProfileSelection"]=current[@"LensDockProfileSelection"];
 if(reset)return metadata;
 NSString *message=nil;
 NSMutableArray *values=[NSMutableArray new];
 if(fields.count!=3)message=@"请输入焦距，并核对光圈与对焦距离。";
 NSNumberFormatter *formatter=[NSNumberFormatter new];formatter.numberStyle=NSNumberFormatterDecimalStyle;formatter.locale=locale?:NSLocale.currentLocale;formatter.usesGroupingSeparator=NO;formatter.lenient=NO;
 if(!message)for(NSUInteger i=0;i<3;i++){
  NSString *text=[fields[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if(!text.length){[values addObject:NSNull.null];continue;}
  id number=nil;NSRange range=NSMakeRange(0,text.length);
  BOOL parsed=[formatter getObjectValue:&number forString:text range:&range error:nil];
  double value=[number isKindOfClass:NSNumber.class]?[number doubleValue]:NAN;
  if(!parsed||range.location!=0||range.length!=text.length||!isfinite(value)||value<=0||(i==1&&(value<.5||value>128))||(i==2&&value>100000)){
   message=@"请输入有效数字：焦距大于 0、光圈 0.5–128、距离大于 0 且至多 100000 m。未知光圈与距离可留空。";break;
  }
  [values addObject:number];
 }
 if(!message&&values[0]==NSNull.null)message=@"原片未记录焦距。请填写实际拍摄焦距，不会从镜头范围猜测。";
 if(message){if(error)*error=[NSError errorWithDomain:@"LensDockCaptureParameters" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];return nil;}
 for(NSString *key in @[@"FocalLength",@"FNumber",@"FocusDistance",@"SubjectDistance",@"FocusDistanceRangeMeters"])[metadata removeObjectForKey:key];
 NSArray *keys=@[@"FocalLength",@"FNumber",@"FocusDistance"];
 for(NSUInteger i=0;i<3;i++)if(values[i]!=NSNull.null)metadata[keys[i]]=values[i];
 // Leaving the auto-filled far-distance fallback unchanged while adjusting
 // another field must not manufacture a manually measured 1000 m distance.
 NSDictionary *effective=current?:original;
 if(values[2]!=NSNull.null&&[values[2]doubleValue]==1000&&!LensPositiveCaptureNumber(effective[@"FocusDistance"])&&!LensPositiveCaptureNumber(effective[@"SubjectDistance"])){
  [metadata removeObjectForKey:@"FocusDistance"];
  NSDictionary *range=LensRecordedFocusDistanceRange(effective);if(range)metadata[@"FocusDistanceRangeMeters"]=range;
 }
 return metadata;
}

static inline NSArray *LensCaptureParameterDisplayValues(NSDictionary *metadata) {
 return @[LensPositiveCaptureNumber(metadata[@"FocalLength"])?:NSNull.null,
          LensPositiveCaptureNumber(metadata[@"FNumber"])?:NSNull.null,
          LensPositiveCaptureNumber(metadata[@"FocusDistance"])?:LensPositiveCaptureNumber(metadata[@"SubjectDistance"])?:@1000];
}
