#pragma once
#import <Foundation/Foundation.h>
#import <math.h>
// Limited to the verified Panasonic LX3 RW2 tag layout. Preview dimensions,
// canvas aspect, JPEG/XMP crops and 35mm focal estimates are not mode evidence.
static NSDictionary*LensCaptureModeEvidence(NSDictionary*tags){
 if(![tags isKindOfClass:NSDictionary.class])return nil;
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
