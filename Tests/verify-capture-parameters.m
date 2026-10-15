#import "LensCaptureParameters.h"
#import "LensNativeProfileEngine.h"
#import "LensCorrectionSettings.h"
#import "LensNativeState.h"
#import <dlfcn.h>

int main(){@autoreleasepool{
 NSURL*here=[NSURL fileURLWithPath:@"Build/Tests" isDirectory:YES],*lib=[here URLByAppendingPathComponent:@"lib/liblensfun.0.3.4.dylib"],*db=[here URLByAppendingPathComponent:@"resources/db"];
 NSLocale*english=[[NSLocale alloc]initWithLocaleIdentifier:@"en_US"],*german=[[NSLocale alloc]initWithLocaleIdentifier:@"de_DE"];
 NSMutableArray*automaticRAWChecks=[NSMutableArray new];
 for(NSDictionary*fixture in @[@{@"name":@"Canon40D.CR2",@"focal":@17,@"aperture":@4},@{@"name":@"NikonD70.NEF",@"focal":@50,@"aperture":@7.1},@{@"name":@"CanonR50V.CR3",@"focal":@25,@"aperture":@5.6}]){
  NSURL*raw=[NSURL fileURLWithPath:[@"Tests/PrivateRAW" stringByAppendingPathComponent:fixture[@"name"]]];if(![NSFileManager.defaultManager fileExistsAtPath:raw.path])continue;
  NSError*readError=nil;NSDictionary*metadata=LensReadRawMetadata(raw,[here URLByAppendingPathComponent:@"resources/exiftool/exiftool"],&readError);
  NSArray*defaults=LensCaptureParameterDisplayValues(metadata);NSDictionary*automaticPlan=LensNativeProfilePlan(metadata,db,lib,64,48,&readError);
  if(!metadata||!automaticPlan||fabs([defaults[0]doubleValue]-[fixture[@"focal"]doubleValue])>1e-6||fabs([defaults[1]doubleValue]-[fixture[@"aperture"]doubleValue])>1e-6||metadata[@"LensDockProfileSelection"]||[automaticPlan[@"parameterOverrides"]boolValue])return 13;
  BOOL recordedDistance=LensPositiveCaptureNumber(metadata[@"FocusDistance"])||LensPositiveCaptureNumber(metadata[@"SubjectDistance"]);
  if([fixture[@"name"]isEqual:@"NikonD70.NEF"]&&(!recordedDistance||fabs([defaults[2]doubleValue]-2.37137370566166)>1e-6))return 14;
  [automaticRAWChecks addObject:@{@"fixtureType":raw.pathExtension,@"automaticallyReadFocalMM":defaults[0],@"automaticallyReadAperture":defaults[1],@"distanceRecorded":@(recordedDistance),@"automaticPlanWithoutManualInput":@YES}];
 }
 NSDictionary*original=@{@"Make":@"NIKON CORPORATION",@"Model":@"NIKON D70",@"LensModel":@"AF-S DX Zoom-Nikkor 18-70mm f/3.5-4.5G IF-ED",@"FNumber":@7.1,@"SubjectDistance":@8};
 NSDictionary*c=LensNativeProfileCandidates(original,db,lib,nil);if(![c[@"automaticCameraID"]length]||![c[@"automaticLensID"]length]||LensNativeProfilePlan(original,db,lib,64,48,nil))return 1;
 NSDictionary*selection=@{@"cameraID":c[@"automaticCameraID"],@"lensID":c[@"automaticLensID"]};NSMutableDictionary*pending=[original mutableCopy];pending[@"LensDockProfileSelection"]=selection;
 NSError*error=nil;NSDictionary*m=LensMetadataWithCaptureParameterText(original,pending,@[@"50",@"",@""],english,NO,&error);
 if(!m||m[@"FNumber"]||m[@"SubjectDistance"]||m[@"FocusDistance"]||original[@"FocalLength"]||![original[@"FNumber"]isEqual:@7.1]||![m[@"LensDockProfileSelection"]isEqual:selection])return 2;
 NSDictionary*p=LensNativeProfilePlanFullGeometry(m,db,lib,64,48,&error);if(!p||![p[@"report"][@"distortionProfileAvailable"]boolValue]||![p[@"report"][@"tcaProfileAvailable"]boolValue]||[p[@"report"][@"vignettingProfileAvailable"]boolValue]||![p[@"report"][@"distance_source"]isEqual:@"infinity_fallback"])return 3;
 for(NSString*invalid in @[@"",@"0",@"-1",@"50 mm",@"NaN",@"inf",@"1e309"]){error=nil;if(LensMetadataWithCaptureParameterText(original,pending,@[invalid,@"",@""],english,NO,&error)||!error)return 4;}
 for(NSArray*invalid in @[@[@"50",@"0",@""],@[@"50",@"0.49",@""],@[@"50",@"129",@""],@[@"50",@"4",@"0"],@[@"50",@"4",@"100001"]])if(LensMetadataWithCaptureParameterText(original,pending,invalid,english,NO,nil))return 5;
 NSDictionary*localized=LensMetadataWithCaptureParameterText(original,pending,@[@"35,5",@"5,6",@"2,5"],german,NO,nil);if(fabs([localized[@"FocalLength"]doubleValue]-35.5)>1e-9||fabs([localized[@"FNumber"]doubleValue]-5.6)>1e-9||fabs([localized[@"FocusDistance"]doubleValue]-2.5)>1e-9)return 6;
 NSDictionary*full=LensMetadataWithCaptureParameterText(original,m,@[@"50",@"7.1",@"8"],english,NO,nil),*fullPlan=LensNativeProfilePlan(full,db,lib,64,48,nil);if(![fullPlan[@"report"][@"vignettingProfileAvailable"]boolValue])return 7;
 if(!dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL))return 8;
 NSMutableDictionary*plan=[p mutableCopy],*report=[p[@"report"]mutableCopy];report[@"workingTransfer"]=@"encoded_sRGB";plan[@"report"]=report;plan[@"metadata"]=m;plan[@"baseMetadata"]=original;plan[@"parameterOverrides"]=@YES;
 NSDictionary*settings=@{@"distortionEnabled":@YES,@"tcaEnabled":@YES,@"vignettingEnabled":@NO,@"distortionStrength":@100,@"tcaStrength":@100,@"vignettingStrength":@0};NSData*envelope=[NSData dataWithContentsOfURL:[here URLByAppendingPathComponent:@"native-effects-template.json"]];id effects=LensEffectsForCorrectionPlan(plan,envelope,settings,nil,&error);NSDictionary*saved=LensSavedCorrectionProfile(LensEffectsFromJSON(LensEffectsJSON(effects,nil)));
 if(!saved||![saved[@"baseMetadata"]isEqual:original]||![saved[@"parameterOverrides"]boolValue]||![saved[@"metadata"][@"LensDockProfileSelection"]isEqual:selection])return 9;
 NSDictionary*reopened=LensMetadataRestoringCaptureParameters(original,saved[@"metadata"]);if(reopened[@"FNumber"]||reopened[@"SubjectDistance"]||reopened[@"FocusDistance"]||![reopened[@"FocalLength"]isEqual:@50])return 10;
 NSDictionary*reset=LensMetadataWithCaptureParameterText(original,saved[@"metadata"],@[],english,YES,nil);if(reset[@"FocalLength"]||![reset[@"FNumber"]isEqual:original[@"FNumber"]]||![reset[@"SubjectDistance"]isEqual:original[@"SubjectDistance"]]||![reset[@"LensDockProfileSelection"]isEqual:selection])return 11;
 NSArray*display=LensCaptureParameterDisplayValues(m);if(![display[0]isEqual:@50]||display[1]!=NSNull.null||![display[2]isEqual:@1000])return 12;
 NSDictionary*out=@{@"scope":@"Capture parameter validation, actual local RAW automatic metadata read when supplied, native profile interpolation and effect serialization; not host GUI or RAW optical accuracy",@"automaticRAWMetadataChecks":automaticRAWChecks,@"privateRAWChecksSkipped":@(automaticRAWChecks.count==0),@"missingFocalNeverGuessed":@YES,@"manualSelectionSurvivesMissingFocal":@YES,@"blankApertureDisablesVignettingOnly":@YES,@"blankDistanceUsesExplicitFarDistanceFallback":@YES,@"unknownValuesRemainAbsentAfterSavedMetadataRestore":@YES,@"localizedDecimalsAccepted":@YES,@"partialAndNonFiniteInputsRejected":@YES,@"resetRestoresOriginalCaptureWithoutDroppingProfileChoice":@YES,@"originalMetadataUnchanged":@YES};
 [[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil]writeToURL:[here URLByAppendingPathComponent:@"capture-parameters-verification.json"] atomically:YES];puts("Missing capture parameters, optional aperture, localization, persistence and reset passed.");
}}
