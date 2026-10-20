#import "LensNativeProfileEngine.h"
// Controlled identity/format fixtures only. These are not optical calibrations
// for real products and never enter the distributed database.
int main(int argc,char**argv){@autoreleasepool{
 NSURL*folder=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
 [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
 NSURL*xml=[folder URLByAppendingPathComponent:@"identity.xml"],*lib=[NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"];
 NSArray*cases=@[
  @[@"Known 50mm f/2 II",@"Known 50mm f/2",@NO,@"missing-generation"],
  @[@"Known 50mm f/2*",@"Known 50mm f/2",@NO,@"missing-star"],
  @[@"Known 50mm f/2+",@"Known 50mm f/2",@NO,@"missing-plus"],
  @[@"镜甲 50mm f/2",@"镜乙 50mm f/2",@NO,@"different-unicode-identity"],
  @[@"Known A047 50mm f/2",@"Known A47 50mm f/2",@NO,@"model-leading-zero"],
  @[@"Known 50mm f/1.4",@"Known 50mm f/14",@NO,@"decimal-not-integer"],
  @[@"Known 17-85mm f/4-5.6",@"Known 1785mm f/4-5.6",@NO,@"focal-boundaries"],
  @[@"Known 17-85mm f/4-5.6",@"Known 85-17mm f/4-5.6",@NO,@"focal-order"],
  @[@"Known 50mm f/2 II",@"Known 50mm f/2 III",@NO,@"different-generation"],
  @[@"Known 50mm f/2",@"OtherBrand Known 50mm f/2",@NO,@"unrecorded-maker"],
  @[@"Known 50mm f/2",@"Known 50mm f/2*",@NO,@"extra-star"],
  @[@"Known 50mm f/2 II",@"Known 50mm f/2 II",@YES,@"exact-generation"],
  @[@"Known 50mm f/2*",@"Known 50mm f/2*",@YES,@"exact-star"],
  @[@"Known 50mm f/2+",@"Known 50mm f/2+",@YES,@"exact-plus"],
  @[@"镜甲 50mm f/2",@"镜甲 50mm f/2",@YES,@"exact-unicode-identity"],
  @[@"LensDock Optics Known 50.0mm f/2.00",@"Known 50mm F2",@YES,@"maker-omission-decimal-format"],
  @[@"Known 50mm f/2",@"LensDock Optics Known 50.0mm F2.00",@YES,@"recorded-maker-prefix"],
  @[@"镜甲 50mm f/2",@"镜甲 50.0mm F2.00",@YES,@"unicode-decimal-format"],
 ];
 NSMutableArray*results=[NSMutableArray new];NSUInteger failures=0;
 for(NSArray*c in cases){
  NSString*s=[NSString stringWithFormat:@"<lensdatabase version=\"1\"><mount><name>IdentityFixture</name></mount><camera><maker>LensDock Test</maker><model>Camera</model><mount>IdentityFixture</mount><cropfactor>1</cropfactor></camera><lens><maker>LensDock Optics</maker><model>%@</model><mount>IdentityFixture</mount><cropfactor>1</cropfactor><calibration><distortion model=\"poly3\" focal=\"50\" k1=\"0.01\"/></calibration></lens></lensdatabase>",c[0]];
  [s writeToURL:xml atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSDictionary*m=@{@"Make":@"LensDock Test",@"Model":@"Camera",@"LensModel":c[1],@"FocalLength":@50,@"FNumber":@2};
  NSDictionary*p=LensNativeProfilePlan(m,folder,lib,48,32,nil);BOOL matched=p!=nil,expected=[c[2]boolValue];if(matched!=expected)failures++;
  [results addObject:@{@"case":c[3],@"matched":@(matched),@"expected":@(expected),@"passed":@(matched==expected)}];
 }
 NSMutableArray*priorityCases=[NSMutableArray new];
 for(NSNumber*direct in @[@YES,@NO]){
  NSString*firstModel=direct.boolValue?@"Known 50mm f/2":@"LensDock Optics Known 50mm f/2";
  NSString*s=[NSString stringWithFormat:@"<lensdatabase version=\"1\"><mount><name>IdentityFixture</name></mount><camera><maker>LensDock Test</maker><model>Camera</model><mount>IdentityFixture</mount><cropfactor>1</cropfactor></camera><lens><maker>LensDock Optics</maker><model>%@</model><mount>IdentityFixture</mount><cropfactor>1</cropfactor><calibration><distortion model=\"poly3\" focal=\"50\" k1=\"0.01\"/></calibration></lens><lens><maker>Other Optics</maker><model>Other Optics Known 50mm f/2</model><mount>IdentityFixture</mount><cropfactor>1</cropfactor><calibration><distortion model=\"poly3\" focal=\"50\" k1=\"0.02\"/></calibration></lens></lensdatabase>",firstModel];
  [s writeToURL:xml atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSDictionary*p=LensNativeProfilePlan(@{@"Make":@"LensDock Test",@"Model":@"Camera",@"LensModel":@"Known 50mm f/2",@"FocalLength":@50,@"FNumber":@2},folder,lib,48,32,nil);
  BOOL passed=direct.boolValue?[p[@"report"][@"lensMaker"]isEqual:@"LensDock Optics"]:!p;if(!passed)failures++;
  [priorityCases addObject:@{@"case":direct.boolValue?@"recorded-model-before-maker-omission":@"ambiguous-maker-omission-rejected",@"passed":@(passed)}];
 }
 NSDictionary*base=@{@"Make":@"Canon",@"Model":@"Canon EOS 40D",@"LensModel":@"EF-S17-85mm f/4-5.6 IS USM",@"FocalLength":@17,@"FNumber":@4};
 NSMutableDictionary*formatted=[base mutableCopy];formatted[@"LensModel"]=@"EF-S17.0-85.0mm F4.00-5.60 IS USM";
 NSURL*db=[NSURL fileURLWithPath:@"Resources/LensBridge/db"];
 NSDictionary*normal=LensNativeProfilePlan(base,db,lib,48,32,nil),*equivalent=LensNativeProfilePlan(formatted,db,lib,48,32,nil);
 BOOL same=normal&&equivalent&&[normal[@"report"][@"interpolatedCalibration"]isEqual:equivalent[@"report"][@"interpolatedCalibration"]];if(!same)failures++;
 [NSFileManager.defaultManager removeItemAtURL:folder error:nil];
 NSDictionary*r=@{@"scope":@"Controlled identity metadata and equivalent numeric formatting against existing Canon calibration; no new lens records or real RAW claim",@"cases":results,@"priorityCases":priorityCases,@"canonEquivalentFormattingSameCalibration":@(same),@"failures":@(failures)};
 NSString*output=argc>1?@(argv[1]):@"Build/Tests/lens-identity-format-verification.json";
 [[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil]writeToFile:output atomically:YES];
 printf("Lens identity/format checks: %lu failures.\n",(unsigned long)failures);return failures?1:0;
}}
