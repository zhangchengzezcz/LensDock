#import "LensSonyEmbeddedProfile.h"
#import "LensNativeProfileEngine.h"
#import <CommonCrypto/CommonDigest.h>
static void check(BOOL condition,NSString*name,NSMutableArray*failures){if(!condition)[failures addObject:name];}
static NSString*digest(NSData*data){unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);NSMutableString*s=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",bytes[i]];return s;}
int main(int argc,char**argv){@autoreleasepool{
 NSMutableArray*failures=[NSMutableArray new];NSData*fixtureData=[NSData dataWithContentsOfFile:@"Tests/Fixtures/Sony-embedded-metadata.json"];
 NSDictionary*fixture=[NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:nil],*reference=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"Tests/Fixtures/Sony-radial-rational-reference.json"] options:0 error:nil];
 if(!fixture||!reference)return 2;check([reference[@"sourceFixtureSHA256"]isEqual:digest(fixtureData)],@"rational reference binds source fixture",failures);
 NSDictionary*g=fixture[@"files"][0][@"expectedGroupedFields"],*source=LensSonyEmbeddedSourceEvidence(g);check(source!=nil,@"complete SubIFD source accepted",failures);
 check(![source[@"renderingEnabled"]boolValue]&&![source[@"pixelFrameVerified"]boolValue]&&[source[@"recordedFullImageSize"]isEqual:@[@6000,@4000]],@"source is not a verified pixel frame",failures);
 check(!LensSonyEmbeddedSourceEvidence(fixture[@"files"][1][@"expectedGroupedFields"]),@"A200 has no source table",failures);
 NSArray*bad=@[
  @[@"File:FileType",@"DNG"],@[@"IFD0:Make",@"NIKON"],@[@"IFD0:Model",@1],@[@"IFD0:Model",@" \n"],@[@"SubIFD:PhotometricInterpretation",@2],
  @[@"SubIFD:ImageWidth",@0],@[@"SubIFD:ImageWidth",@6000.5],@[@"SubIFD:ImageHeight",@40001],@[@"Sony:FullImageSize",@"7000 4000"],@[@"Sony:FullImageSize",@"6000 4000 1"],
  @[@"SubIFD:DistortionCorrParams",@"0"],@[@"SubIFD:DistortionCorrParams",@"1 0"],@[@"SubIFD:DistortionCorrParams",@"17 0"],
  @[@"SubIFD:DistortionCorrParams",@"11 9.0 7 14 34 63 102 155 221 304 406 528 0 0 0 0 0"],
  @[@"SubIFD:DistortionCorrParams",@"11 9999999999999999 7 14 34 63 102 155 221 304 406 528 0 0 0 0 0"],
  @[@"SubIFD:DistortionCorrParams",@"11 -32769 7 14 34 63 102 155 221 304 406 528 0 0 0 0 0"],
  @[@"SubIFD:DistortionCorrParams",@"11 32768 7 14 34 63 102 155 221 304 406 528 0 0 0 0 0"],
  @[@"SubIFD:DistortionCorrParams",@"11 9 7 14 34 63 102 155 221 304 406 528 0 0 0 0 1"],
  @[@"SubIFD:DistortionCorrParams",NSNull.null],@[@"SubIFD:ChromaticAberrationCorrParams",@"21 0 0"],
  @[@"SubIFD:ChromaticAberrationCorrParams",@"20 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0"],
 ];
 for(NSUInteger i=0;i<bad.count;i++){NSMutableDictionary*m=[g mutableCopy];m[bad[i][0]]=bad[i][1];check(!LensSonyEmbeddedSourceEvidence(m),[NSString stringWithFormat:@"malformed source %lu rejected",(unsigned long)i],failures);}
 NSMutableDictionary*makerOnly=[g mutableCopy];for(NSString*key in @[@"Distortion",@"ChromaticAberration",@"Vignetting"])[makerOnly removeObjectForKey:[NSString stringWithFormat:@"SubIFD:%@CorrParams",key]];
 check(!LensSonyEmbeddedSourceEvidence(makerOnly),@"MakerNote copies never replace missing SubIFD",failures);
 for(NSString*missing in @[@"Vignetting",@"Distortion",@"ChromaticAberration"]){NSMutableDictionary*m=[g mutableCopy];[m removeObjectForKey:[NSString stringWithFormat:@"SubIFD:%@CorrParams",missing]];NSDictionary*p=LensSonyEmbeddedSourceEvidence(m);check(p&&!p[@"tables"][missing],@"missing component remains absent",failures);}
 NSMutableDictionary*noCA=[g mutableCopy];[noCA removeObjectForKey:@"SubIFD:ChromaticAberrationCorrParams"];NSDictionary*withoutCA=LensSonyEmbeddedSourceEvidence(noCA);
 check(isfinite(LensSonyEmbeddedGeometryFactor(withoutCA,.5,0,YES,NO))&&isnan(LensSonyEmbeddedGeometryFactor(withoutCA,.5,0,NO,YES)),@"missing TCA never creates a correction",failures);
 double worst=0;for(NSDictionary*c in reference[@"cases"]){double radius=[c[@"radius"][0]doubleValue]/[c[@"radius"][1]doubleValue],expected=[c[@"expectedFactor"][0]doubleValue]/[c[@"expectedFactor"][1]doubleValue];double actual=LensSonyEmbeddedGeometryFactor(source,radius,[c[@"channel"]unsignedIntegerValue],[c[@"distortion"]boolValue],[c[@"tca"]boolValue]);double difference=fabs(expected-actual);worst=fmax(worst,difference);check(isfinite(actual)&&difference<=2e-15,@"exact rational geometry reference",failures);}
 NSMutableDictionary*zero=[g mutableCopy];for(NSString*kind in @[@"Distortion",@"ChromaticAberration",@"Vignetting"]){BOOL tca=[kind isEqual:@"ChromaticAberration"];NSMutableArray*words=[NSMutableArray arrayWithObject:tca?@"22":@"11"];for(NSUInteger i=0;i<(tca?32:16);i++)[words addObject:@"0"];zero[[NSString stringWithFormat:@"SubIFD:%@CorrParams",kind]]=[words componentsJoinedByString:@" "];}
 NSDictionary*identity=LensSonyEmbeddedSourceEvidence(zero);for(NSUInteger c=0;c<3;c++)for(NSUInteger flags=0;flags<4;flags++)check(LensSonyEmbeddedGeometryFactor(identity,.87,c,flags&1,flags&2)==1,@"zero tables are exact identity",failures);
 check(isnan(LensSonyEmbeddedGeometryFactor(source,NAN,0,YES,YES))&&isnan(LensSonyEmbeddedGeometryFactor(source,-1,0,YES,YES))&&isnan(LensSonyEmbeddedGeometryFactor(source,INFINITY,0,YES,YES))&&isnan(LensSonyEmbeddedGeometryFactor(source,.5,3,YES,YES)),@"invalid radial arguments rejected",failures);
 NSMutableDictionary*badFactor=[zero mutableCopy];badFactor[@"SubIFD:DistortionCorrParams"]=@"11 -32768 -32768 -32768 -32768 -32768 -32768 -32768 -32768 -32768 -32768 -32768 0 0 0 0 0";
 check(isnan(LensSonyEmbeddedGeometryFactor(LensSonyEmbeddedSourceEvidence(badFactor),.5,0,YES,NO)),@"nonpositive geometry factor rejected",failures);
 NSMutableArray*rawChecks=[NSMutableArray new],*missing=[NSMutableArray new];
 for(NSDictionary*item in fixture[@"files"]){NSURL*raw=[NSURL fileURLWithPath:[@"Tests/PrivateRAW" stringByAppendingPathComponent:item[@"file"]]];if(![NSFileManager.defaultManager fileExistsAtPath:raw.path]){[missing addObject:item[@"file"]];continue;}
  NSString*before=digest([NSData dataWithContentsOfURL:raw]);check([before isEqual:item[@"sha256"]],@"pinned complete RAW hash",failures);
  NSDictionary*m=LensReadRawMetadata(raw,[NSURL fileURLWithPath:@"Resources/LensBridge/exiftool/exiftool"],nil),*expected=LensSonyEmbeddedSourceEvidence(item[@"expectedGroupedFields"]);BOOL readback=m&&(expected?[m[@"embeddedLensCorrectionSource"]isEqual:expected]:!m[@"embeddedLensCorrectionSource"]);check(readback,@"production metadata preserves validated grouped source",failures);
  NSArray*native=m[@"nativeCorrectionSupport"][@"nativePixelSize"];check([native isKindOfClass:NSArray.class]&&native.count==2&&[native[0]doubleValue]>0&&[native[1]doubleValue]>0,@"public decoder native frame recorded",failures);
  if([item[@"file"]isEqual:@"ILCE-6000.ARW"])check([native isEqual:@[@6000,@4000]],@"A6000 native size matches verified host canvas",failures);
  check(!m[@"DistortionCorrParams"]&&!m[@"ChromaticAberrationCorrParams"]&&!m[@"VignettingCorrParams"],@"no ungrouped correction tables leak",failures);
  NSMutableDictionary*without=[m mutableCopy];[without removeObjectForKey:@"embeddedLensCorrectionSource"];NSURL*db=[NSURL fileURLWithPath:@"Resources/LensBridge/db"],*lib=[NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"];
  NSDictionary*a=LensNativeProfilePlanIncludingGeometry(m,db,lib,96,64,nil),*b=LensNativeProfilePlanIncludingGeometry(without,db,lib,96,64,nil);BOOL same=(!a&&!b)||[a isEqual:b];check(same,@"source-only metadata leaves existing plan unchanged",failures);
  BOOL unchanged=[before isEqual:digest([NSData dataWithContentsOfURL:raw])];check(unchanged,@"original RAW unchanged",failures);
  [rawChecks addObject:@{@"fixture":item[@"file"],@"sha256":before,@"productionReadbackPassed":@(readback),@"sourcePresent":@(expected!=nil),@"currentPlanUnchanged":@(same),@"originalUnchanged":@(unchanged),@"nativePixelSize":native?:@[],@"recordedFullImageSize":expected[@"recordedFullImageSize"]?:@[],@"pixelFrameVerified":@NO}];
 }
 NSDictionary*out=@{@"scope":@"Validated original table reading and coordinate-free D/TCA arithmetic only; no pixel-frame selection, vignette gain, rendered optical acceptance or added physical-lens coverage",@"rationalCases":@([reference[@"cases"]count]),@"maximumFactorAbsoluteError":@(worst),@"malformedSourceCases":@(bad.count),@"zeroTablesExactIdentity":@YES,@"rawChecks":rawChecks,@"missingOptionalRAW":missing,@"productionPixelRouteEnabled":@NO,@"vignettingGainImplemented":@NO,@"failures":failures};
 NSString*output=argc>1?@(argv[1]):@"Build/Tests/sony-embedded-model-verification.json";[[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil]writeToFile:output atomically:YES];
 printf("Sony embedded source/model checks: %lu failures; %lu complete RAW readbacks.\n",(unsigned long)failures.count,(unsigned long)rawChecks.count);return failures.count?1:0;
}}
