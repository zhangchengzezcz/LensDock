#pragma once
#import <Foundation/Foundation.h>
#import <math.h>
#import <stdint.h>
#import <string.h>

// Old documents retain their dense field. A compact field is usable only with
// its explicit encoding and valid node dimensions, never by guessing from size.
static inline BOOL LensGainMapDimensions(NSDictionary *report,NSUInteger width,NSUInteger height,NSUInteger *mapWidth,NSUInteger *mapHeight){
 id encoding=report[@"gainMapEncoding"];
 if(!encoding){*mapWidth=width;*mapHeight=height;return width&&height;}
 if(![encoding isEqual:@"linear-gain-Rf-bottom-up-grid-v1"])return NO;
 id x=report[@"gainMapWidth"],y=report[@"gainMapHeight"];
 if(![x isKindOfClass:NSNumber.class]||![y isKindOfClass:NSNumber.class])return NO;
 double w=[x doubleValue],h=[y doubleValue];
 if(!isfinite(w)||!isfinite(h)||floor(w)!=w||floor(h)!=h||w<2||h<2||w>width||h>height)return NO;
 *mapWidth=(NSUInteger)w;*mapHeight=(NSUInteger)h;return YES;
}

// Lossless coding changes only byte layout: float bit-pattern deltas are split
// into byte planes before LZFSE. No gain value is quantized or discarded.
static inline NSData *LensEncodeGainGrid(NSData *data,NSError **error){
 if(!data.length||data.length%4)return nil;
 NSUInteger count=data.length/4;NSMutableData *planes=[NSMutableData dataWithLength:data.length];unsigned char *bytes=planes.mutableBytes;const unsigned char *source=data.bytes;uint32_t previous=0;
 for(NSUInteger i=0;i<count;i++){uint32_t value;memcpy(&value,source+i*4,4);uint32_t delta=value-previous;previous=value;for(int b=0;b<4;b++)bytes[b*count+i]=(unsigned char)(delta>>(b*8));}
 return [planes compressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:error];
}
static inline NSData *LensDecodedGainData(NSDictionary *profile,NSError **error){
 if(profile[@"linearGainFloat32BottomUp"])return [profile[@"linearGainFloat32BottomUp"]isKindOfClass:NSData.class]?profile[@"linearGainFloat32BottomUp"]:nil;
 if(![profile[@"gainGridLosslessEncoding"]isEqual:@"float32-delta-byteplanes-LZFSE-v1"]||![profile[@"gainGridLosslessData"]isKindOfClass:NSData.class])return nil;
 NSDictionary *report=profile[@"matchedProfile"]?:profile[@"report"];NSUInteger w=[report[@"width"]unsignedIntegerValue],h=[report[@"height"]unsignedIntegerValue],gw=0,gh=0;
 if(w>16000||h>16000||!LensGainMapDimensions(report,w,h,&gw,&gh))return nil;
 NSData *planes=[profile[@"gainGridLosslessData"]decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:error];if(planes.length!=gw*gh*4)return nil;
 NSUInteger count=gw*gh;const unsigned char *bytes=planes.bytes;NSMutableData *decoded=[NSMutableData dataWithLength:planes.length];unsigned char *out=decoded.mutableBytes;uint32_t previous=0;
 for(NSUInteger i=0;i<count;i++){uint32_t delta=0;for(int b=0;b<4;b++)delta|=(uint32_t)bytes[b*count+i]<<(b*8);uint32_t value=previous+delta;previous=value;memcpy(out+i*4,&value,4);}
 return decoded;
}
