#import "LensNativeProfileEngine.h"
#import <math.h>
int main(){@autoreleasepool{
 NSURL*here=[NSURL fileURLWithPath:@"Build/Tests" isDirectory:YES],*db=[here URLByAppendingPathComponent:@"resources/db"],*lib=[here URLByAppendingPathComponent:@"lib/liblensfun.0.3.4.dylib"];
 NSURL*source=[db URLByAppendingPathComponent:@"slr-nikon.xml"];NSData*before=[NSData dataWithContentsOfURL:source];NSError*error=nil;
 NSArray*names=@[@"Nikon AF-P DX Nikkor 10-20mm f/4.5-5.6G VR 168",@"Nikon AF-P DX Nikkor 10-20mm f/4.5-5.6G VR",@"Nikkor AF-P 10-20mm f/4.5-5.6G DX VR"];
 NSDictionary*calibration=nil;NSMutableArray*matches=[NSMutableArray new];
 for(NSString*name in names){
  NSDictionary*m=@{@"Make":@"Nikon Corporation",@"Model":@"Nikon D5200",@"LensModel":name,@"FocalLength":@10,@"FNumber":@4.5};
  NSDictionary*p=LensNativeProfilePlan(m,db,lib,64,48,&error);if(!p){NSLog(@"%@",error);return 1;}NSDictionary*r=p[@"report"];
  if(calibration&&![calibration isEqual:r[@"interpolatedCalibration"]])return 2;calibration=r[@"interpolatedCalibration"];
  if(fabs([calibration[@"distortion"][@"terms"][0]doubleValue]-.01265)>1e-6||![r[@"matchedLensIdentityNames"]containsObject:name])return 3;
  [matches addObject:@{@"requested":name,@"matched":r[@"lens"],@"method":r[@"matchingIdentityMethod"]}];
 }
 if(![before isEqual:[NSData dataWithContentsOfURL:source]])return 4;
 // A recorded alias belonging to distinct optical records is still ambiguous.
 NSURL*temp=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:temp withIntermediateDirectories:YES attributes:nil error:nil];NSURL*xml=[temp URLByAppendingPathComponent:@"aliases.xml"];
 NSString*fixture=@"<lensdatabase version=\"1\"><camera><maker>LensDock Test</maker><model>Camera</model><mount>A</mount><cropfactor>1.5</cropfactor></camera><lens><maker>LensDock Test</maker><model>Shared 50mm f/2</model><model>First 50mm f/2</model><model lang=\"x-lensdock-recorded-alias-0\">Existing 50mm f/2</model><mount>A</mount><cropfactor>1.5</cropfactor><calibration><distortion model=\"poly3\" focal=\"50\" k1=\"0.01\"/></calibration></lens><lens><maker>LensDock Test</maker><model>Shared 50mm f/2</model><model>Second 50mm f/2</model><mount>A</mount><cropfactor>1.5</cropfactor><calibration><distortion model=\"poly3\" focal=\"50\" k1=\"-0.01\"/></calibration></lens></lensdatabase>";
 [fixture writeToURL:xml atomically:YES encoding:NSUTF8StringEncoding error:nil];
 NSMutableDictionary*m=[@{@"Make":@"LensDock Test",@"Model":@"Camera",@"LensModel":@"Shared 50mm f/2",@"FocalLength":@50,@"FNumber":@2}mutableCopy];
 if(LensNativeProfilePlan(m,temp,lib,64,48,nil))return 5;
 m[@"LensModel"]=@"Existing 50mm f/2";NSDictionary*p=LensNativeProfilePlan(m,temp,lib,64,48,nil);
 if(![p[@"report"][@"matchedLensIdentityNames"]containsObject:@"Shared 50mm f/2"])return 6;
 if(![fixture isEqual:[NSString stringWithContentsOfURL:xml encoding:NSUTF8StringEncoding error:nil]])return 7;
 [NSFileManager.defaultManager removeItemAtURL:temp error:nil];
 NSDictionary*out=@{@"scope":@"Explicit XML identity preservation and calibration equivalence, not real RAW optical validation",@"recordedDefaultAndTranslatedNamesProduceSameCalibration":@YES,@"originalDatabaseBytesUnchanged":@YES,@"sharedAliasAmbiguityRejected":@YES,@"existingLanguageAliasPreserved":@YES,@"cases":matches};
 [[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil]writeToURL:[here URLByAppendingPathComponent:@"recorded-aliases-verification.json"] atomically:YES];puts("Recorded XML aliases preserve calibration and reject conflicting records.");
}}
