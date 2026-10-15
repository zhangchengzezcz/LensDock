#pragma once
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import "lensfun.h"

// Content identities never include a pointer, query score or localized display
// choice. Optical changes invalidate a saved manual selection.
static NSArray*LensIdentityNames(lfMLstr value){
 if(!value||!*value)return @[];NSMutableSet*names=[NSMutableSet setWithObject:@(value)];const char*p=value+strlen(value)+1;
 for(NSUInteger i=0;i<64&&*p;i++){p+=strlen(p)+1;if(!*p)break;[names addObject:@(p)];p+=strlen(p)+1;}
 return [names.allObjects sortedArrayUsingSelector:@selector(compare:)];
}
static NSString*LensContentID(NSString*kind,id content){
 if(![NSJSONSerialization isValidJSONObject:content])return nil;
 NSData*data=[NSJSONSerialization dataWithJSONObject:content options:NSJSONWritingSortedKeys error:nil];if(!data)return nil;
 unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString*s=[NSMutableString stringWithFormat:@"%@-v1-",kind];
 for(NSUInteger i=0;i<sizeof(digest);i++)[s appendFormat:@"%02x",digest[i]];return s;
}
static NSArray*LensSortedPoints(NSArray*points){
 NSMutableArray*encoded=[NSMutableArray new];for(id point in points){if(![NSJSONSerialization isValidJSONObject:point])return points;NSData*data=[NSJSONSerialization dataWithJSONObject:point options:0 error:nil];if(!data)return points;[encoded addObject:[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]];}return [encoded sortedArrayUsingSelector:@selector(compare:)];
}
static NSArray*LensModelledPoints(NSArray*points){
 NSArray*sorted=LensSortedPoints(points);NSMutableOrderedSet*models=[NSMutableOrderedSet new];for(NSArray*point in points)if(point.count)[models addObject:point[0]];
 // Lensfun's first calibration model controls interpolation when a record
 // contains different models. Preserve that priority while normalizing the
 // order of points belonging to one model.
 if(models.count>1){NSMutableArray*out=[NSMutableArray arrayWithObject:@{@"modelPriority":models.array}];[out addObjectsFromArray:sorted];return out;}return sorted;
}
static NSString*LensCameraProfileID(const lfCamera*c){
 return LensContentID(@"camera",@[@"lensfun-0.3.4",LensIdentityNames(c->Maker),LensIdentityNames(c->Model),LensIdentityNames(c->Variant),c->Mount?@(c->Mount):@"",@(c->CropFactor)]);
}
static NSString*LensLensProfileID(const lfLens*l){
 NSMutableArray*mounts=[NSMutableArray new],*d=[NSMutableArray new],*t=[NSMutableArray new],*v=[NSMutableArray new],*crop=[NSMutableArray new],*fov=[NSMutableArray new],*real=[NSMutableArray new];
 if(l->Mounts)for(NSUInteger i=0;l->Mounts[i];i++)[mounts addObject:@(l->Mounts[i])];
 if(l->CalibDistortion)for(NSUInteger i=0;l->CalibDistortion[i];i++){lfLensCalibDistortion*p=l->CalibDistortion[i];[d addObject:@[@(p->Model),@(p->Focal),@(p->Terms[0]),@(p->Terms[1]),@(p->Terms[2])]];}
 if(l->CalibTCA)for(NSUInteger i=0;l->CalibTCA[i];i++){lfLensCalibTCA*p=l->CalibTCA[i];[t addObject:@[@(p->Model),@(p->Focal),@(p->Terms[0]),@(p->Terms[1]),@(p->Terms[2]),@(p->Terms[3]),@(p->Terms[4]),@(p->Terms[5])]];}
 if(l->CalibVignetting)for(NSUInteger i=0;l->CalibVignetting[i];i++){lfLensCalibVignetting*p=l->CalibVignetting[i];[v addObject:@[@(p->Model),@(p->Focal),@(p->Aperture),@(p->Distance),@(p->Terms[0]),@(p->Terms[1]),@(p->Terms[2])]];}
 if(l->CalibCrop)for(NSUInteger i=0;l->CalibCrop[i];i++){lfLensCalibCrop*p=l->CalibCrop[i];[crop addObject:@[@(p->CropMode),@(p->Focal),@(p->Crop[0]),@(p->Crop[1]),@(p->Crop[2]),@(p->Crop[3])]];}
 if(l->CalibFov)for(NSUInteger i=0;l->CalibFov[i];i++){lfLensCalibFov*p=l->CalibFov[i];[fov addObject:@[@(p->Focal),@(p->FieldOfView)]];}
 if(l->CalibRealFocal)for(NSUInteger i=0;l->CalibRealFocal[i];i++){lfLensCalibRealFocal*p=l->CalibRealFocal[i];[real addObject:@[@(p->Focal),@(p->RealFocal)]];}
 return LensContentID(@"lens",@[@"lensfun-0.3.4",LensIdentityNames(l->Maker),LensIdentityNames(l->Model),[mounts sortedArrayUsingSelector:@selector(compare:)],@(l->CropFactor),@(l->AspectRatio),@(l->Type),@(l->CenterX),@(l->CenterY),@(l->MinFocal),@(l->MaxFocal),@(l->MinAperture),@(l->MaxAperture),LensModelledPoints(d),LensModelledPoints(t),LensModelledPoints(v),LensSortedPoints(crop),LensSortedPoints(fov),LensSortedPoints(real)]);
}
static NSString*LensProjectionName(lfLensType type){
 NSArray*names=@[@"未知投影",@"直线投影",@"等距鱼眼",@"圆柱投影",@"等距圆柱",@"正交鱼眼",@"立体鱼眼",@"等面积鱼眼",@"Thoby 鱼眼"];return type>=0&&type<names.count?names[type]:names[0];
}
