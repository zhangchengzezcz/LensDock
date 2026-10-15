#import "LensNativeState.h"
#import "LensCorrectionSettings.h"
#import <dlfcn.h>
Class LensRegisterVignettingFilter(void);
// Read-only inspector for effects-data extracted from a locally saved PXD.
// It reports checks, never dumps archived pixels, bookmarks or RAW payloads.
int main(int argc,char**argv){@autoreleasepool{
 if(argc!=4)return 1;
 if(!dlopen("/Applications/Pixelmator Pro Creator Studio.app/Contents/Frameworks/PTFoundation.framework/Versions/A/PTFoundation",RTLD_NOW|RTLD_GLOBAL))return 2;
 LensRegisterVignettingFilter();NSDictionary*p=LensSavedCorrectionProfile(LensEffectsFromJSON([NSData dataWithContentsOfFile:@(argv[1])]));NSDictionary*before=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[2])] options:0 error:nil];if(!p||![before[@"raws"]count])return 3;
 NSDictionary*selection=p[@"metadata"][@"LensDockProfileSelection"],*matched=p[@"matchedProfile"],*settings=p[@"correctionSettings"];
 BOOL selected=[selection[@"cameraID"]isEqual:matched[@"matchedCameraProfileID"]]&&[selection[@"lensID"]isEqual:matched[@"matchedLensProfileID"]]&&[matched[@"manualProfileSelection"]isEqual:selection];
 BOOL source=[p[@"sourceBinding"][@"sourceInformation"][@"rawSHA256"]isEqual:before[@"raws"][0][@"sha256"]];
 BOOL original=p[@"baseMetadata"]&&!p[@"baseMetadata"][@"LensDockProfileSelection"];
 BOOL choices=[settings[@"distortionEnabled"]boolValue]&&[settings[@"tcaEnabled"]boolValue]&&![settings[@"vignettingEnabled"]boolValue];
 NSDictionary*out=@{@"scope":@"Readback of the GUI-saved Nikon PXD test copy",@"manualCameraAndLensIDsMatchStoredCalibration":@(selected),@"sourceBindingMatchesUnmodifiedRAWResource":@(source),@"baseRAWMetadataHasNoManualProfileOverride":@(original),@"distortionAndTCAEnabledVignettingOff":@(choices),@"metadataContainsSelection":@(selection!=nil),@"matchingMethod":matched[@"matchingIdentityMethod"]?:@"",@"matchedCamera":matched[@"camera"],@"matchedLens":matched[@"lens"],@"settings":settings,@"sourceSHA256":before[@"raws"][0][@"sha256"]};
 [[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@(argv[3]) atomically:YES];if(!selected||!source||!original||!choices)return 4;puts("GUI-saved PXD retains manual profile identities, independent choices and original RAW binding.");
}}
