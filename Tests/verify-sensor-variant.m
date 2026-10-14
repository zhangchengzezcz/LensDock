#import "LensNativeProfileEngine.h"
#import <math.h>
int main(){@autoreleasepool{
 NSURL*here=[NSURL fileURLWithPath:@"Build/Tests" isDirectory:YES],*db=[here URLByAppendingPathComponent:@"resources/db"],*lib=[here URLByAppendingPathComponent:@"lib/liblensfun.0.3.4.dylib"];NSError*error=nil;
 NSArray*cases=@[
 @{@"Make":@"Olympus Imaging Corp.",@"Model":@"E-M5",@"LensModel":@"Sigma 30mm f/2.8 EX DN",@"FocalLength":@30,@"FNumber":@2.8,@"expectedCrop":@2},
 @{@"Make":@"Sony",@"Model":@"NEX-3",@"LensModel":@"Sigma 30mm f/2.8 EX DN",@"FocalLength":@30,@"FNumber":@2.8,@"expectedCrop":@1.534},
 @{@"Make":@"Pentax",@"Model":@"Pentax K-500",@"LensModel":@"smc Pentax DA* 60-250mm f/4 [IF] SDM",@"FocalLength":@60,@"FNumber":@4,@"expectedCrop":@1.534},
 @{@"Make":@"Generic",@"Model":@"Crop-factor 1.0 (Full Frame)",@"LensModel":@"smc Pentax DA* 60-250mm f/4 [IF] SDM",@"FocalLength":@60,@"FNumber":@4,@"expectedCrop":@1},
 @{@"Make":@"Nikon Corporation",@"Model":@"Nikon D5200",@"LensModel":@"Tamron AF 70-300mm f/4-5.6 LD Macro 1:2",@"FocalLength":@70,@"FNumber":@4,@"expectedCrop":@1.53},
 @{@"Make":@"Canon",@"Model":@"Canon EOS 40D",@"LensModel":@"Tamron AF 18-200mm f/3.5-6.3 XR Di II LD Aspherical (IF) Macro",@"FocalLength":@18,@"FNumber":@3.5,@"expectedCrop":@1.611}];
 NSMutableArray*results=[NSMutableArray new];
 for(NSDictionary*m in cases){error=nil;NSDictionary*p=LensNativeProfilePlan(m,db,lib,64,48,&error);if(!p){NSLog(@"%@ %@",m[@"Model"],error);return 1;}NSDictionary*r=p[@"report"];if(fabs([r[@"interpolatedCalibration"][@"lensCropFactor"]doubleValue]-[m[@"expectedCrop"]doubleValue])>1e-5)return 2;[results addObject:@{@"camera":m[@"Model"],@"lens":m[@"LensModel"],@"lensCrop":r[@"interpolatedCalibration"][@"lensCropFactor"],@"cameraCrop":r[@"interpolatedCalibration"][@"cameraCropFactor"],@"method":r[@"matchingIdentityMethod"]}];}
 // Separate raw names that share an exact display alias model different sensor
 // calibrations. Never merge two near crop candidates or different projections.
 NSURL*temp=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:temp withIntermediateDirectories:YES attributes:nil error:nil];NSURL*xml=[temp URLByAppendingPathComponent:@"variants.xml"];
 NSString*(^lens)(NSString*,NSString*,NSString*)=^NSString*(NSString*raw,NSString*crop,NSString*type){return [NSString stringWithFormat:@"<lens><maker>LensDock Test</maker><model>%@</model><model lang=\"en\">Known 50mm f/2</model><mount>A</mount><cropfactor>%@</cropfactor><type>%@</type><calibration><distortion model=\"poly3\" focal=\"50\" k1=\"0.01\"/></calibration></lens>",raw,crop,type];};
 NSString*(^writeDB)(NSString*,NSString*,NSString*)=^NSString*(NSString*cameraCrop,NSString*secondCrop,NSString*secondType){return [NSString stringWithFormat:@"<lensdatabase version=\"1\"><camera><maker>LensDock Test</maker><model>Known Camera</model><mount>A</mount><cropfactor>%@</cropfactor></camera>%@%@</lensdatabase>",cameraCrop,lens(@"FIRST 50mm f/2",@"1.5",@"rectilinear"),lens(@"SECOND 50mm f/2",secondCrop,secondType)];};
 NSDictionary*m=@{@"Make":@"LensDock Test",@"Model":@"Known Camera",@"LensModel":@"Known 50mm f/2",@"FocalLength":@50,@"FNumber":@2};
 [writeDB(@"1.5",@"1.53",@"rectilinear")writeToURL:xml atomically:YES encoding:NSUTF8StringEncoding error:nil];if(LensNativeProfilePlan(m,temp,lib,64,48,nil))return 3;
 [writeDB(@"1.5",@"1.5",@"fisheye")writeToURL:xml atomically:YES encoding:NSUTF8StringEncoding error:nil];if(LensNativeProfilePlan(m,temp,lib,64,48,nil))return 4;
 [writeDB(@"2",@"1.1",@"rectilinear")writeToURL:xml atomically:YES encoding:NSUTF8StringEncoding error:nil];if(LensNativeProfilePlan(m,temp,lib,64,48,nil))return 5;
 [NSFileManager.defaultManager removeItemAtURL:temp error:nil];
 NSDictionary*out=@{@"scope":@"Database-based exact identity and sensor calibration routing, not real RAW optical accuracy",@"matchingSensorVariantsSelected":@YES,@"twoNearSensorVariantsRejected":@YES,@"differentProjectionConflictRejected":@YES,@"noSuitableSensorClassRejected":@YES,@"cases":results};
 [[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil]writeToURL:[here URLByAppendingPathComponent:@"sensor-variant-verification.json"] atomically:YES];puts("Exact lens sensor variants and crop/projection ambiguity boundaries passed.");
}}
