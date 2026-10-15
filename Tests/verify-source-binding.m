#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "LensCorrectionSettings.h"
#import "LensNativeState.h"

int main(){@autoreleasepool{
 if(!dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL))return 2;
 NSDictionary *record=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Tests/Fixtures/Nikon-binding.json"] options:0 error:nil];
 // Identity and RAW parameters come from the actual exported Nikon fixture.
 // Geometry here is a small serialization fixture, not an optical validation.
 NSDictionary *live=@{@"sourceInformation":@{@"rawSHA256":record[@"rawSHA256"],@"byteCount":record[@"rawBytes"],@"typeIdentifier":@"com.nikon.raw-image"},@"rawParameters":record[@"rawParameters"],@"width":@4,@"height":@4,@"scale":@[@1,@1],@"angle":@0,@"workingTransfer":@"encoded_sRGB",@"colorSpaceName":@"kCGColorSpaceSRGB",@"identifier":@"first-layer"};
 NSDictionary *binding=LensCorrectionSourceBinding(live);if(!binding||binding[@"identifier"]||!LensCorrectionSourceMatches(binding,live))return 3;
 NSMutableDictionary *renamed=[live mutableCopy];renamed[@"identifier"]=@"duplicated-layer";if(!LensCorrectionSourceMatches(binding,renamed))return 4;
 NSMutableDictionary *replaced=[live mutableCopy],*source=[live[@"sourceInformation"]mutableCopy];source[@"rawSHA256"]=@"152382ce4dbf644899d12b41b4c577f07638aa3ec5745ac344c36bad93826125";replaced[@"sourceInformation"]=source;if(LensCorrectionSourceMatches(binding,replaced))return 5;
 NSMutableDictionary *edited=[live mutableCopy];NSMutableArray *parameters=[live[@"rawParameters"]mutableCopy];NSMutableDictionary *values=[parameters[1]mutableCopy];values[@"exposureBias"]=@1;parameters[1]=values;edited[@"rawParameters"]=parameters;if(LensCorrectionSourceMatches(binding,edited))return 6;
 NSMutableDictionary *scaled=[live mutableCopy];scaled[@"scale"]=@[@2,@2];if(LensCorrectionSourceMatches(binding,scaled))return 7;
 if(LensCorrectionSourceMatches(nil,live)||LensCorrectionSourceBinding(@{}))return 8;
 NSDictionary *plan=@{@"report":@{@"width":@4,@"height":@4,@"workingTransfer":@"encoded_sRGB"},@"liveFingerprint":live};
 NSDictionary *settings=@{@"distortionEnabled":@NO,@"tcaEnabled":@NO,@"vignettingEnabled":@NO,@"distortionStrength":@90,@"tcaStrength":@100,@"vignettingStrength":@50};
 NSData *envelope=[NSData dataWithContentsOfFile:@"Build/Tests/native-effects-template.json"];
 id effects=LensEffectsForCorrectionPlan(plan,envelope,settings,nil,nil);if(!effects)return 9;
 id restored=LensEffectsFromJSON(LensEffectsJSON(effects,nil));NSDictionary *profile=LensSavedCorrectionProfile(restored);
 if(![profile[@"sourceBinding"]isEqual:binding]||profile[@"liveFingerprint"]||!LensCorrectionSourceMatches(profile[@"sourceBinding"],live))return 10;
 NSDictionary *sony=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Tests/Fixtures/A6000-reopen-binding.json"] options:0 error:nil];
 if(!sony||!LensCorrectionSourceMatches(sony[@"savedBinding"],sony[@"reopenedFingerprint"]))return 11;
 // Reopening can recompute derived white-balance chromaticities by a few
 // float ULPs. Actual temperature, tint, controls and source must stay strict.
 for(NSString *key in @[@"nt",@"nT",@"b",@"lc",@"BS",@"cx",@"cy"]){
  NSMutableDictionary *changed=[sony[@"reopenedFingerprint"]mutableCopy];
  NSMutableArray *raw=[changed[@"rawParameters"]mutableCopy];NSMutableDictionary *fields=[raw[1]mutableCopy];
  fields[key]=@([fields[key]doubleValue]+([key isEqual:@"cx"]||[key isEqual:@"cy"]?.00001:1));raw[1]=fields;changed[@"rawParameters"]=raw;
  if(LensCorrectionSourceMatches(sony[@"savedBinding"],changed))return 12;
 }
 NSDictionary *report=@{@"usesVerifiedRAWIdentityAndParameters":@YES,@"roundtripPreservesBinding":@YES,@"layerIdentifierExcluded":@YES,@"rejectsReplacedSource":@YES,@"rejectsChangedRAWParameters":@YES,@"rejectsChangedScale":@YES,@"rejectsMissingBinding":@YES,@"rawSHA256":record[@"rawSHA256"]};
 [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/source-binding-verification.json" atomically:YES];puts("Persistent source binding roundtrip and state guards passed.");
}}
