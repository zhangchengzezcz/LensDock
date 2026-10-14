#import "LensCornerAssessment.h"
#import "LensRecommendationPolicy.h"
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
static BOOL fixture(NSURL*url,const unsigned char*data,int w,int h){
 CGColorSpaceRef s=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);CGDataProviderRef p=CGDataProviderCreateWithData(NULL,data,w*h*4,NULL);CGImageRef i=CGImageCreate(w,h,8,32,w*4,s,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,p,NULL,NO,kCGRenderingIntentDefault);
 CGImageDestinationRef d=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,NULL);CGImageDestinationAddImage(d,i,NULL);BOOL ok=CGImageDestinationFinalize(d);CFRelease(d);CGImageRelease(i);CGDataProviderRelease(p);CGColorSpaceRelease(s);return ok;
}
int main(){@autoreleasepool{
 const int n=128;NSMutableData*bytes=[NSMutableData dataWithLength:n*n*4],*gain=[NSMutableData dataWithLength:n*n*4];unsigned char*b=bytes.mutableBytes;float*g=gain.mutableBytes;NSMutableArray*reports=[NSMutableArray new];
 NSURL*dir=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
 for(int test=0;test<5;test++){
  for(int y=0;y<n;y++)for(int x=0;x<n;x++){int q=y*n+x;g[q]=test>=2?2:1;int v=128;if(test==0&&x<n/5&&y<n/5)v=30;if(test==1&&(x<n/5||x>=n-n/5)&&(y<n/5||y>=n-n/5))v=100;if(test==2)v=220;if(test==3)v=100;if(test==4)v=(x<n/5||x>=n-n/5)&&(y<n/5||y>=n-n/5)?100:220;b[q*4]=b[q*4+1]=b[q*4+2]=v;b[q*4+3]=255;}
  NSURL*url=[dir URLByAppendingPathComponent:[NSString stringWithFormat:@"case%d.png",test]];if(!fixture(url,b,n,n))return 2;
  NSDictionary*r=LensAssessCorners(url,gain,n,n,@"encoded_sRGB",nil);if(!r)return 3;
  if(test==0&&(![r[@"sceneContentAmbiguous"]boolValue]||[r[@"consistentCornerFalloffObserved"]boolValue]||[r[@"corners"][0][@"relativeToCenter"]doubleValue]>.3))return 4;
  if(test==1&&(![r[@"consistentCornerFalloffObserved"]boolValue]||[r[@"sceneContentAmbiguous"]boolValue]))return 5;
  if(test==2&&([r[@"predictedNewHighlightClippingFraction"]doubleValue]<.99||[r[@"automaticFullStrengthSuitable"]boolValue]))return 6;
  double recommended=[r[@"recommendedStrengthPercent"]doubleValue];NSArray*curve=r[@"clippingFractionByStrengthPercent"];
  if(curve.count!=201||[curve[(int)recommended]doubleValue]>.005||recommended<0||recommended>100)return 7;
  if(test==2&&(!(recommended>0&&recommended<50)||[r[@"automaticRecommendedStrengthSuitable"]boolValue]))return 8;
  if(test==3&&(recommended!=50||[r[@"automaticRecommendedStrengthSuitable"]boolValue]))return 9;
  if(test==4&&(![r[@"automaticRecommendedStrengthSuitable"]boolValue]||recommended>=100||recommended<=0))return 10;
  NSDictionary*policy=LensRecommendationPolicy(@{@"report":@{@"distortionProfileAvailable":@YES,@"tcaProfileAvailable":@YES,@"vignettingProfileAvailable":@YES,@"vignettingCorrectionNeeded":@([r[@"calibrationHasNonIdentityGain"]boolValue])},@"cornerAssessment":r});
  if([policy[@"strengths"][2] doubleValue]!=recommended||[policy[@"vignettingAutomatic"]boolValue]!=[r[@"automaticRecommendedStrengthSuitable"]boolValue])return 11;
  [reports addObject:@{@"assessment":r,@"policy":policy}];
 }
 NSDictionary*report=@{@"distortionProfileAvailable":@YES,@"tcaProfileAvailable":@YES,@"vignettingProfileAvailable":@YES,@"vignettingCorrectionNeeded":@YES};
 NSDictionary*missing=LensRecommendationPolicy(@{@"report":report});
 if([missing[@"strengths"][2]doubleValue]!=0||[missing[@"vignettingAutomatic"]boolValue]||![missing[@"vignettingState"]isEqual:@"unmeasured"])return 12;
 NSMutableDictionary*corrupt=[reports[3][@"assessment"]mutableCopy];corrupt[@"recommendedStrengthPercent"]=@200;corrupt[@"automaticRecommendedStrengthSuitable"]=@YES;
 NSDictionary*blocked=LensRecommendationPolicy(@{@"report":report,@"cornerAssessment":corrupt});
 if([blocked[@"strengths"][2]doubleValue]!=0||[blocked[@"vignettingAutomatic"]boolValue])return 13;
 [reports addObject:@{@"case":@"missing-detection",@"policy":missing}];[reports addObject:@{@"case":@"invalid-recommendation",@"policy":blocked}];
 NSMutableDictionary*badCurve=[reports[3][@"assessment"]mutableCopy];NSMutableArray*curve=[badCurve[@"clippingFractionByStrengthPercent"]mutableCopy];curve[10]=@.2;curve[11]=@.1;badCurve[@"clippingFractionByStrengthPercent"]=curve;
 NSDictionary*malformed=LensRecommendationPolicy(@{@"report":report,@"cornerAssessment":badCurve});if([malformed[@"strengths"][2]doubleValue]!=0||[malformed[@"vignettingAutomatic"]boolValue])return 14;
 [reports addObject:@{@"case":@"nonmonotonic-risk-curve",@"policy":malformed}];
 NSData*json=[NSJSONSerialization dataWithJSONObject:reports options:NSJSONWritingPrettyPrinted error:nil];[json writeToFile:@"Build/Tests/corner-assessment-verification.json" atomically:YES];puts("Corner fixtures passed: isolated dark object, symmetric falloff, highlight clipping.");[NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}}
