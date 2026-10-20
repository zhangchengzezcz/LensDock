#import "LensNativeProfileEngine.h"
int main(int argc,char**argv){@autoreleasepool{
 if(argc!=2)return 1;
 NSArray*inputs=@[
 @{@"Make":@"Canon",@"Model":@"Canon EOS 40D",@"LensModel":@"EF-S17-85mm f/4-5.6 IS USM",@"FocalLength":@17,@"FNumber":@4},
 @{@"Make":@"Sony",@"Model":@"ILCE-6000",@"LensModel":@"E 18-55mm f/3.5-5.6 OSS",@"FocalLength":@39,@"FNumber":@5}];
 NSMutableArray*cases=[NSMutableArray new];
 for(NSDictionary*m in inputs){NSMutableArray*times=[NSMutableArray new];NSString*profile=nil;
  for(NSUInteger i=0;i<10;i++){@autoreleasepool{
   CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();NSDictionary*p=LensNativeProfilePlan(m,[NSURL fileURLWithPath:@"Resources/LensBridge/db"],[NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"],96,64,nil);
   double elapsed=(CFAbsoluteTimeGetCurrent()-start)*1000;if(!p)return 2;
   NSString*identifier=p[@"report"][@"matchedLensProfileID"];if(profile&&![profile isEqual:identifier])return 3;profile=identifier;
   if(i)[times addObject:@(elapsed)];
  }}
  NSArray*sorted=[times sortedArrayUsingSelector:@selector(compare:)];[cases addObject:@{@"lens":m[@"LensModel"],@"medianMS":sorted[4],@"samplesMS":times,@"profileID":profile}];
 }
 NSDictionary*r=@{@"scope":@"Warm process, full database load and 96x64 plan, 2 fixed metadata identities; no GUI or full-size rendering speed claim",@"cases":cases};
 [[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@(argv[1]) atomically:YES];
}}
