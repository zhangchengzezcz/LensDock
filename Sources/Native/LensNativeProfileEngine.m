#import "LensNativeProfileEngine.h"
#import "lensfun.h"
#import <ImageIO/ImageIO.h>
#import <CoreImage/CoreImage.h>
#import <dlfcn.h>
#import <math.h>
#import "LensCalibrationEvidence.h"
#import "LensProfileIdentity.h"
#import "LensCaptureModeEvidence.h"
#import "LensFocusDistanceEvidence.h"
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
// Lensfun replaces earlier default model elements with the last one. Retain
// those explicitly recorded names as private language aliases in memory.
// The last default, display translations and every optical value stay intact;
// the public database on disk is never rewritten.
static lfError loadRecordedAliases(lfDatabase*db,NSURL*url,__typeof__(&lf_db_load_file)loadFile,__typeof__(&lf_db_load_data)loadData,NSUInteger*aliasCount){
 NSData*data=[NSData dataWithContentsOfURL:url];if(!data)return LF_WRONG_FORMAT;
 NSXMLDocument*xml=[[NSXMLDocument alloc]initWithData:data options:NSXMLNodeLoadExternalEntitiesNever error:nil];
 if(!xml)return LF_WRONG_FORMAT;
 NSArray*records=[xml nodesForXPath:@"/lensdatabase/lens[count(model[not(@lang)]) > 1]" error:nil];
 if(!records.count)return loadFile(db,url.fileSystemRepresentation);
 NSUInteger added=0;
 for(NSXMLElement*record in records){
  NSArray*defaults=[record nodesForXPath:@"model[not(@lang)]" error:nil];
  for(NSUInteger i=0;i+1<defaults.count;i++){
   NSXMLElement*model=defaults[i];NSUInteger suffix=i;NSString*language=nil;
   do{language=[NSString stringWithFormat:@"x-lensdock-recorded-alias-%lu",(unsigned long)suffix++];}
   while([[record nodesForXPath:[NSString stringWithFormat:@"model[@lang='%@']",language] error:nil]count]);
   [model addAttribute:[NSXMLNode attributeWithName:@"lang" stringValue:language]];
   // The C multi-string requires a default before any language/name pairs.
   [model detach];[record addChild:model];added++;
  }
 }
 NSData*normalized=xml.XMLData;lfError result=loadData(db,url.fileSystemRepresentation,normalized.bytes,normalized.length);
 if(result==LF_NO_ERROR)*aliasCount+=added;return result;
}
// Select a calibration for the recorded lens identity and the known sensor
// class. This does not search for similar focal lengths or nearby lens models.
// Multiple calibrations in the same sensor class remain ambiguous.
static BOOL fisheyeProjection(lfLensType type){return type==LF_FISHEYE||type==LF_FISHEYE_ORTHOGRAPHIC||type==LF_FISHEYE_STEREOGRAPHIC||type==LF_FISHEYE_EQUISOLID||type==LF_FISHEYE_THOBY;}
static BOOL sameProjectionContext(const lfLens*a,const lfLens*b){
 if(a->Type==b->Type)return YES;
 // Different fisheye fits can be calibrated for different sensor regions of
 // one recorded lens. A translated alias alone cannot establish that identity.
 return fisheyeProjection(a->Type)&&fisheyeProjection(b->Type)&&a->Model&&b->Model&&[norm(@(a->Model))isEqual:norm(@(b->Model))]&&isfinite(a->AspectRatio)&&a->AspectRatio>0&&a->AspectRatio==b->AspectRatio;
}
static const lfLens*selectExactLensVariant(const lfLens**candidates,const lfCamera*camera,NSString*name,NSUInteger*count,BOOL*sensorVariant){
 const lfLens*first=NULL;*count=0;*sensorVariant=NO;
 if(candidates)for(NSUInteger i=0;candidates[i];i++)if(exactLensIdentity(candidates[i],name)){if(!first)first=candidates[i];(*count)++;}
 if(*count<=1)return first;
 const lfLens*selected=NULL;NSUInteger near=0;
 for(NSUInteger i=0;candidates[i];i++)if(exactLensIdentity(candidates[i],name)){
  const lfLens*l=candidates[i];BOOL sameMaker=NO;
  for(NSString*a in identityNames(first->Maker))for(NSString*b in identityNames(l->Maker))if([norm(a)isEqual:norm(b)])sameMaker=YES;
  if(!sameMaker||!sameProjectionContext(first,l)||!isfinite(l->CropFactor)||l->CropFactor<=0||!isfinite(camera->CropFactor)||camera->CropFactor<=0)return NULL;
  // 3% admits recorded 1.50/1.534 rounding, but does not collapse Canon 1.6,
  // APS-C 1.5, Micro Four Thirds 2.0 or full-frame 1.0 calibration classes.
  if(fabs(l->CropFactor/camera->CropFactor-1)<=.03){selected=l;near++;}
 }
 if(near!=1)return NULL;
 *sensorVariant=YES;return selected;
}
static const lfLens*fixedBuiltInLens(const lfLens**lenses,const lfCamera*camera,NSDictionary*m){
 if(!lenses||!lenses[0]||lenses[1]||![norm(text(m[@"Model"]))isEqual:@"dmclx3"]||!camera->Mount||strcmp(camera->Mount,"panasonicLX3"))return NULL;
 for(NSString*key in @[@"LensModel",@"LensIDName",@"Lens"])if(text(m[key]).length)return NULL;
 NSDictionary*tags=m[@"rawCaptureMetadata"];if(!LensCaptureModeEvidence(tags)||![tags[@"Panasonic:ConversionLens"]isEqual:@1])return NULL;
 return exactLensIdentity(lenses[0],@"DMC-LX3 & compatibles (Standard)")?lenses[0]:NULL;
}
// Camera marketing variants can be equivalent for lens correction. A shared
// name alone is insufficient: require identical maker, mount and crop factor.
static BOOL exactCameraIdentity(const lfCamera*camera,NSString*model){
 NSString*n=norm(model);if(!n.length)return NO;
 for(NSString*name in identityNames(camera->Model)){
  if([norm(name)isEqual:n])return YES;
  for(NSString*maker in identityNames(camera->Maker))if([norm([maker stringByAppendingString:name])isEqual:n])return YES;
 }
 return NO;
}
static BOOL sameCameraOptics(const lfCamera*a,const lfCamera*b){
 if(!a||!b||!a->Mount||!b->Mount||!isfinite(a->CropFactor)||a->CropFactor<=0||a->CropFactor!=b->CropFactor||strcmp(a->Mount,b->Mount))return NO;
 NSArray*names=identityNames(a->Maker);for(NSString*x in names)for(NSString*y in identityNames(b->Maker))if([norm(x)isEqual:norm(y)])return YES;
 return NO;
}
static const lfCamera*selectCamera(const lfDatabase*db,const lfCamera**candidates,NSDictionary*metadata,__typeof__(&lf_db_find_lenses_hd)findLenses,__typeof__(&lf_free)releaseList,NSString**method,NSString**evidenceKey,NSUInteger*equivalentCount){
 if(!candidates||!candidates[0])return NULL;
 NSMutableArray<NSValue*>*exact=[NSMutableArray new];
 for(NSUInteger i=0;candidates[i];i++)if(exactCameraIdentity(candidates[i],text(metadata[@"Model"]))) [exact addObject:[NSValue valueWithPointer:candidates[i]]];
 if(!exact.count){if(!candidates[1]){*method=@"unique-camera-token-match";*equivalentCount=1;return candidates[0];}return NULL;}
 const lfCamera*first=exact.firstObject.pointerValue;BOOL equivalent=YES;
 for(NSValue*v in exact)if(!sameCameraOptics(first,v.pointerValue)){equivalent=NO;break;}
 if(equivalent){*method=exact.count==1?@"exact-camera-database-alias":@"equivalent-camera-optics-aliases";*equivalentCount=exact.count;return first;}
 NSDictionary*capture=LensCaptureModeEvidence(metadata[@"rawCaptureMetadata"]);
 if(capture&&[norm(capture[@"cameraModel"])isEqual:norm(text(metadata[@"Model"]))]){
  const lfCamera*selected=NULL;NSUInteger count=0;BOOL conflict=NO;
  for(NSValue*v in exact){const lfCamera*c=v.pointerValue;if(c->Variant&&[norm(@(c->Variant))isEqual:norm(capture[@"variant"])]){if(selected&&!sameCameraOptics(selected,c))conflict=YES;if(!selected)selected=c;count++;}}
  if(selected&&!conflict){*method=@"raw-sensor-active-area-aspect-mode";*evidenceKey=@"rawCaptureMetadata";*equivalentCount=count;return selected;}
 }
 // Joint evidence is accepted only from recorded exact lens identities, never
 // focal similarity or a nearest lens. Distinct crop/mount contexts stay errors.
 for(NSString*key in @[@"LensModel",@"LensIDName",@"Lens"]){
  NSString*name=text(metadata[key]);if(!name.length)continue;
  const lfCamera*selected=NULL;NSUInteger compatible=0;BOOL conflict=NO;
  for(NSValue*v in exact){
   const lfCamera*c=v.pointerValue;const lfLens**lenses=findLenses(db,c,NULL,NULL,0);NSUInteger matches=0;
   NSUInteger identities=0;BOOL variant=NO;const lfLens*matching=selectExactLensVariant(lenses,c,name,&identities,&variant);matches=matching?1:identities;
   if(lenses)releaseList((void*)lenses);
   if(matches){if(matches!=1){conflict=YES;continue;}compatible++;if(!selected)selected=c;else if(!sameCameraOptics(selected,c))conflict=YES;}
  }
  if(selected&&!conflict){*method=@"joint-exact-camera-lens-optical-context";*evidenceKey=key;*equivalentCount=compatible;return selected;}
 }
 return NULL;
}
static void selectionFailure(NSError**error,NSString*message){if(error)*error=[NSError errorWithDomain:@"LensBridgeProfile" code:2 userInfo:@{NSLocalizedDescriptionKey:message}];}
static NSDictionary*profileSelection(NSDictionary*m,NSError**error){
 id value=m[@"LensDockProfileSelection"];if(!value)return @{};
 if(![value isKindOfClass:NSDictionary.class]){selectionFailure(error,@"保存的手动配置无效，请重新选择。");return nil;}
 for(NSString*key in @[@"cameraID",@"lensID"]){id v=value[key];if(!v)continue;NSString*prefix=[key isEqual:@"cameraID"]?@"camera-v1-":@"lens-v1-";
  if(![v isKindOfClass:NSString.class]||![v hasPrefix:prefix]||[v length]!=prefix.length+64||[[v substringFromIndex:prefix.length]rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"]invertedSet]].location!=NSNotFound){selectionFailure(error,@"手动配置标识无效，请重新选择。");return nil;}
 }
 return value;
}
static const lfCamera*cameraForID(const lfCamera*const*cameras,NSString*identifier){
 if(cameras)for(NSUInteger i=0;cameras[i];i++)if([LensCameraProfileID(cameras[i])isEqual:identifier])return cameras[i];return NULL;
}
static const lfLens*lensForID(const lfLens**lenses,NSString*identifier){
 if(lenses)for(NSUInteger i=0;lenses[i];i++)if([LensLensProfileID(lenses[i])isEqual:identifier])return lenses[i];return NULL;
}
static BOOL loadProfileDatabase(lfDatabase*db,NSURL*url,__typeof__(&lf_db_load_file)loadFile,__typeof__(&lf_db_load_data)loadData,NSUInteger*loaded,NSUInteger*aliases,NSError**error){
 NSArray*files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:0 error:error];
 for(NSURL*file in [files sortedArrayUsingComparator:^NSComparisonResult(NSURL*a,NSURL*b){return [a.path compare:b.path];}])if([file.pathExtension isEqual:@"xml"]){if(loadRecordedAliases(db,file,loadFile,loadData,aliases)!=LF_NO_ERROR){fail(error,@"镜头数据库读取失败。");return NO;}(*loaded)++;}
 if(!*loaded){fail(error,@"没有可用镜头数据库。");return NO;}return YES;
}
NSDictionary*LensNativeProfileCandidates(NSDictionary*m,NSURL*dbURL,NSURL*libURL,NSError**error){@autoreleasepool{
 NSDictionary*selection=profileSelection(m,error);if(!selection)return nil;
 void*handle=dlopen(libURL.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);if(!handle){fail(error,@"无法载入独立镜头计算库。");return nil;}
 #define CANDIDATE_LOAD(n) __typeof__(&n) n##Fn=dlsym(handle,#n);if(!n##Fn){fail(error,@"镜头库接口版本不兼容。");dlclose(handle);return nil;}
 CANDIDATE_LOAD(lf_db_new);CANDIDATE_LOAD(lf_db_destroy);CANDIDATE_LOAD(lf_db_load_file);CANDIDATE_LOAD(lf_db_load_data);CANDIDATE_LOAD(lf_db_get_cameras);CANDIDATE_LOAD(lf_db_find_cameras);CANDIDATE_LOAD(lf_db_find_lenses_hd);CANDIDATE_LOAD(lf_free);CANDIDATE_LOAD(lf_mlstr_get);CANDIDATE_LOAD(lf_lens_interpolate_distortion);CANDIDATE_LOAD(lf_lens_interpolate_tca);CANDIDATE_LOAD(lf_lens_interpolate_vignetting);
 #undef CANDIDATE_LOAD
 lfDatabase*db=lf_db_newFn();const lfCamera**cs=NULL;const lfLens**ls=NULL;NSDictionary*result=nil;NSUInteger loaded=0,aliases=0,equivalents=0;NSString*method=nil,*evidence=nil,*automaticLensID=nil,*selectedLensID=nil;NSComparator order=nil;NSMutableArray*cameras=[NSMutableArray new],*lenses=[NSMutableArray new];
 if(!loadProfileDatabase(db,dbURL,lf_db_load_fileFn,lf_db_load_dataFn,&loaded,&aliases,error))goto done;
 cs=lf_db_find_camerasFn(db,text(m[@"Make"]).UTF8String,text(m[@"Model"]).UTF8String);
 const lfCamera*automatic=selectCamera(db,cs,m,lf_db_find_lenses_hdFn,lf_freeFn,&method,&evidence,&equivalents);
 const lfCamera*camera=selection[@"cameraID"]?cameraForID(lf_db_get_camerasFn(db),selection[@"cameraID"]):automatic;
 if(selection[@"cameraID"]&&!camera){selectionFailure(error,@"保存的相机模式已变更或不在当前数据库中，请重新选择。");goto done;}
 const lfCamera*const*all=lf_db_get_camerasFn(db);
 for(NSUInteger i=0;all&&all[i];i++){
  const lfCamera*c=all[i];NSString*identifier=LensCameraProfileID(c);if(!identifier)continue;BOOL matched=NO;if(cs)for(NSUInteger j=0;cs[j];j++)if(cs[j]==c)matched=YES;
  NSString*variant=c->Variant?@(lf_mlstr_getFn(c->Variant)):@"";
  [cameras addObject:@{@"id":identifier,@"title":@(lf_mlstr_getFn(c->Model)),@"maker":@(lf_mlstr_getFn(c->Maker)),@"variant":variant,@"mount":c->Mount?@(c->Mount):@"",@"cropFactor":@(c->CropFactor),@"subtitle":[NSString stringWithFormat:@"%@%@ · 裁切 %.3g× · %@",@(lf_mlstr_getFn(c->Maker)),variant.length?[@" · " stringByAppendingString:variant]:@"",c->CropFactor,c->Mount?@(c->Mount):@""],@"matchesMetadata":@(matched)}];
 }
 if(camera){
  ls=lf_db_find_lenses_hdFn(db,camera,NULL,NULL,0);
  for(NSString*key in @[@"LensModel",@"LensIDName",@"Lens"]){
   NSString*name=text(m[key]);if(!name.length)continue;NSUInteger count=0;BOOL sensor=NO;const lfLens*l=selectExactLensVariant(ls,camera,name,&count,&sensor);if(l){automaticLensID=LensLensProfileID(l);break;}if(count>1)continue;
   const lfLens**query=lf_db_find_lenses_hdFn(db,camera,NULL,name.UTF8String,0);NSUInteger total=0;while(query&&query[total])total++;
   l=selectExactLensVariant(query,camera,name,&count,&sensor);if(!l&&count==0&&total==1)l=query[0];if(l)automaticLensID=LensLensProfileID(l);if(query)lf_freeFn((void*)query);if(automaticLensID)break;
  }
  if(!automaticLensID){const lfLens*builtin=fixedBuiltInLens(ls,camera,m);if(builtin)automaticLensID=LensLensProfileID(builtin);}
  const lfLens*manual=selection[@"lensID"]?lensForID(ls,selection[@"lensID"]):NULL;
  if(selection[@"lensID"]&&!manual){selectionFailure(error,@"保存的镜头校准已变更或与此相机不兼容，请重新选择。");goto done;}
  selectedLensID=manual?LensLensProfileID(manual):automaticLensID;
  for(NSUInteger i=0;ls&&ls[i];i++){
   const lfLens*l=ls[i];NSString*identifier=LensLensProfileID(l);if(!identifier)continue;BOOL matched=[identifier isEqual:automaticLensID];for(NSString*key in @[@"LensModel",@"LensIDName",@"Lens"])if(exactLensIdentity(l,text(m[key])))matched=YES;
   lfLensCalibDistortion d={0};lfLensCalibTCA t={0};lfLensCalibVignetting v={0};double focal=positive(m[@"FocalLength"]),aperture=positive(m[@"FNumber"]),distance=positive(m[@"FocusDistance"])?:positive(m[@"SubjectDistance"])?:1000;
   [lenses addObject:@{@"id":identifier,@"title":@(lf_mlstr_getFn(l->Model)),@"maker":@(lf_mlstr_getFn(l->Maker)),@"cropFactor":@(l->CropFactor),@"projection":@(l->Type),@"aspectRatio":@(l->AspectRatio),@"subtitle":[NSString stringWithFormat:@"%@ · 裁切 %.3g× · 比例 %.3g · %@",@(lf_mlstr_getFn(l->Maker)),l->CropFactor,l->AspectRatio,LensProjectionName(l->Type)],@"matchesMetadata":@(matched),@"minFocal":@(l->MinFocal),@"maxFocal":@(l->MaxFocal),@"availableAtCapture":@{@"distortion":@(focal&&lf_lens_interpolate_distortionFn(l,focal,&d)),@"tca":@(focal&&lf_lens_interpolate_tcaFn(l,focal,&t)),@"vignetting":@(focal&&aperture&&lf_lens_interpolate_vignettingFn(l,focal,aperture,distance,&v))}}];
  }
 }
 order=^NSComparisonResult(NSDictionary*a,NSDictionary*b){if([a[@"matchesMetadata"]boolValue]!=[b[@"matchesMetadata"]boolValue])return [a[@"matchesMetadata"]boolValue]?NSOrderedAscending:NSOrderedDescending;NSComparisonResult r=[a[@"title"]compare:b[@"title"] options:NSCaseInsensitiveSearch];return r==NSOrderedSame?[a[@"subtitle"]compare:b[@"subtitle"]]:r;};
 result=@{@"cameras":[cameras sortedArrayUsingComparator:order],@"lenses":[lenses sortedArrayUsingComparator:order],@"selectedCameraID":camera?LensCameraProfileID(camera):@"",@"automaticCameraID":automatic?LensCameraProfileID(automatic):@"",@"selectedLensID":selectedLensID?:@"",@"automaticLensID":automaticLensID?:@"",@"databaseFiles":@(loaded)};
done:
 if(ls)lf_freeFn(ls);if(cs)lf_freeFn(cs);lf_db_destroyFn(db);dlclose(handle);return result;
}}
NSDictionary*LensReadNativeCorrectionSupport(NSURL*rawURL){
 CIRAWFilter*raw=[CIRAWFilter filterWithImageURL:rawURL];
 if(!raw)return @{@"probeSucceeded":@NO,@"probeSource":@"CIRAWFilter.isLensCorrectionSupported"};
 return @{@"probeSucceeded":@YES,@"lensCorrectionSupported":@(raw.isLensCorrectionSupported),@"lensCorrectionEnabledByDefault":@(raw.isLensCorrectionEnabled),@"decoderVersion":raw.decoderVersion?:@"",@"probeSource":@"CIRAWFilter.isLensCorrectionSupported",@"osVersion":NSProcessInfo.processInfo.operatingSystemVersionString};
}
static NSArray*runExifArguments(NSURL*raw,NSURL*tool,NSArray*options,NSError**error){
 if(![NSFileManager.defaultManager fileExistsAtPath:tool.path]){fail(error,@"缺少 MakerNote 元数据读取器。");return nil;}
 NSTask*t=[NSTask new];t.executableURL=[NSURL fileURLWithPath:@"/usr/bin/perl"];
 NSMutableArray*args=[NSMutableArray arrayWithObject:tool.path];[args addObjectsFromArray:options];[args addObject:raw.path];t.arguments=args;
 NSPipe*out=NSPipe.pipe,*err=NSPipe.pipe;t.standardOutput=out;t.standardError=err;
 if(![t launchAndReturnError:error])return nil;
 NSData*d=[out.fileHandleForReading readDataToEndOfFile];[t waitUntilExit];
 if(t.terminationStatus){fail(error,@"MakerNote 元数据读取失败。");return nil;}
 id result=[NSJSONSerialization JSONObjectWithData:d options:0 error:error];return [result isKindOfClass:NSArray.class]?result:nil;
}
static NSArray*runExif(NSURL*raw,NSURL*tool,BOOL numeric,NSError**error){
 NSMutableArray*args=[NSMutableArray arrayWithObject:@"-j"];if(numeric)[args addObject:@"-n"];
 // A CR3 can contain different values with the same tag name in EXIF,
 // MakerNotes and a track. Keep their groups until capture fields are selected;
 // ExifTool's unqualified duplicate winner is not necessarily standard EXIF.
 if(numeric)[args addObjectsFromArray:@[@"-G1",@"-a",@"-Canon:FocusDistanceUpper",@"-Canon:FocusDistanceLower"]];
 [args addObjectsFromArray:@[@"-Make",@"-Model",@"-LensModel",@"-LensID",@"-LensType",@"-Lens",@"-LensInfo",@"-RFLensType",@"-FocalLength",@"-FNumber",@"-ExifIFD:ApertureValue",@"-FocusDistance",@"-SubjectDistance",@"-Orientation"]];
 NSArray*rows=runExifArguments(raw,tool,args,error);if(!numeric||!rows.count)return rows;
 NSDictionary*grouped=rows[0];NSMutableDictionary*values=[NSMutableDictionary new];
 for(NSString*key in [grouped.allKeys sortedArrayUsingSelector:@selector(compare:)]){
  NSRange separator=[key rangeOfString:@":" options:NSBackwardsSearch];NSString*name=separator.location==NSNotFound?key:[key substringFromIndex:separator.location+1];
  // Sony's Composite:FocusDistance is a FocusPosition * FocalLength estimate,
  // not a directly recorded focus distance. It sorts before MakerNote groups
  // and must neither override them nor masquerade as a measured distance.
  if([name isEqual:@"FocusDistance"]&&[key hasPrefix:@"Composite:"])continue;
  if(!values[name])values[name]=grouped[key];
 }
 NSDictionary*standard=@{@"Make":@"IFD0:Make",@"Model":@"IFD0:Model",@"LensModel":@"ExifIFD:LensModel",@"FocalLength":@"ExifIFD:FocalLength",@"FNumber":@"ExifIFD:FNumber",@"SubjectDistance":@"ExifIFD:SubjectDistance",@"ApertureValue":@"ExifIFD:ApertureValue",@"Orientation":@"IFD0:Orientation"};
 for(NSString*name in standard){id value=grouped[standard[name]];if(value)values[name]=value;}
 NSDictionary*range=LensCanonFocusDistanceRange(grouped);if(range)values[@"FocusDistanceRangeMeters"]=range;
 return @[values];
}
NSDictionary*LensReadRawCaptureMetadata(NSURL*raw,NSURL*tool,NSError**error){
 NSArray*rows=runExifArguments(raw,tool,@[@"-j",@"-n",@"-G1",@"-a",@"-FileType",@"-IFD0:Make",@"-IFD0:Model",@"-IFD0:SensorWidth",@"-IFD0:SensorHeight",@"-IFD0:SensorTopBorder",@"-IFD0:SensorLeftBorder",@"-IFD0:SensorBottomBorder",@"-IFD0:SensorRightBorder",@"-IFD0:CropTop",@"-IFD0:CropLeft",@"-IFD0:CropBottom",@"-IFD0:CropRight",@"-ExifIFD:DigitalZoomRatio",@"-Panasonic:ConversionLens"],error);
 if(!rows.count)return nil;NSMutableDictionary*tags=[rows[0]mutableCopy];[tags removeObjectForKey:@"SourceFile"];return tags;
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
  // If a decoder supplies valid standard EXIF but ExifTool only exposes an
  // alternate copy, retain the decoder's capture value rather than a MakerNote.
  for(NSString*key in @[@"FocalLength",@"FNumber",@"SubjectDistance"]){if(positive(ex[key]))m[key]=ex[key];}
  NSArray*b=runExif(rawURL,tool,NO,&makerError);
  if(b.count)m[@"LensIDName"]=b[0][@"LensID"]?:b[0][@"LensType"]?:@"";
  m[@"metadataReader"]=@"ImageIO+ExifTool MakerNote";
 }
 // ApertureValue records the exposure aperture, unlike MaxApertureValue or
 // lens specifications. ExifTool's numeric output already applies ValueConv
 // and is an f-number; ImageIO exposes the original APEX value. Never convert
 // the former a second time, and never replace a valid recorded FNumber.
 if(!positive(m[@"FNumber"])){
  double aperture=a.count?positive(a[0][@"ApertureValue"]):0;
  if(!aperture&&[ex[@"ApertureValue"]isKindOfClass:NSNumber.class]){
   double apex=[ex[@"ApertureValue"]doubleValue];double converted=isfinite(apex)?exp2(apex/2):0;
   if(isfinite(converted)&&converted>0)aperture=converted;
  }
  if(aperture)m[@"FNumber"]=@(aperture);
 }
 // Do not retain two incompatible encodings under the same EXIF key.
 [m removeObjectForKey:@"ApertureValue"];
 if([norm(text(m[@"Model"]))isEqual:@"dmclx3"]){NSError*captureError=nil;NSDictionary*tags=LensReadRawCaptureMetadata(rawURL,tool,&captureError);if(tags)m[@"rawCaptureMetadata"]=tags;if(captureError)m[@"captureMetadataWarning"]=captureError.localizedDescription;}
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
 LOAD(lf_db_new);LOAD(lf_db_destroy);LOAD(lf_db_load_file);LOAD(lf_db_load_data);LOAD(lf_db_get_cameras);LOAD(lf_db_find_cameras);LOAD(lf_db_find_lenses_hd);LOAD(lf_free);LOAD(lf_mlstr_get);
 LOAD(lf_modifier_apply_geometry_distortion);LOAD(lf_modifier_apply_subpixel_distortion);LOAD(lf_modifier_apply_subpixel_geometry_distortion);
 LOAD(lf_lens_interpolate_distortion);LOAD(lf_lens_interpolate_tca);LOAD(lf_lens_interpolate_vignetting);LOAD(lf_modifier_new);LOAD(lf_modifier_initialize);LOAD(lf_modifier_destroy);LOAD(lf_modifier_apply_color_modification);
 lfDatabase*db=lf_db_newFn();const lfCamera**cs=NULL;const lfLens**ls=NULL;lfModifier*mod=NULL;NSDictionary*result=nil;NSString*distanceSource=nil,*identitySource=nil,*identityMethod=nil,*cameraMethod=nil,*cameraEvidenceKey=nil;NSUInteger equivalentCameras=0;NSMutableDictionary*report=nil,*plan=nil,*snapshot=nil;
 NSDictionary*selection=profileSelection(m,error);NSUInteger loaded=0,recordedAliases=0;if(!selection)goto cleanup;if(!loadProfileDatabase(db,dbURL,lf_db_load_fileFn,lf_db_load_dataFn,&loaded,&recordedAliases,error))goto cleanup;
 cs=lf_db_find_camerasFn(db,text(m[@"Make"]).UTF8String,text(m[@"Model"]).UTF8String);
 const lfCamera*camera=selection[@"cameraID"]?cameraForID(lf_db_get_camerasFn(db),selection[@"cameraID"]):selectCamera(db,cs,m,lf_db_find_lenses_hdFn,lf_freeFn,&cameraMethod,&cameraEvidenceKey,&equivalentCameras);const lfLens*lens=NULL;
 if(selection[@"cameraID"]){if(!camera){selectionFailure(error,@"手动相机模式已变更或不存在，请重新选择。");goto cleanup;}cameraMethod=@"user-selected-content-profile";equivalentCameras=1;}
 if(!camera){fail(error,@"相机候选的卡口或裁切参数无法唯一确认，请选择相机配置。");goto cleanup;}
 if(selection[@"lensID"]){ls=lf_db_find_lenses_hdFn(db,camera,NULL,NULL,0);lens=lensForID(ls,selection[@"lensID"]);if(!lens){selectionFailure(error,@"手动镜头校准已变更或与此相机不兼容，请重新选择。");goto cleanup;}identitySource=@"LensDockProfileSelection";identityMethod=@"user-selected-content-profile";}
 else for(NSString*key in @[@"LensModel",@"LensIDName",@"Lens"]){
  NSString*name=text(m[key]);if(!name.length)continue;
  if(ls){lf_freeFn(ls);ls=NULL;}
  // Keep every sensor calibration candidate; the library display-list
  // uniquifier would hide alternative profiles before our identity checks.
  // Search identities among compatible camera mounts before parsing aperture
  // tokens from the name. This accepts recorded aliases, never nearby optics.
  ls=lf_db_find_lenses_hdFn(db,camera,NULL,NULL,0);
  NSUInteger exactCount=0;BOOL sensorVariant=NO;const lfLens*exact=selectExactLensVariant(ls,camera,name,&exactCount,&sensorVariant);
  if(exact){lens=exact;identitySource=key;identityMethod=sensorVariant?@"exact-lens-identity-sensor-calibration-variant":@"normalized-exact-database-alias";break;}
  if(exactCount>1)continue;
  if(ls){lf_freeFn(ls);ls=NULL;}
  ls=lf_db_find_lenses_hdFn(db,camera,NULL,name.UTF8String,0);
  if(!ls)continue;exact=selectExactLensVariant(ls,camera,name,&exactCount,&sensorVariant);NSUInteger count=0;
  for(;ls[count];count++){}
  if(exact){lens=exact;identitySource=key;identityMethod=sensorVariant?@"exact-lens-identity-sensor-calibration-variant":@"normalized-exact";break;}if(exactCount==0&&count==1){lens=ls[0];identitySource=key;identityMethod=@"unique-strict-token-match";break;}
 }
 if(!lens){if(ls){lf_freeFn(ls);ls=NULL;}ls=lf_db_find_lenses_hdFn(db,camera,NULL,NULL,0);lens=fixedBuiltInLens(ls,camera,m);if(lens){identitySource=@"rawCaptureMetadata";identityMethod=@"fixed-built-in-camera-lens";}}
 if(!lens){fail(error,@"无法唯一匹配镜头，请选择镜头配置。");goto cleanup;}
 if(lens->MinFocal&&(focal<lens->MinFocal*.97||focal>lens->MaxFocal*1.03)){fail(error,@"实际焦距超出匹配镜头范围。");goto cleanup;}
 double distance=positive(m[@"FocusDistance"]);if(!distance)distance=positive(m[@"SubjectDistance"]);distanceSource=distance?@"metadata":@"infinity_fallback";if(!distance)distance=1000;
 lfLensCalibDistortion distortion={0};lfLensCalibTCA tca={0};lfLensCalibVignetting vig={0};
 BOOL hasD=lf_lens_interpolate_distortionFn(lens,focal,&distortion),hasT=lf_lens_interpolate_tcaFn(lens,focal,&tca),hasV=aperture&&lf_lens_interpolate_vignettingFn(lens,focal,aperture,distance,&vig);
 report=[@{@"camera":@(lf_mlstr_getFn(camera->Model)),@"lens":@(lf_mlstr_getFn(lens->Model)),@"focal_mm":@(focal),@"aperture":@(aperture),@"focus_distance_m":@(distance),@"distance_source":distanceSource,@"distortionProfileAvailable":@(hasD),@"tcaProfileAvailable":@(hasT),@"vignettingProfileAvailable":@(hasV),@"width":@(w),@"height":@(h),@"databaseFiles":@(loaded)} mutableCopy];
 report[@"cameraIdentityMethod"]=cameraMethod;report[@"equivalentCameraCandidates"]=@(equivalentCameras);report[@"matchedCameraIdentityNames"]=identityNames(camera->Model);
 if(cameraEvidenceKey){report[@"cameraIdentityEvidenceSource"]=cameraEvidenceKey;if([cameraMethod isEqual:@"joint-exact-camera-lens-optical-context"])report[@"cameraIdentityLensEvidenceSource"]=cameraEvidenceKey;}
 {NSDictionary*capturedMode=LensCaptureModeEvidence(m[@"rawCaptureMetadata"]);if(capturedMode&&[norm(text(m[@"Model"]))isEqual:norm(capturedMode[@"cameraModel"])])report[@"rawCaptureModeEvidence"]=capturedMode;}
 report[@"cameraMaker"]=@(lf_mlstr_getFn(camera->Maker));report[@"lensMaker"]=@(lf_mlstr_getFn(lens->Maker));report[@"matchingIdentitySource"]=identitySource;report[@"matchingIdentityMethod"]=identityMethod;
 report[@"matchedLensIdentityNames"]=identityNames(lens->Model);report[@"cameraMount"]=@(camera->Mount);
 report[@"preservedRecordedDefaultAliases"]=@(recordedAliases);
 report[@"matchedCameraProfileID"]=LensCameraProfileID(camera);report[@"matchedLensProfileID"]=LensLensProfileID(lens);
 if(selection.count)report[@"manualProfileSelection"]=selection;
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
 NSDictionary*requestedSelection=profileSelection(m,error);if(!requestedSelection)return nil;
 if(!w||!h||w>16000||h>16000||w*h>120000000){fail(error,@"图像尺寸不在已验证范围。");return nil;}
 NSUInteger orientation=m[@"Orientation"]?[m[@"Orientation"]unsignedIntegerValue]:1;
 if(orientation<1||orientation>8){fail(error,@"RAW 方向标记无效。");return nil;}
 NSUInteger ow=orientation>=5?h:w,oh=orientation>=5?w:h;
 NSDictionary*capture=LensCaptureModeEvidence(m[@"rawCaptureMetadata"]);BOOL captureAligned=YES;
 if(capture&&[norm(text(m[@"Model"]))isEqual:norm(capture[@"cameraModel"])]){
  double aspect=(double)MAX(ow,oh)/MIN(ow,oh);captureAligned=fabs(aspect/[capture[@"aspectRatio"]doubleValue]-1)<=.01;
 }
 NSDictionary*native=m[@"nativeCorrectionSupport"];
 if(native&&![native[@"probeSucceeded"]boolValue]){fail(error,@"暂时无法确认原生镜头矫正支持，未添加补充校正。");return nil;}
 BOOL official=[native[@"lensCorrectionSupported"]boolValue];NSError* __autoreleasing nativeProfileError=nil;
 if(!captureAligned){fail(official?&nativeProfileError:error,@"原始 RAW 的拍摄比例与当前显影尺寸不一致，暂不添加补充校正。");if(!official)return nil;}
 NSDictionary*base=captureAligned?makeNativePlan(m,db,lib,ow,oh,geometry&&!official,official?&nativeProfileError:error):nil;
 if(!base&&requestedSelection.count){if(official&&error)*error=nativeProfileError;return nil;}
 if(official){
  double recordedDistance=positive(m[@"FocusDistance"])?:positive(m[@"SubjectDistance"]);
  NSMutableDictionary*p=base?[base mutableCopy]:[NSMutableDictionary new];NSMutableDictionary*r=base?[base[@"report"]mutableCopy]:[@{@"camera":text(m[@"Model"]),@"lens":text(m[@"LensModel"]).length?text(m[@"LensModel"]):text(m[@"LensIDName"]),@"focal_mm":@(positive(m[@"FocalLength"])),@"aperture":@(positive(m[@"FNumber"])),@"focus_distance_m":@(recordedDistance?:1000),@"distance_source":recordedDistance?@"metadata":@"infinity_fallback",@"width":@(ow),@"height":@(oh),@"vignettingProfileAvailable":@NO,@"vignettingCorrectionNeeded":@NO,@"databaseFiles":@0}mutableCopy];
  r[@"nativeCorrectionSupport"]=native;r[@"geometryHandledByNative"]=@YES;r[@"supplementalVignettingOnly"]=@YES;r[@"nativeVignettingResidualMeasured"]=@NO;
  for(NSString*key in @[@"distortionProfileAvailable",@"tcaProfileAvailable",@"distortionCorrectionNeeded",@"tcaCorrectionNeeded"])r[key]=@NO;
  for(NSString*key in @[@"distortionPeakShiftPixels",@"distortionPeakShiftPercent",@"tcaPeakSeparationPixels"])r[key]=@0;
  if(nativeProfileError)r[@"independentCalibrationNote"]=[NSString stringWithFormat:@"%@ 原生矫正保留，额外暗角补偿不可用。",nativeProfileError.localizedDescription];
  [p removeObjectForKey:@"normalizedGeometryMapsLZFSE"];p[@"report"]=r;base=p;
 }else if(base&&native){NSMutableDictionary*p=[base mutableCopy],*r=[base[@"report"]mutableCopy];r[@"nativeCorrectionSupport"]=native;r[@"geometryHandledByNative"]=@NO;r[@"supplementalVignettingOnly"]=@NO;p[@"report"]=r;base=p;}
 if(base&&LensRecordedFocusDistanceRange(m)){NSMutableDictionary*p=[base mutableCopy],*r=[base[@"report"]mutableCopy];r[@"FocusDistanceRangeMeters"]=LensRecordedFocusDistanceRange(m);p[@"report"]=r;base=p;}
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
