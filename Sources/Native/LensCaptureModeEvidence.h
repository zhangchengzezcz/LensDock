#pragma once
#import <Foundation/Foundation.h>
#import <math.h>
// Original RAW evidence only. Preview/canvas dimensions are not mode evidence.
static NSDictionary*LensCaptureModeEvidence(NSDictionary*tags){
 if(![tags isKindOfClass:NSDictionary.class])return nil;
 // FinePix F810 owner's manual BL00411-200(1), printed p91: widescreen
 // and digital zoom are unavailable in CCD-RAW. Require the RAF header model
 // as well as embedded EXIF; do not apply this rule to JPEG/DNG or other bodies.
 if([tags[@"File:FileType"]isEqual:@"RAF"]&&[tags[@"IFD0:Make"]isKindOfClass:NSString.class]&&[[tags[@"IFD0:Make"]uppercaseString]isEqual:@"FUJIFILM"]&&
    [tags[@"IFD0:Model"]isKindOfClass:NSString.class]&&[[tags[@"IFD0:Model"]uppercaseString]isEqual:@"FINEPIX F810"]&&
    [tags[@"LensDock:RAFHeaderModel"]isKindOfClass:NSString.class]&&[[tags[@"LensDock:RAFHeaderModel"]uppercaseString]isEqual:@"FINEPIX F810"]){
  id zoom=tags[@"ExifIFD:DigitalZoomRatio"];
  if(zoom&&(![zoom isKindOfClass:NSNumber.class]||!isfinite([zoom doubleValue])||[zoom doubleValue]<0||[zoom doubleValue]>1.00001))return nil;
  return @{@"cameraModel":@"FinePix F810",@"variant":@"standard",@"aspectRatio":@(4.0/3),@"source":@"RAF header and camera CCD-RAW mode restriction (owner manual p91)",@"cameraSelectionMethod":@"raw-format-documented-camera-mode"};
 }
 if(![tags[@"File:FileType"]isEqual:@"RW2"]||![tags[@"IFD0:Model"]isKindOfClass:NSString.class]||[[tags[@"IFD0:Model"]uppercaseString]compare:@"DMC-LX3"]!=NSOrderedSame||![tags[@"IFD0:Make"]isKindOfClass:NSString.class]||![[tags[@"IFD0:Make"]lowercaseString]hasPrefix:@"panasonic"])return nil;
 id zoom=tags[@"ExifIFD:DigitalZoomRatio"];if(zoom&&(![zoom isKindOfClass:NSNumber.class]||!isfinite([zoom doubleValue])||[zoom doubleValue]<0||[zoom doubleValue]>1.00001))return nil;
 id conversion=tags[@"Panasonic:ConversionLens"];if(conversion&&(![conversion isKindOfClass:NSNumber.class]||[conversion intValue]!=1||[conversion doubleValue]!=1))return nil;
 for(NSString*key in @[@"IFD0:CropTop",@"IFD0:CropLeft",@"IFD0:CropBottom",@"IFD0:CropRight"]){id value=tags[key];if(value&&(![value isKindOfClass:NSNumber.class]||[value doubleValue]!=0))return nil;}
 NSArray*keys=@[@"IFD0:SensorWidth",@"IFD0:SensorHeight",@"IFD0:SensorTopBorder",@"IFD0:SensorLeftBorder",@"IFD0:SensorBottomBorder",@"IFD0:SensorRightBorder"];double v[6];
 for(NSUInteger i=0;i<keys.count;i++){id value=tags[keys[i]];if(![value isKindOfClass:NSNumber.class])return nil;v[i]=[value doubleValue];if(!isfinite(v[i])||v[i]<0||v[i]>100000||floor(v[i])!=v[i])return nil;}
 if(v[0]<=0||v[1]<=0||v[2]>=v[4]||v[3]>=v[5]||v[4]>v[1]||v[5]>v[0])return nil;
 double width=v[5]-v[3],height=v[4]-v[2],ratio=width/height;NSString*variant=nil;double aspect=0;
 for(NSArray*mode in @[@[@"4:3",@(4.0/3)],@[@"3:2",@1.5],@[@"16:9",@(16.0/9)],@[@"1:1",@1]])if(fabs(ratio/[mode[1]doubleValue]-1)<=.005){if(variant)return nil;variant=mode[0];aspect=[mode[1]doubleValue];}
 if(!variant)return nil;
 return @{@"cameraModel":@"DMC-LX3",@"variant":variant,@"aspectRatio":@(aspect),@"activeWidth":@(width),@"activeHeight":@(height),@"source":@"RW2 IFD0 Sensor*Border"};
}
