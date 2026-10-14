#import "LensNativeDocument.h"
#import <sqlite3.h>
#import <math.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
NSString*LensNativeRAWExtension(NSString*identifier){
 if(![identifier isKindOfClass:NSString.class]||!identifier.length)return nil;
 UTType*type=[UTType typeWithIdentifier:identifier];if(![type conformsToType:UTTypeRAWImage])return nil;
 NSString*extension=type.preferredFilenameExtension;
 NSCharacterSet*invalid=[[NSCharacterSet alphanumericCharacterSet]invertedSet];
 if(!extension.length||extension.length>10||[extension rangeOfCharacterFromSet:invalid].location!=NSNotFound)return nil;
 return extension.uppercaseString;
}
static void docFail(NSError**error,NSString*message){if(error)*error=[NSError errorWithDomain:@"LensBridgeDocument" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];}
static NSData*member(NSURL*url,NSString*name,NSError**error){
 NSTask*t=[NSTask new];t.executableURL=[NSURL fileURLWithPath:@"/usr/bin/unzip"];t.arguments=@[@"-p",url.path,name];NSPipe*out=NSPipe.pipe;t.standardOutput=out;t.standardError=NSFileHandle.fileHandleWithNullDevice;
 if(![t launchAndReturnError:error])return nil;NSMutableData*d=[NSMutableData new];
 for(;;){NSData*chunk=[out.fileHandleForReading readDataOfLength:65536];if(!chunk.length)break;[d appendData:chunk];if(d.length>256*1024*1024){[t terminate];[t waitUntilExit];docFail(error,@"原生资源超出验证大小。");return nil;}}
 [t waitUntilExit];if(t.terminationStatus){docFail(error,@"原生文档资源读取失败。");return nil;}return d;
}
static NSData*value(sqlite3*db,NSString*sql,NSString*arg){
 sqlite3_stmt*q=NULL;NSData*d=nil;if(sqlite3_prepare_v2(db,sql.UTF8String,-1,&q,NULL)!=SQLITE_OK)return nil;
 if(arg)sqlite3_bind_text(q,1,arg.UTF8String,-1,SQLITE_TRANSIENT);
 if(sqlite3_step(q)==SQLITE_ROW){const void*b=sqlite3_column_blob(q,0);int n=sqlite3_column_bytes(q,0);if(b&&n>0)d=[NSData dataWithBytes:b length:n];}
 sqlite3_finalize(q);return d;
}
static BOOL readBigDoubles(NSData*d,int count,double*out){if(d.length!=12+count*8||memcmp(d.bytes,"4-tP",4))return NO;for(int i=0;i<count;i++){uint64_t u=0;memcpy(&u,(const char*)d.bytes+12+i*8,8);u=CFSwapInt64BigToHost(u);memcpy(out+i,&u,8);}return YES;}
NSDictionary*LensReadNativeRAWLayer(NSURL*pxd,NSString*uuid,NSURL*temp,NSError**error){
 NSRegularExpression*pattern=[NSRegularExpression regularExpressionWithPattern:@"^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$" options:0 error:nil];
 if(!uuid||![pattern numberOfMatchesInString:uuid options:0 range:NSMakeRange(0,uuid.length)]){docFail(error,@"无法确定选中的原生图层。");return nil;}
 if(![NSFileManager.defaultManager createDirectoryAtURL:temp withIntermediateDirectories:YES attributes:nil error:error])return nil;
 NSData*metadata=member(pxd,@"metadata.info",error);if(!metadata)return nil;
 NSURL*dbURL=[temp URLByAppendingPathComponent:@"metadata.info"];if(![metadata writeToURL:dbURL options:NSDataWritingWithoutOverwriting error:error])return nil;
 sqlite3*db=NULL;if(sqlite3_open_v2(dbURL.fileSystemRepresentation,&db,SQLITE_OPEN_READONLY,NULL)!=SQLITE_OK){if(db)sqlite3_close(db);docFail(error,@"无法读取原生文档索引。");return nil;}
 NSDictionary*result=nil;
 {
 NSString*prefix=@"select value from layer_info where layer_id=(select id from document_layers where identifier=?) and key=";
 NSData*raw=value(db,[prefix stringByAppendingString:@"'raw-parameters-data'"],uuid);
 NSArray*params=raw?[NSJSONSerialization JSONObjectWithData:raw options:0 error:nil]:nil;
 if(![params isKindOfClass:NSArray.class]||params.count!=2||![params[1] isKindOfClass:NSDictionary.class]){docFail(error,@"请选择原生 RAW 图层。");goto done;}
 if([params[1][@"lc"] boolValue]){docFail(error,@"原厂镜头矫正已启用，停止叠加配置以避免重复矫正。");goto done;}
 // Existing effects are read through the live native state and preserved by the correction composer.
 double size[2],scale[2],angle,backing;
 if(!readBigDoubles(value(db,[prefix stringByAppendingString:@"'size'"],uuid),2,size)||!readBigDoubles(value(db,[prefix stringByAppendingString:@"'scale'"],uuid),2,scale)||!readBigDoubles(value(db,[prefix stringByAppendingString:@"'angle'"],uuid),1,&angle)||!readBigDoubles(value(db,[prefix stringByAppendingString:@"'backingScale'"],uuid),1,&backing)||scale[0]!=1||scale[1]!=1||angle!=0||(!isfinite(size[0])||!isfinite(size[1])||!isfinite(backing)||backing<=0||size[0]<=0||size[1]<=0||size[0]*backing>16000||size[1]*backing>16000)){docFail(error,@"图层旋转与缩放尚未验证。");goto done;}
 uint64_t width=(uint64_t)(size[0]*backing),height=(uint64_t)(size[1]*backing);
 if(!width||!height||width>16000||height>16000){docFail(error,@"RAW 图层尺寸不在已验证范围。");goto done;}
 NSData*uti=value(db,@"select content_uti from storable_info where layer_identifier=? and identifier='OriginalContentSource'",uuid);
 NSString*type=[[NSString alloc]initWithData:uti encoding:NSUTF8StringEncoding];
 NSString*extension=LensNativeRAWExtension(type);
 if(!extension){docFail(error,@"此原始资源没有可识别的 RAW 类型。");goto done;}
 NSData*original=member(pxd,[NSString stringWithFormat:@"data/%@-OriginalContentSource",uuid],error);if(!original)goto done;
 NSURL*rawURL=[temp URLByAppendingPathComponent:[@"Original." stringByAppendingString:extension]];
 if(![original writeToURL:rawURL options:NSDataWritingWithoutOverwriting error:error])goto done;
 NSString*transfer=@"unsupported";NSData*format=value(db,@"select value from document_info where key='format'",nil);
 NSRange signature=[format rangeOfData:[NSData dataWithBytes:"acsp" length:4] options:0 range:NSMakeRange(0,format.length)];
 if(signature.location!=NSNotFound&&signature.location>=36){NSUInteger start=signature.location-36;uint32_t length=0;memcpy(&length,(const char*)format.bytes+start,4);length=CFSwapInt32BigToHost(length);
  if(length>=128&&start+length<=format.length){NSData*icc=[format subdataWithRange:NSMakeRange(start,length)];CGColorSpaceRef space=CGColorSpaceCreateWithICCData((__bridge CFDataRef)icc);
   if(space){NSString*name=CFBridgingRelease(CGColorSpaceCopyName(space));CGColorSpaceRelease(space);
    if([@[@"kCGColorSpaceDisplayP3",@"kCGColorSpaceSRGB",@"kCGColorSpaceExtendedSRGB"]containsObject:name])transfer=@"encoded_sRGB";
    if([@[@"kCGColorSpaceExtendedLinearSRGB",@"kCGColorSpaceLinearSRGB",@"kCGColorSpaceExtendedLinearDisplayP3"]containsObject:name])transfer=@"linear";
   }
  }
 }
 NSData*preview=member(pxd,@"QuickLook/Preview.heic",nil);NSURL*previewURL=[temp URLByAppendingPathComponent:@"Preview.heic"];
 if(preview)[preview writeToURL:previewURL options:NSDataWritingWithoutOverwriting error:nil];
 result=@{@"previewURL":previewURL,@"workingTransfer":transfer,@"rawURL":rawURL,@"rawUTI":type,@"width":@(width),@"height":@(height),@"identifier":uuid,@"rawByteCount":@(original.length)};
 }
done:
 sqlite3_close(db);return result;
}
