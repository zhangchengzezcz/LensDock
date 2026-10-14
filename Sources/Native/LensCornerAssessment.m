#import "LensCornerAssessment.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>
static float linearValue(float v,BOOL linear){return linear?v:(v<=.04045?v/12.92:powf((v+.055)/1.055,2.4));}
NSDictionary*LensAssessCorners(NSURL*url,NSData*gain,NSUInteger gw,NSUInteger gh,NSString*transfer,NSError**error){
 return LensAssessCornerPreviewData([NSData dataWithContentsOfURL:url],gain,gw,gh,transfer,error);
}
NSDictionary*LensAssessCornerPreviewData(NSData*preview,NSData*gain,NSUInteger gw,NSUInteger gh,NSString*transfer,NSError**error){
 BOOL linear=[transfer isEqual:@"linear"];
 if(!linear&&![transfer isEqual:@"encoded_sRGB"])return nil;
 if(!gw||!gh||gain.length!=gw*gh*4)return nil;
 if(!preview.length)return nil;CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)preview,NULL);if(!source)return nil;
 NSDictionary*options=@{(__bridge NSString*)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString*)kCGImageSourceThumbnailMaxPixelSize:@512,(__bridge NSString*)kCGImageSourceCreateThumbnailWithTransform:@NO};
 CGImageRef image=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)options);CFRelease(source);if(!image)return nil;
 size_t w=CGImageGetWidth(image),h=CGImageGetHeight(image);NSMutableData*buffer=[NSMutableData dataWithLength:w*h*4];unsigned char*b=buffer.mutableBytes;
 CGColorSpaceRef space=CGImageGetColorSpace(image);if(!space||CGColorSpaceGetModel(space)!=kCGColorSpaceModelRGB){CGImageRelease(image);return nil;}
 CGContextRef ctx=CGBitmapContextCreate(b,w,h,8,w*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);if(!ctx){CGImageRelease(image);return nil;}
 CGContextDrawImage(ctx,CGRectMake(0,0,w,h),image);CGContextRelease(ctx);CGImageRelease(image);
 NSMutableData*luminance=[NSMutableData dataWithLength:w*h*sizeof(float)];float*l=luminance.mutableBytes;const float*g=gain.bytes;
 BOOL nonIdentity=NO;for(NSUInteger i=0;i<gw*gh;i++){if(!isfinite(g[i])||g[i]<=0)return nil;if(fabsf(g[i]-1)>1e-3)nonIdentity=YES;}
 size_t newClipping=0,alreadyClipping=0,firstClipping[202]={0};
 for(size_t y=0;y<h;y++)for(size_t x=0;x<w;x++){
  size_t i=y*w+x;float rgb[3];for(int c=0;c<3;c++)rgb[c]=linearValue(b[i*4+c]/255.,linear);
  l[i]=.2126*rgb[0]+.7152*rgb[1]+.0722*rgb[2];float peak=fmaxf(rgb[0],fmaxf(rgb[1],rgb[2]));
  size_t mx=MIN(gw-1,(size_t)((x+.5)*gw/w)),my=MIN(gh-1,(size_t)((y+.5)*gh/h));float factor=g[(gh-1-my)*gw+mx];
  if(peak>=.995)alreadyClipping++;else{
   if(peak*factor>1.)newClipping++;
   if(peak>0&&factor>1){double threshold=(1./peak-1)/(factor-1);if(threshold<2.){int first=MAX(1,MIN(201,(int)floor(threshold*100)+1));firstClipping[first]++;}}
  }
 }
 double center=0;size_t cn=0;
 for(size_t y=h*3/8;y<h*5/8;y++)for(size_t x=w*3/8;x<w*5/8;x++){center+=l[y*w+x];cn++;}center/=MAX((size_t)1,cn);
 NSMutableArray*corners=[NSMutableArray new];BOOL allDark=YES,uniform=YES;double ratios[4];
 NSArray*names=@[@"topLeft",@"topRight",@"bottomLeft",@"bottomRight"];
 for(int corner=0;corner<4;corner++){
  size_t pw=MAX((size_t)2,w/5),ph=MAX((size_t)2,h/5),x0=(corner&1)?w-pw:0,y0=(corner&2)?h-ph:0;
  double sum=0,square=0,gradient=0;size_t n=0,edges=0;
  for(size_t y=y0;y<y0+ph;y++)for(size_t x=x0;x<x0+pw;x++){
   double v=l[y*w+x];sum+=v;square+=v*v;n++;if(x+1<x0+pw){gradient+=fabs(v-l[y*w+x+1]);edges++;}if(y+1<y0+ph){gradient+=fabs(v-l[(y+1)*w+x]);edges++;}
  }
  double mean=sum/n,variance=fmax(0,square/n-mean*mean),texture=gradient/MAX((size_t)1,edges);ratios[corner]=center>1e-5?mean/center:0;
  allDark=allDark&&center>.015&&ratios[corner]<.9;uniform=uniform&&sqrt(variance)<.15&&texture<.025;
  [corners addObject:@{@"position":names[corner],@"meanLinearLuminance":@(mean),@"relativeToCenter":@(ratios[corner]),@"textureEnergy":@(texture),@"luminanceStddev":@(sqrt(variance))}];
 }
 double low=ratios[0],high=ratios[0];for(int i=1;i<4;i++){low=fmin(low,ratios[i]);high=fmax(high,ratios[i]);}
 BOOL sceneAmbiguous=!allDark||!uniform||high-low>.3;
 double clip=(double)newClipping/(w*h);
 NSMutableArray*curve=[NSMutableArray new];size_t count=0;int safe=0;
 for(int strength=0;strength<=200;strength++){count+=firstClipping[strength];double fraction=(double)count/(w*h);[curve addObject:@(fraction)];if(strength<=100&&fraction<=.005)safe=strength;}
 int recommended=nonIdentity?MIN(safe,sceneAmbiguous?50:100):0;
 return @{@"version":@2,@"assessmentSource":@"saved_preview",@"corners":corners,@"centerMeanLinearLuminance":@(center),@"consistentCornerFalloffObserved":@(allDark&&uniform&&high-low<=.3),@"sceneContentAmbiguous":@(sceneAmbiguous),@"predictedNewHighlightClippingFraction":@(clip),@"clippingFractionByStrengthPercent":curve,@"highlightBudgetFraction":@.005,@"highlightLimitedStrengthPercent":@(safe),@"recommendedStrengthPercent":@(recommended),@"recommendedStrengthIsConservativeTrial":@(sceneAmbiguous),@"automaticRecommendedStrengthSuitable":@(nonIdentity&&!sceneAmbiguous&&recommended>0),@"existingHighlightClippingFraction":@((double)alreadyClipping/(w*h)),@"automaticFullStrengthSuitable":@(nonIdentity&&!sceneAmbiguous&&clip<=.005),@"calibrationHasNonIdentityGain":@(nonIdentity),@"calibrationInferredFromContent":@NO};
}
