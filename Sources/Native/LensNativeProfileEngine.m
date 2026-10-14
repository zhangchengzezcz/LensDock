#import "LensNativeProfileEngine.h"
#import "lensfun.h"
#import <ImageIO/ImageIO.h>
#import <CoreImage/CoreImage.h>
#import <dlfcn.h>
#import <math.h>
#import "LensCalibrationEvidence.h"
static void fail(NSError**error,NSString*message){if(error)*error=[NSError errorWithDomain:@"LensBridgeProfile" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];}
static double positive(id n){if(![n respondsToSelector:@selector(doubleValue)])return 0;double v=[n doubleValue];return isfinite(v)&&v>0?v:0;}
static NSString*text(id v){return [v isKindOfClass:NSString.class]?v:@"";}
static NSString*norm(NSString*v){return [v.lowercaseString stringByReplacingOccurrencesOfString:@"[^a-z0-9]" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0,v.length)];}
// Lensfun's public multi-language string stores the default EXIF name first,
// then language/name pairs. Display labels are not reliable identity keys.
static NSArray<NSString*>*identityNames(lfMLstr value){
 if(!value||!*value)return @[];NSMutableArray*names=[NSMutableArray arrayWithObject:@(value)];const char*next=value+strlen(value)+1;
 for(NSUInteger i=0;i<64&&*next;i++){next+=strlen(next)+1;if(!*next)break;[names addObject:@(next)];next+=strlen(next)+1;}
 return names;
}
static BOOL exactLensIdentity(const lfLens*lens,NSString*name){
 NSString*n=norm(name);if(!n.length)return NO;
 for(NSString*model in identityNames(lens->Model)){if([norm(model)isEqual:n])return YES;for(NSString*maker in identityNames(lens->Maker))if([norm([maker stringByAppendingString:model])isEqual:n])return YES;}
 return NO;
}
NSDictionary*LensReadNativeCorrectionSupport(NSURL*rawURL){
 CIRAWFilter*raw=[CIRAWFilter filterWithImageURL:rawURL];
 if(!raw)return @{@"probeSucceeded":@NO,@"probeSource":@"CIRAWFilter.isLensCorrectionSupported"};
 return @{@"probeSucceeded":@YES,@"lensCorrectionSupported":@(raw.isLensCorrectionSupported),@"lensCorrectionEnabledByDefault":@(raw.isLensCorrectionEnabled),@"decoderVersion":raw.decoderVersion?:@"",@"probeSource":@"CIRAWFilter.isLensCorrectionSupported",@"osVersion":NSProcessInfo.processInfo.operatingSystemVersionString};
}
static NSArray*runExif(NSURL*raw,NSURL*tool,BOOL numeric,NSError**error){
 if(![NSFileManager.defaultManager fileExistsAtPath:tool.path]){fail(error,@"缺少 MakerNote 元数据读取器。");return nil;}
 NSTask*t=[NSTask new];t.executableURL=[NSURL fileURLWithPath:@"/usr/bin/perl"];
 NSMutableArray*args=[NSMutableArray arrayWithObjects:tool.path,@"-j",nil];if(numeric)[args addObject:@"-n"];
 [args addObjectsFromArray:@[@"-Make",@"-Model",@"-LensModel",@"-LensID",@"-LensType",@"-Lens",@"-LensInfo",@"-RFLensType",@"-FocalLength",@"-FNumber",@"-FocusDistance",@"-SubjectDistance",@"-Orientation",raw.path]];t.arguments=args;
 NSPipe*out=NSPipe.pipe,*err=NSPipe.pipe;t.standardOutput=out;t.standardError=err;
 if(![t launchAndReturnError:error])return nil;
 NSData*d=[out.fileHandleForReading readDataToEndOfFile];[t waitUntilExit];
 if(t.terminationStatus){fail(error,@"MakerNote 元数据读取失败。");return nil;}
 id result=[NSJSONSerialization JSONObjectWithData:d options:0 error:error];return [result isKindOfClass:NSArray.class]?result:nil;
}
NSDictionary*LensReadRawMetadata(NSURL*rawURL,NSURL*tool,NSError**error){
 CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)rawURL,NULL);
 if(!source){fail(error,@"无法读取 RAW 元数据。");return nil;}
 NSDictionary*p=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));CFRelease(source);
 NSDictionary*ex=p[@"{Exif}"],*tiff=p[@"{TIFF}"];
 NSMutableDictionary*m=[NSMutableDictionary new];
 for(NSString*key in @[@"Make",@"Model"]){if(tiff[key])m[key]=tiff[key];}
 for(NSString*key in @[@"LensModel",@"FocalLength",@"FNumber",@"SubjectDistance"]){if(ex[key])m[key]=ex[key];}
 if(p[@"Orientation"])m[@"Orientation"]=p[@"Orientation"];
 m[@"metadataReader"]=@"ImageIO";
 m[@"nativeCorrectionSupport"]=LensReadNativeCorrectionSupport(rawURL);
 // MakerNotes also supply IDs and focus distance when standard EXIF already
 // contains a lens name. Always supplement it; never guess distance from focus
 // position or substitute another lens when the ID is missing/ambiguous.
 NSError*makerError=nil;NSArray*a=runExif(rawURL,tool,YES,&makerError);
 if(a.count){
  [m addEntriesFromDictionary:a[0]];
  NSArray*b=runExif(rawURL,tool,NO,&makerError);
  if(b.count)m[@"LensIDName"]=b[0][@"LensID"]?:b[0][@"LensType"]?:@"";
  m[@"metadataReader"]=@"ImageIO+ExifTool MakerNote";
 }
 if(makerError){
  if(!text(m[@"LensModel"]).length&&![m[@"nativeCorrectionSupport"][@"lensCorrectionSupported"]boolValue]){if(error)*error=makerError;return nil;}
  m[@"metadataWarning"]=makerError.localizedDescription;
 }
 [m removeObjectForKey:@"SourceFile"];return m;
}

static NSDictionary*makeNativePlan(NSDictionary*m,NSURL*dbURL,NSURL*libURL,NSUInteger w,NSUInteger h,BOOL geometry,NSError**error){
 if(!w||!h||w>16000||h>16000||w*h>120000000){fail(error,@"图像尺寸不在已验证范围。");return nil;}
 double focal=positive(m[@"FocalLength"]),aperture=positive(m[@"FNumber"]);
 if(!focal){fail(error,@"缺少拍摄焦距。");return nil;}
 void*handle=dlopen(libURL.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);if(!handle){fail(error,@"无法载入独立镜头计算库。");return nil;}
 #define LOAD(n) __typeof__(&n) n##Fn=dlsym(handle,#n);if(!n##Fn){fail(error,@"镜头库接口版本不兼容。");dlclose(handle);return nil;}
 LOAD(lf_db_new);LOAD(lf_db_destroy);LOAD(lf_db_load_file);LOAD(lf_db_find_cameras);LOAD(lf_db_find_lenses_hd);LOAD(lf_free);LOAD(lf_mlstr_get);
 LOAD(lf_modifier_apply_geometry_distortion);LOAD(lf_modifier_apply_subpixel_distortion);LOAD(lf_modifier_apply_subpixel_geometry_distortion);
 LOAD(lf_lens_interpolate_distortion);LOAD(lf_lens_interpolate_tca);LOAD(lf_lens_interpolate_vignetting);LOAD(lf_modifier_new);LOAD(lf_modifier_initialize);LOAD(lf_modifier_destroy);LOAD(lf_modifier_apply_color_modification);
 lfDatabase*db=lf_db_newFn();const lfCamera**cs=NULL;const lfLens**ls=NULL;lfModifier*mod=NULL;NSDictionary*result=nil;NSString*distanceSource=nil,*identitySource=nil,*identityMethod=nil;NSMutableDictionary*report=nil,*plan=nil,*snapshot=nil;
 NSArray*files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:dbURL includingPropertiesForKeys:nil options:0 error:error];NSUInteger loaded=0;
 for(NSURL*url in [files sortedArrayUsingComparator:^NSComparisonResult(NSURL*a,NSURL*b){return [a.path compare:b.path];}]){
  if([url.pathExtension isEqual:@"xml"]){if(lf_db_load_fileFn(db,url.fileSystemRepresentation)!=LF_NO_ERROR){fail(error,@"镜头数据库读取失败。");goto cleanup;}loaded++;}
 }
 if(!loaded){fail(error,@"没有可用镜头数据库。");goto cleanup;}
 cs=lf_db_find_camerasFn(db,text(m[@"Make"]).UTF8String,text(m[@"Model"]).UTF8String);
 if(!cs||!cs[0]||cs[1]){fail(error,@"无法唯一匹配相机，请选择相机配置。");goto cleanup;}
 const lfCamera*camera=cs[0];const lfLens*lens=NULL;
 for(NSString*key in @[@"LensModel",@"LensIDName",@"Lens"]){
  NSString*name=text(m[key]);if(!name.length)continue;
  if(ls){lf_freeFn(ls);ls=NULL;}
  // Search identities among compatible camera mounts before parsing aperture
  // tokens from the name. This accepts recorded aliases, never nearby optics.
  ls=lf_db_find_lenses_hdFn(db,camera,NULL,NULL,LF_SEARCH_SORT_AND_UNIQUIFY);
  const lfLens*exact=NULL;NSUInteger exactCount=0;
  if(ls)for(NSUInteger i=0;ls[i];i++)if(exactLensIdentity(ls[i],name)){exact=ls[i];exactCount++;}
  if(exactCount==1){lens=exact;identitySource=key;identityMethod=@"normalized-exact-database-alias";break;}
  if(exactCount>1)continue;
  if(ls){lf_freeFn(ls);ls=NULL;}
  ls=lf_db_find_lenses_hdFn(db,camera,NULL,name.UTF8String,LF_SEARCH_SORT_AND_UNIQUIFY);
  if(!ls)continue;exact=NULL;exactCount=0;NSUInteger count=0;
  for(;ls[count];count++){
   if(exactLensIdentity(ls[count],name)){exact=ls[count];exactCount++;}
  }
  if(exactCount==1){lens=exact;identitySource=key;identityMethod=@"normalized-exact";break;}if(exactCount==0&&count==1){lens=ls[0];identitySource=key;identityMethod=@"unique-strict-token-match";break;}
 }
 if(!lens){fail(error,@"无法唯一匹配镜头，请选择镜头配置。");goto cleanup;}
 if(lens->MinFocal&&(focal<lens->MinFocal*.97||focal>lens->MaxFocal*1.03)){fail(error,@"实际焦距超出匹配镜头范围。");goto cleanup;}
 double distance=positive(m[@"FocusDistance"]);if(!distance)distance=positive(m[@"SubjectDistance"]);distanceSource=distance?@"metadata":@"infinity_fallback";if(!distance)distance=1000;
 lfLensCalibDistortion distortion={0};lfLensCalibTCA tca={0};lfLensCalibVignetting vig={0};
 BOOL hasD=lf_lens_interpolate_distortionFn(lens,focal,&distortion),hasT=lf_lens_interpolate_tcaFn(lens,focal,&tca),hasV=aperture&&lf_lens_interpolate_vignettingFn(lens,focal,aperture,distance,&vig);
 report=[@{@"camera":@(lf_mlstr_getFn(camera->Model)),@"lens":@(lf_mlstr_getFn(lens->Model)),@"focal_mm":@(focal),@"aperture":@(aperture),@"focus_distance_m":@(distance),@"distance_source":distanceSource,@"distortionProfileAvailable":@(hasD),@"tcaProfileAvailable":@(hasT),@"vignettingProfileAvailable":@(hasV),@"width":@(w),@"height":@(h),@"databaseFiles":@(loaded)} mutableCopy];
 report[@"cameraMaker"]=@(lf_mlstr_getFn(camera->Maker));report[@"lensMaker"]=@(lf_mlstr_getFn(lens->Maker));report[@"matchingIdentitySource"]=identitySource;report[@"matchingIdentityMethod"]=identityMethod;
 report[@"matchedLensIdentityNames"]=identityNames(lens->Model);report[@"cameraMount"]=@(camera->Mount);
 if(m[@"metadataReader"])report[@"metadataReader"]=m[@"metadataReader"];
 if(m[@"metadataWarning"])report[@"metadataWarning"]=m[@"metadataWarning"];
 snapshot=[@{@"lensfunVersion":@"0.3.4",@"cameraCropFactor":@(camera->CropFactor),@"lensCropFactor":@(lens->CropFactor),@"lensProjection":@(lens->Type),@"lensCenter":@[@(lens->CenterX),@(lens->CenterY)],@"lensAspectRatio":@(lens->AspectRatio)}mutableCopy];
 if(hasD)snapshot[@"distortion"]=@{@"model":@(distortion.Model),@"focal":@(distortion.Focal),@"terms":@[@(distortion.Terms[0]),@(distortion.Terms[1]),@(distortion.Terms[2])]};
 if(hasT)snapshot[@"tca"]=@{@"model":@(tca.Model),@"focal":@(tca.Focal),@"terms":@[@(tca.Terms[0]),@(tca.Terms[1]),@(tca.Terms[2]),@(tca.Terms[3]),@(tca.Terms[4]),@(tca.Terms[5])]};
 if(hasV)snapshot[@"vignetting"]=@{@"model":@(vig.Model),@"focal":@(vig.Focal),@"aperture":@(vig.Aperture),@"distance":@(vig.Distance),@"terms":@[@(vig.Terms[0]),@(vig.Terms[1]),@(vig.Terms[2])]};
 report[@"interpolatedCalibration"]=snapshot;plan=[@{@"report":report}mutableCopy];
 BOOL needsD=LensGeometryCalibrationNeeded(report,@"distortion"),needsT=LensGeometryCalibrationNeeded(report,@"tca");
 for(int pass=0;pass<2;pass++){
  if(pass==0?!needsD:!needsT)continue;
  mod=lf_modifier_newFn(lens,camera->CropFactor,(int)w,(int)h);int flags=pass==0?LF_MODIFY_DISTORTION:LF_MODIFY_TCA;
  int enabled=lf_modifier_initializeFn(mod,lens,LF_PF_F32,focal,aperture?:8,distance,1,LF_RECTILINEAR,flags,0);
  if(!(enabled&flags)){fail(error,@"有效的几何标定未能启用，停止生成校正。");goto cleanup;}
  double peak=0;
  for(int y=0;y<=64;y++)for(int x=0;x<=64;x++){
   double px=(double)x*(w-1)/64.,py=(double)y*(h-1)/64.;float q[6]={0};
   BOOL valid=pass==0?lf_modifier_apply_geometry_distortionFn(mod,px,py,1,1,q):lf_modifier_apply_subpixel_distortionFn(mod,px,py,1,1,q);
   if(!valid){fail(error,@"无法评估镜头标定的实际校正量。");goto cleanup;}
   double shift=pass==0?hypot(q[0]-px,q[1]-py):fmax(hypot(q[0]-q[2],q[1]-q[3]),hypot(q[4]-q[2],q[5]-q[3]));
   if(!isfinite(shift)){fail(error,@"镜头标定的校正量无效。");goto cleanup;}peak=fmax(peak,shift);
  }
  report[pass==0?@"distortionPeakShiftPixels":@"tcaPeakSeparationPixels"]=@(peak);
  if(pass==0){report[@"distortionPeakShiftPercent"]=@(100*peak/MIN(w,h));needsD=peak>.001;}else needsT=peak>.001;
  lf_modifier_destroyFn(mod);mod=NULL;
 }
 report[@"distortionCorrectionNeeded"]=@(needsD);report[@"tcaCorrectionNeeded"]=@(needsT);
 if(!report[@"distortionPeakShiftPercent"])report[@"distortionPeakShiftPercent"]=@0;
 if(!report[@"tcaPeakSeparationPixels"])report[@"tcaPeakSeparationPixels"]=@0;
 report[@"geometryAmountAssessment"]=@"optical-profile-sampled-65x65";report[@"geometryCalibrationInferredFromContent"]=@NO;
 if(hasV){
  mod=lf_modifier_newFn(lens,camera->CropFactor,(int)w,(int)h);
  int enabled=lf_modifier_initializeFn(mod,lens,LF_PF_F32,focal,aperture,distance,1,LF_RECTILINEAR,LF_MODIFY_VIGNETTING,0);
  BOOL valid=!!(enabled&LF_MODIFY_VIGNETTING);NSMutableData*gain=nil;float lo=INFINITY,hi=0;
  if(valid){
   gain=[NSMutableData dataWithLength:w*h*4];float*g=gain.mutableBytes;for(NSUInteger i=0;i<w*h;i++)g[i]=1;
   valid=lf_modifier_apply_color_modificationFn(mod,g,0,0,(int)w,(int)h,LF_CR_1(RED),(int)w*4);
   if(valid)for(NSUInteger i=0;i<w*h;i++){float v=g[i];if(!isfinite(v)||v<=0){valid=NO;break;}lo=fminf(lo,v);hi=fmaxf(hi,v);}
   if(valid){for(NSUInteger y=0;y<h/2;y++)for(NSUInteger x=0;x<w;x++){float v=g[y*w+x];g[y*w+x]=g[(h-1-y)*w+x];g[(h-1-y)*w+x]=v;}}
  }
  report[@"vignettingCalibrationPresent"]=@YES;report[@"vignettingCalibrationUsable"]=@(valid);
  if(valid){report[@"gain_range"]=@[@(lo),@(hi)];report[@"vignettingCorrectionNeeded"]=@(fabsf(lo-1)>1e-3||fabsf(hi-1)>1e-3);plan[@"linearGainFloat32BottomUp"]=gain;}
  else{report[@"vignettingProfileAvailable"]=@NO;report[@"vignettingCorrectionNeeded"]=@NO;report[@"vignettingCalibrationWarning"]=@"当前图像范围内的暗角增益无效，已关闭这项；有效畸变与色差可独立使用。";}
 }
 // Persist normalized source coordinates, independently of RAW pixel data.
 // Each RG plane is losslessly compressed and tagged with its map encoding.
 if(geometry&&(needsD||needsT)&&w*h<=48000000){
  NSMutableDictionary*maps=[NSMutableDictionary new];
  for(int pass=0;pass<3;pass++){
   BOOL multi=pass!=0;if((pass==0&&!needsD)||(pass==1&&!needsT)||(pass==2&&(!needsD||!needsT)))continue;
   if(mod){lf_modifier_destroyFn(mod);mod=NULL;}
   mod=lf_modifier_newFn(lens,camera->CropFactor,(int)w,(int)h);
   int flags=pass==0?LF_MODIFY_DISTORTION:pass==1?LF_MODIFY_TCA:LF_MODIFY_DISTORTION|LF_MODIFY_TCA;
   int enabled=lf_modifier_initializeFn(mod,lens,LF_PF_F32,focal,aperture?:8,distance,1,LF_RECTILINEAR,flags,0);
   if((enabled&flags)!=flags){fail(error,@"镜头几何标定不可用。");goto cleanup;}
   NSMutableData*coordinates=[NSMutableData dataWithLength:w*h*(multi?6:2)*sizeof(float)];float*xy=coordinates.mutableBytes;
   BOOL ok=pass==0?lf_modifier_apply_geometry_distortionFn(mod,0,0,(int)w,(int)h,xy):pass==1?lf_modifier_apply_subpixel_distortionFn(mod,0,0,(int)w,(int)h,xy):lf_modifier_apply_subpixel_geometry_distortionFn(mod,0,0,(int)w,(int)h,xy);
   if(!ok){fail(error,@"镜头坐标映射生成失败。");goto cleanup;}
   for(int channel=0;channel<(multi?3:1);channel++){@autoreleasepool{
    NSMutableData*rg=[NSMutableData dataWithLength:w*h*8];float*target=rg.mutableBytes;
    for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){
     NSUInteger from=(y*w+x)*(multi?6:2)+channel*2,to=((h-1-y)*w+x)*2;
     target[to]=(xy[from]+.5f)/w;target[to+1]=1.f-(xy[from+1]+.5f)/h;
     if(!isfinite(target[to])||!isfinite(target[to+1])){fail(error,@"镜头坐标映射无效。");goto cleanup;}
    }
    NSData*compressed=[rg compressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:error];if(!compressed)goto cleanup;
    NSString*key=pass==0?@"D":[NSString stringWithFormat:@"%c%d",pass==1?'T':'C',channel];maps[key]=compressed;
   }}
  }
  plan[@"normalizedGeometryMapsLZFSE"]=maps;report[@"geometryMapEncoding"]=@"normalized-source-RGf-bottom-up-v1";
 }
 result=plan;
cleanup:
 if(mod)lf_modifier_destroyFn(mod);if(ls)lf_freeFn(ls);if(cs)lf_freeFn(cs);lf_db_destroyFn(db);dlclose(handle);return result;
}

static CGPoint originalPoint(CGPoint p,NSUInteger orientation,NSUInteger width,NSUInteger height){
 switch(orientation){case 2:return CGPointMake(width-1-p.x,p.y);case 3:return CGPointMake(width-1-p.x,height-1-p.y);case 4:return CGPointMake(p.x,height-1-p.y);case 5:return CGPointMake(p.y,p.x);case 6:return CGPointMake(p.y,height-1-p.x);case 7:return CGPointMake(width-1-p.y,height-1-p.x);case 8:return CGPointMake(width-1-p.y,p.x);default:return p;}
}
static CGPoint orientedPoint(CGPoint p,NSUInteger orientation,NSUInteger width,NSUInteger height){
 switch(orientation){case 2:return CGPointMake(width-1-p.x,p.y);case 3:return CGPointMake(width-1-p.x,height-1-p.y);case 4:return CGPointMake(p.x,height-1-p.y);case 5:return CGPointMake(p.y,p.x);case 6:return CGPointMake(height-1-p.y,p.x);case 7:return CGPointMake(height-1-p.y,width-1-p.x);case 8:return CGPointMake(p.y,width-1-p.x);default:return p;}
}
static NSDictionary*makeOrientedPlan(NSDictionary*m,NSURL*db,NSURL*lib,NSUInteger w,NSUInteger h,BOOL geometry,NSError**error){
 if(!w||!h||w>16000||h>16000||w*h>120000000){fail(error,@"图像尺寸不在已验证范围。");return nil;}
 NSUInteger orientation=m[@"Orientation"]?[m[@"Orientation"]unsignedIntegerValue]:1;
 if(orientation<1||orientation>8){fail(error,@"RAW 方向标记无效。");return nil;}
 NSUInteger ow=orientation>=5?h:w,oh=orientation>=5?w:h;
 NSDictionary*native=m[@"nativeCorrectionSupport"];
 if(native&&![native[@"probeSucceeded"]boolValue]){fail(error,@"暂时无法确认原生镜头矫正支持，未添加补充校正。");return nil;}
 BOOL official=[native[@"lensCorrectionSupported"]boolValue];NSError* __autoreleasing nativeProfileError=nil;
 NSDictionary*base=makeNativePlan(m,db,lib,ow,oh,geometry&&!official,official?&nativeProfileError:error);
 if(official){
  NSMutableDictionary*p=base?[base mutableCopy]:[NSMutableDictionary new];NSMutableDictionary*r=base?[base[@"report"]mutableCopy]:[@{@"camera":text(m[@"Model"]),@"lens":text(m[@"LensModel"]).length?text(m[@"LensModel"]):text(m[@"LensIDName"]),@"focal_mm":@(positive(m[@"FocalLength"])),@"aperture":@(positive(m[@"FNumber"])),@"focus_distance_m":@(positive(m[@"FocusDistance"])?:1000),@"distance_source":positive(m[@"FocusDistance"])?@"metadata":@"infinity_fallback",@"width":@(ow),@"height":@(oh),@"vignettingProfileAvailable":@NO,@"vignettingCorrectionNeeded":@NO,@"databaseFiles":@0}mutableCopy];
  r[@"nativeCorrectionSupport"]=native;r[@"geometryHandledByNative"]=@YES;r[@"supplementalVignettingOnly"]=@YES;r[@"nativeVignettingResidualMeasured"]=@NO;
  for(NSString*key in @[@"distortionProfileAvailable",@"tcaProfileAvailable",@"distortionCorrectionNeeded",@"tcaCorrectionNeeded"])r[key]=@NO;
  for(NSString*key in @[@"distortionPeakShiftPixels",@"distortionPeakShiftPercent",@"tcaPeakSeparationPixels"])r[key]=@0;
  if(nativeProfileError)r[@"independentCalibrationNote"]=@"没有唯一的独立镜头标定；原生矫正保留，额外暗角补偿不可用。";
  [p removeObjectForKey:@"normalizedGeometryMapsLZFSE"];p[@"report"]=r;base=p;
 }else if(base&&native){NSMutableDictionary*p=[base mutableCopy],*r=[base[@"report"]mutableCopy];r[@"nativeCorrectionSupport"]=native;r[@"geometryHandledByNative"]=@NO;r[@"supplementalVignettingOnly"]=@NO;p[@"report"]=r;base=p;}
 if(!base||orientation==1)return base;
 NSMutableDictionary*plan=[base mutableCopy],*report=[base[@"report"]mutableCopy];report[@"width"]=@(w);report[@"height"]=@(h);report[@"sourceOrientation"]=@(orientation);report[@"calibrationWidth"]=@(ow);report[@"calibrationHeight"]=@(oh);plan[@"report"]=report;
 NSData*gain=base[@"linearGainFloat32BottomUp"];
 if(gain){if(gain.length!=ow*oh*4)return nil;const float*source=gain.bytes;NSMutableData*out=[NSMutableData dataWithLength:w*h*4];float*target=out.mutableBytes;
  for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){CGPoint p=originalPoint(CGPointMake(x,y),orientation,ow,oh);target[((h-1-y)*w+x)]=source[((oh-1-(NSUInteger)p.y)*ow+(NSUInteger)p.x)];}plan[@"linearGainFloat32BottomUp"]=out;
 }
 if(base[@"normalizedGeometryMapsLZFSE"]){NSMutableDictionary*maps=[NSMutableDictionary new];for(NSString*key in base[@"normalizedGeometryMapsLZFSE"]){@autoreleasepool{
  NSData*data=[base[@"normalizedGeometryMapsLZFSE"][key]decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:error];if(data.length!=ow*oh*8)return nil;const float*source=data.bytes;NSMutableData*out=[NSMutableData dataWithLength:w*h*8];float*target=out.mutableBytes;
  for(NSUInteger y=0;y<h;y++)for(NSUInteger x=0;x<w;x++){CGPoint p=originalPoint(CGPointMake(x,y),orientation,ow,oh);NSUInteger pos=((oh-1-(NSUInteger)p.y)*ow+(NSUInteger)p.x)*2;CGPoint q=orientedPoint(CGPointMake(source[pos]*ow-.5,(1-source[pos+1])*oh-.5),orientation,ow,oh);NSUInteger to=((h-1-y)*w+x)*2;target[to]=(q.x+.5)/w;target[to+1]=1-(q.y+.5)/h;}
  NSData*encoded=[out compressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:error];if(!encoded)return nil;maps[key]=encoded;
 }}plan[@"normalizedGeometryMapsLZFSE"]=maps;}
 return plan;
}
NSDictionary*LensNativeProfilePlan(NSDictionary*m,NSURL*db,NSURL*lib,NSUInteger w,NSUInteger h,NSError**error){return makeOrientedPlan(m,db,lib,w,h,NO,error);}

// Compression is accepted only after checking every coordinate in each full map.
// Original RAW and interpolated coefficients remain intact. Runtime interpolation
// adds a measured subpixel approximation, recorded with the persisted effect.
static double mapValue(const float*data,NSUInteger w,NSUInteger h,double x,double y,int channel){
 NSUInteger ix=MIN(w-2,(NSUInteger)floor(x)),iy=MIN(h-2,(NSUInteger)floor(y));double fx=x-ix,fy=y-iy;
 return (1-fy)*((1-fx)*data[(iy*w+ix)*2+channel]+fx*data[(iy*w+ix+1)*2+channel])+fy*((1-fx)*data[((iy+1)*w+ix)*2+channel]+fx*data[((iy+1)*w+ix+1)*2+channel]);
}
NSDictionary*LensCompactGeometryPlan(NSDictionary*full,double tolerance,NSError**error){
 NSDictionary*r=full[@"report"],*maps=full[@"normalizedGeometryMapsLZFSE"];NSUInteger w=[r[@"width"]unsignedIntegerValue],h=[r[@"height"]unsignedIntegerValue];
 if(!maps.count||w<2||h<2)return full;if(!isfinite(tolerance)||tolerance<=0)return nil;
 for(NSUInteger nodes=65;nodes<=2049;nodes=2*(nodes-1)+1){@autoreleasepool{
  NSUInteger mw=MIN(w,nodes),mh=MIN(h,nodes);NSMutableDictionary*compressed=[NSMutableDictionary new];double worst=0;BOOL accepted=YES;
  for(NSString*key in maps){@autoreleasepool{
   NSData*data=[maps[key]decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:error];if(data.length!=w*h*8)return nil;const float*source=data.bytes;
   NSMutableData*grid=[NSMutableData dataWithLength:mw*mh*8];float*g=grid.mutableBytes;
   for(NSUInteger y=0;y<mh;y++)for(NSUInteger x=0;x<mw;x++)for(int c=0;c<2;c++)g[(y*mw+x)*2+c]=mapValue(source,w,h,(double)x*(w-1)/(mw-1),(double)y*(h-1)/(mh-1),c);
   for(NSUInteger y=0;y<h&&accepted;y++)for(NSUInteger x=0;x<w&&accepted;x++)for(int c=0;c<2;c++){
    double value=mapValue(g,mw,mh,(double)x*(mw-1)/(w-1),(double)y*(mh-1)/(h-1),c);
    double e=fabs(value-source[(y*w+x)*2+c])*(c==0?w:h);worst=fmax(worst,e);if(e>tolerance){accepted=NO;break;}
   }
   if(!accepted)break;NSData*encoded=[grid compressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:error];if(!encoded)return nil;compressed[key]=encoded;
  }}
  if(accepted){NSMutableDictionary*plan=[full mutableCopy],*report=[r mutableCopy];report[@"geometryMapWidth"]=@(mw);report[@"geometryMapHeight"]=@(mh);report[@"geometryMapEncoding"]=@"normalized-source-RGf-bottom-up-grid-v2";report[@"geometryMapVerifiedMaxErrorPixels"]=@(worst);report[@"geometryMapTolerancePixels"]=@(tolerance);report[@"geometryVerification"]=@"every-full-resolution-coordinate";plan[@"report"]=report;plan[@"normalizedGeometryMapsLZFSE"]=compressed;return plan;}
  if(mw==w&&mh==h)break;
 }}
 // A profile that cannot meet the tolerance retains its full-resolution maps.
 return full;
}
NSDictionary*LensNativeProfilePlanFullGeometry(NSDictionary*m,NSURL*db,NSURL*lib,NSUInteger w,NSUInteger h,NSError**error){return makeOrientedPlan(m,db,lib,w,h,YES,error);}
NSDictionary*LensNativeProfilePlanIncludingGeometry(NSDictionary*m,NSURL*db,NSURL*lib,NSUInteger w,NSUInteger h,NSError**error){NSDictionary*full=makeOrientedPlan(m,db,lib,w,h,YES,error);return full?LensCompactGeometryPlan(full,.001,error):nil;}
