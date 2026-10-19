#import "LensHostCompatibility.h"
#import "LensNativeState.h"
int main(void){@autoreleasepool{
 for(NSString*version in @[@"4.3",@"4.3.1",@"4.4",@"5",@"10.0"]){if(!LensHostVersionSupported(version))return 1;}
 for(NSString*version in @[@"4.2.99",@"4.3beta",@"",@"4..3",@"-4.3"]){if(LensHostVersionSupported(version))return 2;}
 NSString*base=@"/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks";
 for(NSString*name in @[@"PTFoundation",@"PXMEngine",@"PXMKit"]){NSString*path=[base stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.framework/Versions/A/%@",name,name]];if(!dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_GLOBAL)){fprintf(stderr,"%s\n",dlerror());return 3;}}
 NSDictionary*contract=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Compatibility/Pixelmator-4.3.json"] options:NSJSONReadingMutableContainers error:nil];
 NSDictionary*report=LensInspectHostCompatibility(contract,@"4.3",NO);if(![report[@"passed"]boolValue]){NSLog(@"%@",report);return 4;}
 if(![LensInspectHostCompatibility(contract,@"4.4",NO)[@"passed"]boolValue]||[LensInspectHostCompatibility(contract,@"4.2",NO)[@"passed"]boolValue])return 5;
 NSMutableDictionary*changed=[contract mutableCopy];NSMutableDictionary*groups=[contract[@"requiredHostSymbols"]mutableCopy];groups[groups.allKeys.firstObject]=@[@"$sLensDockMissingRequiredInterface"];changed[@"requiredHostSymbols"]=groups;
 if([LensInspectHostCompatibility(changed,@"4.3",NO)[@"passed"]boolValue])return 6;
 if(LensHostValueLayout("$s12PTFoundation15PTRawParametersVMa",288,288))return 7;
 NSData*empty=[@"[1,{\"w\":[],\"o\":1,\"ctx\":[1,{\"cs\":[1,{\"map\":{}}]}]}]" dataUsingEncoding:NSUTF8StringEncoding];id effects=LensEffectsFromJSON(empty);
 if(!effects||!LensEffectsEquivalent(empty,LensEffectsJSON(effects,nil)))return 8;
 NSMutableDictionary*r=[report mutableCopy];r[@"effectsRoundtrip"]=@YES;r[@"missingInterfaceRejected"]=@YES;r[@"changedValueLayoutRejected"]=@YES;r[@"futureVersionEligibilityTested"]=@YES;r[@"futureRuntimeActuallyTested"]=@NO;
 [[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"Build/Tests/host-compatibility-verification.json" atomically:YES];
 puts("Generic host versions, current 19 exports and value layouts, effects roundtrip and negative interface/layout checks passed; future runtimes not claimed.");return 0;
}}
