#import <Foundation/Foundation.h>
#import <math.h>

// Camera-recorded source tables and coordinate-free radial arithmetic only.
// These functions do not select a pixel frame, create a correction plan or
// enable rendering. In particular no vignette gain interpretation is provided.
static inline NSArray<NSNumber*>*LensSonyIntegerWords(id value,NSUInteger limit,long long bound){
 if(![value isKindOfClass:NSString.class]||![value length]||[value length]>4096)return nil;
 NSArray*words=[value componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];NSMutableArray*out=[NSMutableArray new];
 for(NSString*word in words){
  if(!word.length)continue;if(out.count==limit)return nil;NSUInteger i=0;BOOL negative=NO;
  if([word characterAtIndex:0]=='-'||[word characterAtIndex:0]=='+'){negative=[word characterAtIndex:0]=='-';i++;}
  if(i==word.length)return nil;long long number=0;
  for(;i<word.length;i++){unichar c=[word characterAtIndex:i];if(c<'0'||c>'9'||number>(bound-(c-'0'))/10)return nil;number=number*10+c-'0';}
  if(number>bound)return nil;[out addObject:@(negative?-number:number)];
 }
 return out.count?out:nil;
}
static inline NSDictionary*LensSonySourceTable(id value,BOOL tca){
 NSArray*all=LensSonyIntegerWords(value,tca?33:17,32768);if(!all)return nil;
 NSInteger count=[all[0]integerValue],n=tca?count/2:count;
 if(n<2||n>16||(tca&&count%2)||(all.count!=(NSUInteger)count+1&&all.count!=(tca?33u:17u)))return nil;
 for(NSUInteger i=1;i<all.count;i++){NSInteger v=[all[i]integerValue];if(v < -32768||v>32767||(i>(NSUInteger)count&&v))return nil;}
 if(tca)return @{@"nodeCount":@(n),@"red":[all subarrayWithRange:NSMakeRange(1,n)],@"blue":[all subarrayWithRange:NSMakeRange(1+n,n)]};
 return @{@"nodeCount":@(n),@"values":[all subarrayWithRange:NSMakeRange(1,n)]};
}
static inline BOOL LensSonyDimension(id value){
 return [value isKindOfClass:NSNumber.class]&&isfinite([value doubleValue])&&[value doubleValue]>=16&&[value doubleValue]<=40000&&floor([value doubleValue])==[value doubleValue];
}
static inline NSDictionary*LensSonyEmbeddedSourceEvidence(NSDictionary*grouped){
 if(![grouped isKindOfClass:NSDictionary.class]||![grouped[@"File:FileType"]isEqual:@"ARW"])return nil;
 id maker=grouped[@"IFD0:Make"],model=grouped[@"IFD0:Model"];
 if(![maker isKindOfClass:NSString.class]||![[maker stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].uppercaseString isEqual:@"SONY"]||![model isKindOfClass:NSString.class]||[model length]>128)return nil;
 model=[model stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(![model length])return nil;
 id photo=grouped[@"SubIFD:PhotometricInterpretation"],width=grouped[@"SubIFD:ImageWidth"],height=grouped[@"SubIFD:ImageHeight"];
 if(![photo isKindOfClass:NSNumber.class]||[photo doubleValue]!=32803||!LensSonyDimension(width)||!LensSonyDimension(height)||[width doubleValue]*[height doubleValue]>400000000)return nil;
 NSMutableDictionary*tables=[NSMutableDictionary new];NSUInteger commonCount=0;
 for(NSString*kind in @[@"Distortion",@"ChromaticAberration",@"Vignetting"]){
  NSString*key=[NSString stringWithFormat:@"SubIFD:%@CorrParams",kind];id raw=grouped[key];if(!raw)continue;
  NSDictionary*table=LensSonySourceTable(raw,[kind isEqual:@"ChromaticAberration"]);if(!table)return nil;
  NSUInteger n=[table[@"nodeCount"]unsignedIntegerValue];if(commonCount&&commonCount!=n)return nil;commonCount=n;
  tables[kind]=table;
 }
 if(!tables.count)return nil;
 NSMutableDictionary*evidence=[@{@"schema":@1,@"provider":@"sony-subifd-radial-source-v1",@"cameraMake":@"SONY",@"cameraModel":model,@"sourceGroup":@"SubIFD",@"storageWidth":width,@"storageHeight":height,@"tables":tables,@"pixelFrameVerified":@NO,@"renderingEnabled":@NO}mutableCopy];
 id full=grouped[@"Sony:FullImageSize"];
 if(full){NSArray*size=LensSonyIntegerWords(full,2,40000);if(size.count!=2||!LensSonyDimension(size[0])||!LensSonyDimension(size[1])||[size[0]doubleValue]>[width doubleValue]||[size[1]doubleValue]>[height doubleValue])return nil;evidence[@"recordedFullImageSize"]=size;}
 return evidence;
}
static inline double LensSonyRadialCode(NSDictionary*table,NSString*component,double radius){
 if(![table isKindOfClass:NSDictionary.class]||!isfinite(radius)||radius<0)return NAN;
 id count=table[@"nodeCount"],values=table[component];if(![count isKindOfClass:NSNumber.class]||floor([count doubleValue])!=[count doubleValue])return NAN;
 NSInteger n=[count integerValue];if(n<2||n>16||![values isKindOfClass:NSArray.class]||[values count]!=(NSUInteger)n)return NAN;
 for(id value in values)if(![value isKindOfClass:NSNumber.class]||!isfinite([value doubleValue])||floor([value doubleValue])!=[value doubleValue]||[value doubleValue]<-32768||[value doubleValue]>32767)return NAN;
 // Recorded nodes are half a bin beyond each i/(n-1) position. Keep the
 // endpoint constant outside that interval; never extrapolate a new curve.
 double position=radius*(n-1)-.5;if(position<=0)return [values[0]doubleValue];if(position>=n-1)return [values[n-1]doubleValue];
 NSUInteger left=(NSUInteger)floor(position);double fraction=position-left;
 return [values[left]doubleValue]*(1-fraction)+[values[left+1]doubleValue]*fraction;
}
static inline double LensSonyEmbeddedGeometryFactor(NSDictionary*source,double radius,NSUInteger channel,BOOL distortion,BOOL tca){
 if(![source isKindOfClass:NSDictionary.class]||![source[@"provider"]isEqual:@"sony-subifd-radial-source-v1"]||channel>2||!isfinite(radius)||radius<0)return NAN;
 NSDictionary*tables=source[@"tables"];if(![tables isKindOfClass:NSDictionary.class])return NAN;double factor=1;
 if(distortion){double code=LensSonyRadialCode(tables[@"Distortion"],@"values",radius);factor=1+ldexp(code,-14);if(!isfinite(factor)||factor<=0)return NAN;}
 if(tca){double red=LensSonyRadialCode(tables[@"ChromaticAberration"],@"red",radius),blue=LensSonyRadialCode(tables[@"ChromaticAberration"],@"blue",radius);if(!isfinite(red)||!isfinite(blue))return NAN;factor*=1+ldexp(channel==0?red:channel==2?blue:0,-21);}
 return isfinite(factor)&&factor>0?factor:NAN;
}
