#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "LensCalibrationEvidence.h"
#import "LensGainMap.h"

// Prototype native effect. The full calibration gain map is archived with the
// effect, independently of any rendered RAW. Map samples are linear-light gains.
// This filter must be present on reopening; it is not an official vendor plugin.
static const char *LensGainClassName="LensBridgeProfileVignettingFilter";
static char LensProfileKey,LensMapCacheKey,LensGainCacheKey;
// A one-node border prevents GPU filtering from mixing calibration values with
// implicit zero pixels at texture edges. This pads numeric fields, never RAW.
static CIImage*calibrationImage(NSData*data,NSUInteger w,NSUInteger h,NSUInteger bytesPerPixel,CIFormat format){
 if(!w||!h||data.length!=w*h*bytesPerPixel)return nil;
 NSUInteger row=(w+2)*bytesPerPixel;NSMutableData*padded=[NSMutableData dataWithLength:row*(h+2)];const unsigned char*src=data.bytes;unsigned char*dst=padded.mutableBytes;
 for(NSUInteger y=0;y<h;y++){unsigned char*line=dst+(y+1)*row;memcpy(line+bytesPerPixel,src+y*w*bytesPerPixel,w*bytesPerPixel);memcpy(line,line+bytesPerPixel,bytesPerPixel);memcpy(line+(w+1)*bytesPerPixel,line+w*bytesPerPixel,bytesPerPixel);}
 memcpy(dst,dst+row,row);memcpy(dst+(h+1)*row,dst+h*row,row);
 return [CIImage imageWithBitmapData:padded bytesPerRow:row size:CGSizeMake(w+2,h+2) format:format colorSpace:nil];
}
static NSDictionary *profile(id self) { return objc_getAssociatedObject(self,&LensProfileKey); }
static void setProfile(id self,SEL cmd,NSDictionary *value) {
 objc_setAssociatedObject(self,&LensProfileKey,[value copy],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 objc_setAssociatedObject(self,&LensMapCacheKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 objc_setAssociatedObject(self,&LensGainCacheKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 [self setName:@"镜头矫正"];
}
static id getProfile(id self,SEL cmd) {return profile(self);}
// The native custom-CI wrapper uses these attributes instead of displacement
// map controls. Matching and recommendation selection remain in our panel.
static NSArray *lensInputKeys(id self,SEL cmd){return @[kCIInputImageKey];}
static NSDictionary *lensAttributes(id self,SEL cmd){
 return @{kCIAttributeFilterDisplayName:@"镜头矫正",kCIAttributeFilterName:@"LensBridgeProfileVignettingFilter",kCIAttributeFilterCategories:@[kCICategoryDistortionEffect,kCICategoryColorAdjustment],kCIInputImageKey:@{kCIAttributeClass:@"CIImage",kCIAttributeType:kCIAttributeTypeImage,kCIAttributeDisplayName:@"RAW 显影图像"}};
}
static id decodeProfile(id self,SEL cmd,NSCoder* coder) {
 struct objc_super sup={self,class_getSuperclass(objc_getClass(LensGainClassName))};
 self=((id(*)(struct objc_super*,SEL,id))objc_msgSendSuper)(&sup,cmd,coder);
 if(self){NSDictionary*p=[coder decodeObjectForKey:@"LensBridgeVignettingProfile"];if(p)setProfile(self,NULL,p);NSNumber*amount=[coder decodeObjectForKey:@"LensBridgeLegacyAmount"];if(amount)[self setValue:amount forKey:@"inputAmount"];}
 return self;
}
static void encodeProfile(id self,SEL cmd,NSCoder*coder) {
 struct objc_super sup={self,class_getSuperclass(objc_getClass(LensGainClassName))};
 ((void(*)(struct objc_super*,SEL,id))objc_msgSendSuper)(&sup,cmd,coder);
 [coder encodeObject:profile(self) forKey:@"LensBridgeVignettingProfile"];
 [coder encodeObject:[self valueForKey:@"inputAmount"] forKey:@"LensBridgeLegacyAmount"];
}
static id copyProfile(id self,SEL cmd,NSZone*zone) {
 struct objc_super sup={self,class_getSuperclass(objc_getClass(LensGainClassName))};
 id copy=((id(*)(struct objc_super*,SEL,NSZone*))objc_msgSendSuper)(&sup,cmd,zone);
 if(copy){setProfile(copy,NULL,profile(self));[copy setValue:[self valueForKey:@"inputAmount"] forKey:@"inputAmount"];}return copy;
}
static id gainOutput(id self,SEL cmd) {
 CIImage*input=[self valueForKey:kCIInputImageKey];NSDictionary*p=profile(self);if(!input||!p)return input;
 NSString*transfer=p[@"workingTransfer"];if([transfer isEqual:@"lensdock-compact-v4"]&&[p[@"profileFormatVersion"]isEqual:@4])transfer=p[@"compactWorkingTransfer"];if(![transfer isEqual:@"linear"]&&![transfer isEqual:@"encoded_sRGB"])return input;
 NSUInteger w=[p[@"width"]unsignedIntegerValue],h=[p[@"height"]unsignedIntegerValue];if(!w||!h||w>16000||h>16000)return input;
 CGRect rect=input.extent;if(CGRectIsInfinite(rect)||CGRectIsEmpty(rect))return input;
 NSDictionary*config=p[@"correctionSettings"];double vs,ds=0,ts=0;
 if(config){vs=[config[@"vignettingEnabled"]boolValue]?[config[@"vignettingStrength"]doubleValue]/100.:0;ds=[config[@"distortionEnabled"]boolValue]?[config[@"distortionStrength"]doubleValue]/100.:0;ts=[config[@"tcaEnabled"]boolValue]?[config[@"tcaStrength"]doubleValue]/100.:0;}
 else vs=[[self valueForKey:@"inputAmount"]doubleValue]/100.;
 if([p[@"matchedProfile"][@"supplementalVignettingOnly"]boolValue])ds=ts=0;
 if(ds&&!LensGeometryCalibrationNeeded(p[@"matchedProfile"],@"distortion"))ds=0;
 if(ts&&!LensGeometryCalibrationNeeded(p[@"matchedProfile"],@"tca"))ts=0;
 vs=fmax(0,fmin(2,vs));ds=fmax(0,fmin(2,ds));ts=fmax(0,fmin(2,ts));if(!vs&&!ds&&!ts)return input;
 CIImage*source=[transfer isEqual:@"encoded_sRGB"]?[input imageByApplyingFilter:@"CISRGBToneCurveToLinear"]:input;
 if(vs){
  NSData*d=objc_getAssociatedObject(self,&LensGainCacheKey);if(!d){d=LensDecodedGainData(p,nil);if(d)objc_setAssociatedObject(self,&LensGainCacheKey,d,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}NSUInteger gw=0,gh=0;if(!LensGainMapDimensions(p[@"matchedProfile"],w,h,&gw,&gh)||d.length!=gw*gh*4)return input;
  if(p[@"matchedProfile"][@"gainMapEncoding"]){
   CIImage*map=calibrationImage(d,gw,gh,4,kCIFormatRf);
   static CIKernel*gridGain;static dispatch_once_t once;dispatch_once(&once,^{gridGain=[CIKernel kernelWithString:@"kernel vec4 compactGain(sampler src, sampler field, float strength, vec4 extent, vec4 dimensions) { vec2 p=(destCoord()-extent.xy)/extent.zw; vec2 q=(p*dimensions.xy-vec2(0.5))*(dimensions.zw-vec2(1.0))/(dimensions.xy-vec2(1.0)); q=clamp(q,vec2(0.0),dimensions.zw-vec2(1.0)); vec2 i=floor(q)+vec2(0.5); vec2 f=fract(q); float g=mix(mix(sample(field,clamp(i,vec2(0.5),dimensions.zw-vec2(0.5))+vec2(1.0)).r,sample(field,clamp(i+vec2(1.0,0.0),vec2(0.5),dimensions.zw-vec2(0.5))+vec2(1.0)).r,f.x),mix(sample(field,clamp(i+vec2(0.0,1.0),vec2(0.5),dimensions.zw-vec2(0.5))+vec2(1.0)).r,sample(field,clamp(i+vec2(1.0,1.0),vec2(0.5),dimensions.zw-vec2(0.5))+vec2(1.0)).r,f.x),f.y); vec4 s=sample(src,samplerCoord(src)); return vec4(s.rgb*(1.0+strength*(g-1.0)),s.a); }"];});
   source=[gridGain applyWithExtent:rect roiCallback:^CGRect(int index,CGRect request){return index==0?request:CGRectMake(0,0,gw+2,gh+2);} arguments:@[source,map,@(vs),[CIVector vectorWithCGRect:rect],[CIVector vectorWithX:w Y:h Z:gw W:gh]]];if(!source)return input;
  }else{
  CIImage*map=[CIImage imageWithBitmapData:d bytesPerRow:w*4 size:CGSizeMake(w,h) format:kCIFormatRf colorSpace:nil];map=[map imageByApplyingTransform:CGAffineTransformMake(1,0,0,-1,0,h)];map=[map imageByApplyingTransform:CGAffineTransformMake(rect.size.width/w,0,0,rect.size.height/h,rect.origin.x,rect.origin.y)];
  static CIColorKernel*gainKernel;static dispatch_once_t once;dispatch_once(&once,^{gainKernel=[CIColorKernel kernelWithString:@"kernel vec4 profileGain(__sample source, __sample gain, float strength) { return vec4(source.rgb * (1.0 + strength * (gain.r - 1.0)), source.a); }"];});
  source=[gainKernel applyWithExtent:rect arguments:@[source,map,@(vs)]];
  }
 }
 if(ds||ts){
  NSUInteger mw=[p[@"matchedProfile"][@"geometryMapWidth"]unsignedIntegerValue]?:w,mh=[p[@"matchedProfile"][@"geometryMapHeight"]unsignedIntegerValue]?:h;if(mw<2||mh<2||mw>16000||mh>16000)return input;
  BOOL residual=[p[@"matchedProfile"][@"geometryMapEncoding"]isEqual:@"pixel-displacement-residual-RG8-bottom-up-grid-v4"];double residualStep=residual?[p[@"matchedProfile"][@"geometryResidualStepPixels"]doubleValue]:0;if(residual&&(!isfinite(residualStep)||residualStep<=0||residualStep>1))return input;
  NSDictionary*maps=objc_getAssociatedObject(self,&LensMapCacheKey);
  if(!maps){NSMutableDictionary*decoded=[NSMutableDictionary new];for(NSString*key in p[@"normalizedGeometryMapsLZFSE"]){NSData*data=[p[@"normalizedGeometryMapsLZFSE"][key] decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];if(data.length!=mw*mh*8)return input;decoded[key]=calibrationImage(data,mw,mh,8,kCIFormatRGf);if(residual){NSData*bytes=[p[@"geometryResidualMapsLZFSE"][key]decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil];if(bytes.length!=w*h*2)return input;decoded[[@"R" stringByAppendingString:key]]=calibrationImage(bytes,w,h,2,kCIFormatRG8);}}maps=decoded;objc_setAssociatedObject(self,&LensMapCacheKey,maps,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
  // Unused map arguments use D (or T0); strengths make them algebraically inert.
  CIImage*fallback=maps[@"D"]?:maps[@"T0"];if(!fallback)return input;
  NSMutableArray*args=[NSMutableArray arrayWithObject:source];
  for(NSString*key in @[@"D",@"T0",@"T1",@"T2",@"C0",@"C1",@"C2"])[args addObject:maps[key]?:fallback];
  for(NSString*key in @[@"D",@"T0",@"T1",@"T2",@"C0",@"C1",@"C2"])[args addObject:maps[[@"R" stringByAppendingString:key]]?:fallback];
  [args addObjectsFromArray:@[@(ds),@(ts),@(residual||[p[@"matchedProfile"][@"geometryMapEncoding"]isEqual:@"pixel-displacement-RGf-bottom-up-grid-v3"]),@(residualStep),[CIVector vectorWithCGRect:rect],[CIVector vectorWithX:w Y:h Z:mw W:mh]]];
  // Samples outside the original have no photographic data. Explicitly keep
  // them transparent: the native wrapper otherwise extends the edge pixels.
  static CIKernel*warp;static dispatch_once_t once;dispatch_once(&once,^{warp=[CIKernel kernelWithString:@"vec2 profileCoordinate(sampler m, sampler residual, vec2 p, vec4 dimensions, float offsets, float step) { vec2 q=(p*dimensions.xy-vec2(0.5))*(dimensions.zw-vec2(1.0))/(dimensions.xy-vec2(1.0)); q=clamp(q,vec2(0.0),dimensions.zw-vec2(1.0)); vec2 i=floor(q)+vec2(0.5); vec2 f=fract(q); vec2 value=mix(mix(sample(m,clamp(i,vec2(0.5),dimensions.zw-vec2(0.5))+vec2(1.0)).rg,sample(m,clamp(i+vec2(1.0,0.0),vec2(0.5),dimensions.zw-vec2(0.5))+vec2(1.0)).rg,f.x),mix(sample(m,clamp(i+vec2(0.0,1.0),vec2(0.5),dimensions.zw-vec2(0.5))+vec2(1.0)).rg,sample(m,clamp(i+vec2(1.0,1.0),vec2(0.5),dimensions.zw-vec2(0.5))+vec2(1.0)).rg,f.x),f.y); if(offsets<0.5)return value; if(step>0.0){ vec2 rq=clamp(p*dimensions.xy-vec2(0.5),vec2(0.0),dimensions.xy-vec2(1.0)); vec2 ri=floor(rq)+vec2(0.5); vec2 rf=fract(rq); vec2 correction=mix(mix(sample(residual,clamp(ri,vec2(0.5),dimensions.xy-vec2(0.5))+vec2(1.0)).rg,sample(residual,clamp(ri+vec2(1.0,0.0),vec2(0.5),dimensions.xy-vec2(0.5))+vec2(1.0)).rg,rf.x),mix(sample(residual,clamp(ri+vec2(0.0,1.0),vec2(0.5),dimensions.xy-vec2(0.5))+vec2(1.0)).rg,sample(residual,clamp(ri+vec2(1.0,1.0),vec2(0.5),dimensions.xy-vec2(0.5))+vec2(1.0)).rg,rf.x),rf.y); value+=(correction*255.0-vec2(128.0))*step; } return p+value/dimensions.xy; } kernel vec4 profileGeometry(sampler src, sampler d, sampler tr, sampler tg, sampler tb, sampler cr, sampler cg, sampler cb, sampler rd, sampler rtr, sampler rtg, sampler rtb, sampler rcr, sampler rcg, sampler rcb, float ds, float ts, float offsets, float step, vec4 extent, vec4 dimensions) { vec2 p=(destCoord()-extent.xy)/extent.zw; vec2 pd=profileCoordinate(d,rd,p,dimensions,offsets,step); vec2 pr=mix(mix(p,pd,ds),mix(profileCoordinate(tr,rtr,p,dimensions,offsets,step),profileCoordinate(cr,rcr,p,dimensions,offsets,step),ds),ts); vec2 pg=mix(mix(p,pd,ds),mix(profileCoordinate(tg,rtg,p,dimensions,offsets,step),profileCoordinate(cg,rcg,p,dimensions,offsets,step),ds),ts); vec2 pb=mix(mix(p,pd,ds),mix(profileCoordinate(tb,rtb,p,dimensions,offsets,step),profileCoordinate(cb,rcb,p,dimensions,offsets,step),ds),ts); vec2 lo=vec2(0.5)/extent.zw; vec2 hi=vec2(1.0)-lo; if(pr.x<lo.x||pr.y<lo.y||pr.x>hi.x||pr.y>hi.y||pg.x<lo.x||pg.y<lo.y||pg.x>hi.x||pg.y>hi.y||pb.x<lo.x||pb.y<lo.y||pb.x>hi.x||pb.y>hi.y)return vec4(0.0); vec4 r=sample(src,samplerTransform(src,extent.xy+pr*extent.zw)); vec4 g=sample(src,samplerTransform(src,extent.xy+pg*extent.zw)); vec4 b=sample(src,samplerTransform(src,extent.xy+pb*extent.zw)); return vec4(r.r,g.g,b.b,g.a); }"];});
  source=[warp applyWithExtent:rect roiCallback:^CGRect(int index,CGRect request){return index==0?rect:(index>7?CGRectMake(0,0,w+2,h+2):CGRectMake(0,0,mw+2,mh+2));} arguments:args];if(!source)return input;
 }
 return [transfer isEqual:@"encoded_sRGB"]?[source imageByApplyingFilter:@"CILinearToSRGBToneCurve"]:source;
}
Class LensRegisterVignettingFilter(void) {
 Class cls=objc_getClass(LensGainClassName);if(cls)return cls;
 Class base=NSClassFromString(@"PTFoundation.PTCIDisplacementMapFilter");if(!base)return Nil;
 cls=objc_allocateClassPair(base,LensGainClassName,0);if(!cls)return Nil;
 class_addMethod(cls,@selector(copyWithZone:),(IMP)copyProfile,"@24@0:8^v16");
 class_addMethod(cls,@selector(outputImage),(IMP)gainOutput,"@16@0:8");
 class_addMethod(cls,@selector(inputKeys),(IMP)lensInputKeys,"@16@0:8");
 class_addMethod(cls,@selector(attributes),(IMP)lensAttributes,"@16@0:8");
 class_addMethod(cls,NSSelectorFromString(@"lensProfile"),(IMP)getProfile,"@16@0:8");
 class_addMethod(cls,NSSelectorFromString(@"setLensProfile:"),(IMP)setProfile,"v24@0:8@16");
 class_addMethod(cls,@selector(initWithCoder:),(IMP)decodeProfile,"@24@0:8@16");
 class_addMethod(cls,@selector(encodeWithCoder:),(IMP)encodeProfile,"v24@0:8@16");
 objc_registerClassPair(cls);return cls;
}
