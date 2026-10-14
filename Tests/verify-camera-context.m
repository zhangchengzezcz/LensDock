#import "LensNativeProfileEngine.h"
int main(){@autoreleasepool{
 NSURL*here=[NSURL fileURLWithPath:@"Build/Tests" isDirectory:YES],*db=[here URLByAppendingPathComponent:@"resources/db"],*lib=[here URLByAppendingPathComponent:@"lib/liblensfun.0.3.4.dylib"];NSError*error=nil;
 NSArray*cases=@[
 @{@"Make":@"Olympus Optical Co.,Ltd",@"Model":@"X-2,C-50Z",@"LensModel":@"C-50Z & compatibles (Standard)",@"FocalLength":@7.8,@"FNumber":@2.8},
 @{@"Make":@"Sony",@"Model":@"Cybershot",@"LensModel":@"DSC-F707 & compatibles (Standard)",@"FocalLength":@9.7,@"FNumber":@2},
 @{@"Make":@"Sony",@"Model":@"Cybershot",@"LensModel":@"DSC-S85 & compatibles (Standard)",@"FocalLength":@7,@"FNumber":@2.8}];
 NSMutableArray*results=[NSMutableArray new];
 for(NSDictionary*m in cases){NSDictionary*p=LensNativeProfilePlan(m,db,lib,64,48,&error);if(!p){NSLog(@"%@",error);return 1;}NSDictionary*r=p[@"report"];NSString*method=r[@"cameraIdentityMethod"];if(![method isEqual:@"equivalent-camera-optics-aliases"]&&![method isEqual:@"joint-exact-camera-lens-optical-context"])return 2;[results addObject:@{@"requestedCamera":m[@"Model"],@"requestedLens":m[@"LensModel"],@"cameraMethod":method,@"crop":r[@"interpolatedCalibration"][@"cameraCropFactor"],@"mount":r[@"cameraMount"],@"equivalentCandidates":r[@"equivalentCameraCandidates"]}];}
 // Real multi-aspect modes must remain ambiguous without an explicit mode.
 NSDictionary*ambiguous=@{@"Make":@"Panasonic",@"Model":@"DMC-LX3",@"LensModel":@"DMC-LX3 & compatibles (Standard)",@"FocalLength":@5.1,@"FNumber":@2};
 if(LensNativeProfilePlan(ambiguous,db,lib,64,48,nil))return 3;
 NSURL*temp=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:temp withIntermediateDirectories:YES attributes:nil error:nil];
 NSString*(^database)(NSString*,NSString*,NSString*)=^NSString*(NSString*crop,NSString*mount,NSString*lenses){return [NSString stringWithFormat:@"<lensdatabase version=\"1\"><camera><maker>LensDock Test</maker><model>Shared Camera</model><variant>first</variant><mount>A</mount><cropfactor>1.5</cropfactor></camera><camera><maker>LensDock Test</maker><model>Shared Camera</model><variant>second</variant><mount>%@</mount><cropfactor>%@</cropfactor></camera>%@</lensdatabase>",mount,crop,lenses];};
 NSString*lens=@"<lens><maker>LensDock Test</maker><model>Known 50mm f/2</model><mount>A</mount><cropfactor>1</cropfactor><calibration><distortion model=\"poly3\" focal=\"50\" k1=\"0.01\"/></calibration></lens>";
 NSDictionary*m=@{@"Make":@"LensDock Test",@"Model":@"Shared Camera",@"LensModel":@"Known 50mm f/2",@"FocalLength":@50,@"FNumber":@2};
 NSURL*xml=[temp URLByAppendingPathComponent:@"contexts.xml"];
 [database(@"1.5",@"A",lens)writeToURL:xml atomically:YES encoding:NSUTF8StringEncoding error:nil];NSDictionary*p=LensNativeProfilePlan(m,temp,lib,64,48,nil);if(!p||![p[@"report"][@"cameraIdentityMethod"]isEqual:@"equivalent-camera-optics-aliases"])return 4;
 [database(@"1.6",@"A",lens)writeToURL:xml atomically:YES encoding:NSUTF8StringEncoding error:nil];if(LensNativeProfilePlan(m,temp,lib,64,48,nil))return 5;
 NSString*multiMount=[lens stringByReplacingOccurrencesOfString:@"<mount>A</mount>" withString:@"<mount>A</mount><mount>B</mount>"];
 [database(@"1.5",@"B",multiMount)writeToURL:xml atomically:YES encoding:NSUTF8StringEncoding error:nil];if(LensNativeProfilePlan(m,temp,lib,64,48,nil))return 6;
 // A uniquely identified lens can distinguish mounts; unknown lenses cannot.
 [database(@"1.5",@"B",lens)writeToURL:xml atomically:YES encoding:NSUTF8StringEncoding error:nil];p=LensNativeProfilePlan(m,temp,lib,64,48,nil);if(!p||![p[@"report"][@"cameraIdentityMethod"]isEqual:@"joint-exact-camera-lens-optical-context"])return 7;
 NSMutableDictionary*unknown=[m mutableCopy];unknown[@"LensModel"]=@"Unknown 50mm f/2";if(LensNativeProfilePlan(unknown,temp,lib,64,48,nil))return 8;
 [NSFileManager.defaultManager removeItemAtURL:temp error:nil];
 NSDictionary*report=@{@"recordedCameraAliasesWithSameOpticsAccepted":@YES,@"jointExactLensEvidenceCanResolveCameraMount":@YES,@"differentCropAndMultiAspectModesRejected":@YES,@"sameNameDistinctMountsRejected":@YES,@"unknownLensNotUsedToResolveAmbiguity":@YES,@"cases":results,@"scope":@"identity and optical-context routing, not real RAW accuracy"};
 [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]writeToURL:[here URLByAppendingPathComponent:@"camera-context-verification.json"] atomically:YES];puts("Camera aliases, joint exact lens evidence, crop/mount conflicts and unknown-lens boundaries passed.");
}}
