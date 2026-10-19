#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
static inline BOOL LensHostVersionSupported(NSString*version){
 if(![version isKindOfClass:NSString.class]||!version.length)return NO;
 NSArray*parts=[version componentsSeparatedByString:@"."];if(parts.count>4)return NO;
 NSCharacterSet*invalid=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"]invertedSet];
 for(NSString*p in parts)if(!p.length||[p rangeOfCharacterFromSet:invalid].location!=NSNotFound||p.length>9)return NO;
 return [version compare:@"4.3" options:NSNumericSearch]!=NSOrderedAscending;
}
typedef struct{void*type;uintptr_t state;} LensHostMetadataResponse;
typedef LensHostMetadataResponse __attribute__((swiftcall))(*LensHostMetadataGetter)(uintptr_t);
static inline BOOL LensHostValueLayout(const char*symbol,uintptr_t size,uintptr_t stride){
 LensHostMetadataGetter get=dlsym(RTLD_DEFAULT,symbol);if(!get)return NO;
 void*type=get(0).type;if(!type)return NO;uintptr_t*witness=*((uintptr_t**)type-1);
 return witness&&witness[8]==size&&witness[9]==stride;
}
NSDictionary*LensInspectHostCompatibility(NSDictionary*contract,NSString*version,BOOL requireUI);
NSDictionary*LensHostCompatibilityReport(void);
BOOL LensHostCompatibilityReady(void);
