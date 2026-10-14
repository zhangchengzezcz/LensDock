#import "LensLiveDocument.h"
#import "LensNativeState.h"
#import "LensNativeDocument.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <math.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
@interface NSObject(LiveBitmapRead)
- (id)colorSpace;
- (CGColorSpaceRef)CGColorSpace;
- (CIImage*)CIImage;
@end
typedef void* __attribute__((swiftcall)) (*LiveGetter)(void* __attribute__((swift_context)));
typedef void __attribute__((swiftcall)) (*RawGetter)(void* __attribute__((swift_indirect_result)),void* __attribute__((swift_context)));
typedef void* __attribute__((swiftcall)) (*RawCreator)(void*,void* __attribute__((swift_context)));
typedef struct {void*type;uintptr_t state;} MetadataResponse;
typedef MetadataResponse __attribute__((swiftcall)) (*MetadataGetter)(uintptr_t);
typedef CGSize __attribute__((swiftcall))(*SizeGetter)(void* __attribute__((swift_context)));
typedef CGPoint __attribute__((swiftcall))(*ScaleGetter)(void* __attribute__((swift_context)));
typedef CGFloat __attribute__((swiftcall))(*BackingGetter)(void* __attribute__((swift_context)));
typedef struct{void*buffer;uint64_t timestamp;} BitmapInfo;
typedef BitmapInfo __attribute__((swiftcall))(*BitmapGetter)(void*,void* __attribute__((swift_context)));
static void liveFail(NSError**error,NSString*message){if(error)*error=[NSError errorWithDomain:@"LensBridgeLive" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];}
static void diagnostic(NSDictionary*state){[[NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:nil]writeToFile:[NSTemporaryDirectory()stringByAppendingPathComponent:@"LensLiveFailure.json"] atomically:YES];}
static id reference(id script,const char*name){Ivar ivar=class_getInstanceVariable(object_getClass(script),name);if(!ivar)return nil;void*p=NULL;memcpy(&p,(char*)(__bridge void*)script+ivar_getOffset(ivar),sizeof(p));return (__bridge id)p;}
static NSArray*liveObjects(NSDocument*doc,id script){
 if(!NSThread.isMainThread||![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]isEqual:@"4.3"]||![doc isKindOfClass:NSClassFromString(@"PXMPro.Document")]||![script isKindOfClass:NSClassFromString(@"Pixelmator.ScriptingLayer")]){diagnostic(@{@"stage":@"host-class",@"document":NSStringFromClass(object_getClass(doc))?:@"",@"script":NSStringFromClass(object_getClass(script))?:@"",@"mainThread":@(NSThread.isMainThread),@"version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@""});return nil;}
 LiveGetter contextGet=dlsym(RTLD_DEFAULT,"$s6PXMKit0A8DocumentC15documentContextAA0abD0Cvg"),engineGet=dlsym(RTLD_DEFAULT,"$s6PXMKit0A15DocumentContextC6engine9PXMEngine6EngineCvg");
 id context=contextGet?CFBridgingRelease(contextGet((__bridge void*)doc)):nil;id engine=context&&engineGet?CFBridgingRelease(engineGet((__bridge void*)context)):nil;id uid=reference(script,"identifier"),raw=reference(script,"layer");
 if(![NSStringFromClass(object_getClass(engine))isEqual:@"PXMEngine.Engine"]||![NSStringFromClass(object_getClass(uid))isEqual:@"PTFoundation.PTHashableString"]||![NSStringFromClass(object_getClass(raw))isEqual:@"PXMEngine.RawLayer"]){diagnostic(@{@"stage":@"references",@"engine":NSStringFromClass(object_getClass(engine))?:@"",@"identifier":NSStringFromClass(object_getClass(uid))?:@"",@"layer":NSStringFromClass(object_getClass(raw))?:@""});return nil;}
 return @[context,engine,uid,raw];
}
static void*liveBridge(void){static void*handle;static dispatch_once_t once;dispatch_once(&once,^{NSURL*file=[NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"LensLiveSource.dylib"];handle=dlopen(file.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);});return handle;}
static NSString*rawTypeForFile(NSURL*file){
 CGImageSourceRef image=CGImageSourceCreateWithURL((__bridge CFURLRef)file,NULL);NSString*type=image?[(__bridge NSString*)CGImageSourceGetType(image) copy]:nil;if(image)CFRelease(image);if(LensNativeRAWExtension(type))return type;
 // Some TIFF-based RAW formats are identified as TIFF when the temporary file
 // has no original suffix. ExifTool identifies their actual format from bytes.
 NSURL*tool=[NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"LensBridge/exiftool/exiftool"];NSTask*task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/perl"];task.arguments=@[tool.path,@"-s3",@"-FileTypeExtension",file.path];NSPipe*pipe=NSPipe.pipe;task.standardOutput=pipe;task.standardError=NSFileHandle.fileHandleWithNullDevice;if(![task launchAndReturnError:nil])return nil;NSData*out=[pipe.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];if(task.terminationStatus||out.length>32)return nil;
 NSString*extension=[[[NSString alloc]initWithData:out encoding:NSUTF8StringEncoding]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];UTType*declared=[UTType typeWithFilenameExtension:extension];return LensNativeRAWExtension(declared.identifier)?declared.identifier:nil;
}
static NSDictionary*sourceIdentity(NSArray*objects){
 void*handle=liveBridge();void*(*export)(void*,void*,void*)=handle?dlsym(handle,"LensBridgeExportOriginalRAW"):NULL;if(!export)return nil;
 NSURL*root=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];if(![NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil])return nil;NSURL*file=[root URLByAppendingPathComponent:@"Original.raw"];NSError*error=CFBridgingRelease(export((__bridge void*)objects[1],(__bridge void*)objects[2],(__bridge void*)file));NSDictionary*result=nil;
 if(!error){NSDictionary*attributes=[NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil];uint64_t bytes=[attributes[NSFileSize]unsignedLongLongValue];if(bytes&&bytes<=256*1024*1024){NSString*type=rawTypeForFile(file);NSData*data=[NSData dataWithContentsOfURL:file options:NSDataReadingMappedIfSafe error:nil];if(data&&LensNativeRAWExtension(type)){unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString*sha=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[sha appendFormat:@"%02x",digest[i]];result=@{@"typeIdentifier":type,@"rawSHA256":sha,@"byteCount":@(bytes)};}}}
 [NSFileManager.defaultManager removeItemAtURL:root error:nil];return result;
}
static NSArray*nativeRawParameters(id raw){
 RawGetter get=dlsym(RTLD_DEFAULT,"$s9PXMEngine8RawLayerC13rawParameters12PTFoundation05PTRawE0Vvg");RawCreator create=dlsym(RTLD_DEFAULT,"$s12PTFoundation19PTRawParametersObjCC03rawC0AcA0bC0V_tcfC");MetadataGetter metadata=dlsym(RTLD_DEFAULT,"$s12PTFoundation15PTRawParametersVMa");Class cls=NSClassFromString(@"PTFoundation.PTRawParametersObjC");
 if(!get||!create||!metadata||!cls)return nil;void*t=metadata(0).type;if(!t)return nil;void**witness=*((void***)t-1);if(((uintptr_t*)witness)[8]!=0x118)return nil;
 // The version-verified getter returns an owned indirect value; the allocating
 // wrapper initializer consumes it. Never release the transferred fields twice.
 uint64_t value[0x118/8]={0};get(value,(__bridge void*)raw);id wrapper=CFBridgingRelease(create(value,(__bridge void*)cls));NSData*j=LensEffectsJSON(wrapper,nil);id decoded=j?[NSJSONSerialization JSONObjectWithData:j options:0 error:nil]:nil;
 return [decoded isKindOfClass:NSArray.class]&&[decoded count]==2&&[decoded[1]isKindOfClass:NSDictionary.class]?decoded:nil;
}
static NSDictionary*fingerprint(NSArray*objects,id script){
 id context=objects[0],engine=objects[1],uid=objects[2],raw=objects[3];NSArray*parameters=nativeRawParameters(raw);if(!parameters){diagnostic(@{@"stage":@"raw-parameters"});return nil;}
 SizeGetter sizeGet=dlsym(RTLD_DEFAULT,"$s9PXMEngine5LayerC4sizeSo6CGSizeVvg");BackingGetter backingGet=dlsym(RTLD_DEFAULT,"$s9PXMEngine5LayerC12backingScale12CoreGraphics7CGFloatVvg");ScaleGetter scaleGet=dlsym(RTLD_DEFAULT,"$s9PXMEngine5LayerC5scaleSo7CGPointVvg");LiveGetter formatGet=dlsym(RTLD_DEFAULT,"$s6PXMKit0A15DocumentContextC14documentFormatSo012PTBitmapDataE0Cvg");
 NSDictionary*source=sourceIdentity(objects);if(!source||!sizeGet||!backingGet||!scaleGet||!formatGet){diagnostic(@{@"stage":@"source-identity",@"source":source?:@{},@"sizeGetter":@(sizeGet!=NULL),@"backingGetter":@(backingGet!=NULL),@"scaleGetter":@(scaleGet!=NULL),@"formatGetter":@(formatGet!=NULL)});return nil;}
 SEL rotation=NSSelectorFromString(@"scriptRotation"),unique=NSSelectorFromString(@"scriptUniqueID");if(![script respondsToSelector:rotation]||![script respondsToSelector:unique])return nil;double angle=((double(*)(id,SEL))objc_msgSend)(script,rotation);NSString*identifier=((id(*)(id,SEL))objc_msgSend)(script,unique);
 CGSize size=sizeGet((__bridge void*)raw);CGPoint scale=scaleGet((__bridge void*)raw);CGFloat backing=backingGet((__bridge void*)raw);
 id format=CFBridgingRelease(formatGet((__bridge void*)context)),color=[format respondsToSelector:@selector(colorSpace)]?[format colorSpace]:nil;CGColorSpaceRef space=[color respondsToSelector:@selector(CGColorSpace)]?[color CGColorSpace]:NULL;NSString*name=space?CFBridgingRelease(CGColorSpaceCopyName(space)):@"";
 NSString*transfer=@"unsupported";if([@[@"kCGColorSpaceDisplayP3",@"kCGColorSpaceSRGB",@"kCGColorSpaceExtendedSRGB"]containsObject:name])transfer=@"encoded_sRGB";if([@[@"kCGColorSpaceExtendedLinearSRGB",@"kCGColorSpaceLinearSRGB",@"kCGColorSpaceExtendedLinearDisplayP3"]containsObject:name])transfer=@"linear";
 return @{@"rawParameters":parameters,@"sourceInformation":source,@"identifier":identifier,@"width":@(size.width*backing),@"height":@(size.height*backing),@"scale":@[@(scale.x),@(scale.y)],@"angle":@(angle),@"workingTransfer":transfer,@"colorSpaceName":name?:@""};
}
NSDictionary*LensLiveRAWFingerprint(NSDocument*doc,id script){NSArray*objects=liveObjects(doc,script);return objects?fingerprint(objects,script):nil;}
BOOL LensRegisterLiveHistory(NSDocument*doc,id script){
 NSArray *objects=liveObjects(doc,script);void *handle=objects?liveBridge():NULL;
 BOOL(*registerHistory)(void*)=handle?dlsym(handle,"LensBridgeRegisterLensHistory"):NULL;
 return registerHistory&&registerHistory((__bridge void*)objects[1]);
}
NSDictionary*LensReadLiveRAWLayer(NSDocument*doc,id script,NSURL*temporary,NSError**error){
 NSArray*objects=liveObjects(doc,script);NSDictionary*state=objects?fingerprint(objects,script):nil;if(!state){liveFail(error,@"当前版本无法读取原生 RAW 状态。");return nil;}
 double w=[state[@"width"]doubleValue],h=[state[@"height"]doubleValue];if(!isfinite(w)||!isfinite(h)||w<2||h<2||w>16000||h>16000||w*h>120000000||fabs(w-round(w))>1e-6||fabs(h-round(h))>1e-6||[state[@"scale"][0]doubleValue]!=1||[state[@"scale"][1]doubleValue]!=1||[state[@"angle"]doubleValue]!=0){liveFail(error,@"图层旋转、缩放或尺寸尚未验证。");return nil;}
 NSString*type=state[@"sourceInformation"][@"typeIdentifier"],*extension=LensNativeRAWExtension(type);if(!extension){liveFail(error,@"当前图层没有可识别的原始 RAW 资源。");return nil;}
 if([state[@"workingTransfer"]isEqual:@"unsupported"]){liveFail(error,@"当前文档颜色空间尚未验证。");return nil;}
 if(![NSFileManager.defaultManager createDirectoryAtURL:temporary withIntermediateDirectories:YES attributes:nil error:error])return nil;
 NSURL*rawURL=[temporary URLByAppendingPathComponent:[@"Original." stringByAppendingString:extension]];void*handle=liveBridge();void*(*export)(void*,void*,void*)=handle?dlsym(handle,"LensBridgeExportOriginalRAW"):NULL;if(!export){liveFail(error,@"原始数据读取桥接不可用。");return nil;}
 NSError*exportError=CFBridgingRelease(export((__bridge void*)objects[1],(__bridge void*)objects[2],(__bridge void*)rawURL));if(exportError){if(error)*error=exportError;return nil;}
 NSDictionary*attributes=[NSFileManager.defaultManager attributesOfItemAtPath:rawURL.path error:error];uint64_t bytes=[attributes[NSFileSize]unsignedLongLongValue];if(!bytes||bytes>256*1024*1024){liveFail(error,@"原始 RAW 数据大小超出当前验证范围。");return nil;}
 LiveGetter stateGet=dlsym(RTLD_DEFAULT,"$s9PXMEngine6EngineC12contentStateAA07ContentD0CSgvg");id content=stateGet?CFBridgingRelease(stateGet((__bridge void*)objects[1])):nil;BitmapGetter bitmapGet=dlsym(RTLD_DEFAULT,"$s9PXMEngine12ContentStateC016bitmapOfRawLayerB07layerIDAC0fgbC4DataV10BitmapInfoVSg12PTFoundation16PTHashableStringC_tF");id bitmap=nil;if(content&&bitmapGet){BitmapInfo info=bitmapGet((__bridge void*)objects[2],(__bridge void*)content);if(info.buffer)bitmap=CFBridgingRelease(info.buffer);}
 CIImage*image=[bitmap respondsToSelector:@selector(CIImage)]?[bitmap CIImage]:nil;if(!image||image.extent.size.width!=w||image.extent.size.height!=h){liveFail(error,@"当前 RAW 显影预览尚未就绪，请重新匹配。");return nil;}
 CGFloat reduction=MIN(1,2048./MAX(w,h));image=[image imageByApplyingTransform:CGAffineTransformMakeScale(reduction,reduction)];CGColorSpaceRef srgb=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);CIContext*renderer=[CIContext contextWithOptions:nil];CGImageRef cg=[renderer createCGImage:image fromRect:image.extent format:kCIFormatRGBA8 colorSpace:srgb];CGColorSpaceRelease(srgb);if(!cg){liveFail(error,@"无法读取当前 RAW 显影预览。");return nil;}
 NSMutableData*preview=[NSMutableData new];CGImageDestinationRef writer=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)preview,CFSTR("public.png"),1,NULL);BOOL written=NO;if(writer){CGImageDestinationAddImage(writer,cg,NULL);written=CGImageDestinationFinalize(writer);CFRelease(writer);}CGImageRelease(cg);NSURL*previewURL=[temporary URLByAppendingPathComponent:@"Preview.png"];if(!written||![preview writeToURL:previewURL options:NSDataWritingWithoutOverwriting error:error]){liveFail(error,@"无法保存检测预览。");return nil;}
 if(![state isEqual:fingerprint(objects,script)]){liveFail(error,@"读取期间 RAW 状态发生变化，请重新匹配。");return nil;}
 return @{@"rawURL":rawURL,@"previewURL":previewURL,@"workingTransfer":state[@"workingTransfer"],@"previewTransfer":@"encoded_sRGB",@"rawUTI":type,@"width":@((NSUInteger)w),@"height":@((NSUInteger)h),@"identifier":state[@"identifier"],@"rawByteCount":@(bytes),@"liveFingerprint":state,@"previewSource":@"native-raw-layer-content"};
}
NSDictionary*LensProbeLiveRAWExport(NSDocument*doc,id script){
 NSURL*root=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];NSURL*before=doc.fileURL;BOOL edited=doc.documentEdited;NSError*error=nil;NSDictionary*snapshot=LensReadLiveRAWLayer(doc,script,root,&error);NSMutableDictionary*r=[@{@"error":error.localizedDescription?:@"",@"fileURLUnchanged":@((!before&&!doc.fileURL)||[before isEqual:doc.fileURL]),@"editedBefore":@(edited),@"editedAfter":@(doc.documentEdited)}mutableCopy];
 if(snapshot){NSData*raw=[NSData dataWithContentsOfURL:snapshot[@"rawURL"]];unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(raw.bytes,(CC_LONG)raw.length,hash);NSMutableString*sha=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[sha appendFormat:@"%02x",hash[i]];r[@"rawSHA256"]=sha;r[@"rawBytes"]=@(raw.length);r[@"fingerprint"]=snapshot[@"liveFingerprint"];r[@"previewSource"]=snapshot[@"previewSource"];}
 NSURL*diagnostic=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:@"LensLiveProbe"] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:diagnostic withIntermediateDirectories:YES attributes:nil error:nil];[[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil]writeToURL:[diagnostic URLByAppendingPathComponent:@"LiveExport.json"] atomically:YES];[NSFileManager.defaultManager removeItemAtURL:root error:nil];return r;
}
