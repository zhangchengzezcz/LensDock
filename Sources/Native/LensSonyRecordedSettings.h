#import <Foundation/Foundation.h>
#import <math.h>

// Capture-menu facts only. "Auto" is not proof of a baked correction, and
// "Off" is not proof about mandatory processing inside a decoder. Never use
// this reader to manufacture a calibration or silently enable/disable one.
static inline NSDictionary *LensSonyRecordedCorrectionSettings(NSDictionary *grouped) {
    if (![grouped isKindOfClass:NSDictionary.class] || ![grouped[@"File:FileType"] isEqual:@"ARW"]) return nil;
    NSString *make=grouped[@"IFD0:Make"], *model=grouped[@"IFD0:Model"];
    if (![make isKindOfClass:NSString.class] || ![[make stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].uppercaseString isEqual:@"SONY"] ||
        ![model isKindOfClass:NSString.class] || model.length>128) return nil;
    model=[model stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    id photo=grouped[@"SubIFD:PhotometricInterpretation"];
    if (!model.length || ![photo isKindOfClass:NSNumber.class] || [photo doubleValue]!=32803) return nil;
    NSDictionary *tags=@{@"distortion":@"SubIFD:DistortionCorrection",@"tca":@"SubIFD:ChromaticAberrationCorrection",@"vignetting":@"SubIFD:VignettingCorrection"};
    NSMutableDictionary *components=[NSMutableDictionary new];BOOL any=NO;
    for (NSString *kind in @[@"distortion",@"tca",@"vignetting"]) {
        id value=grouped[tags[kind]];
        if (!value) { components[kind]=@{@"setting":@"not-recorded"}; continue; }
        any=YES;
        if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID() ||
            !isfinite([value doubleValue]) || floor([value doubleValue])!=[value doubleValue] || [value doubleValue]<-32768 || [value doubleValue]>32767) {
            components[kind]=@{@"setting":@"invalid"};continue;
        }
        NSInteger code=[value integerValue];NSString *setting=@"unknown";
        if ([kind isEqual:@"vignetting"]) {
            if(code==256)setting=@"off";else if(code==257||code==272)setting=@"auto";else if(code==511)setting=@"unavailable";
        } else {
            if(code==0)setting=@"off";else if(code==1)setting=@"auto";else if(code==255)setting=@"unavailable";
            else if([kind isEqual:@"distortion"]&&code==17)setting=@"auto-fixed-by-lens";
        }
        components[kind]=@{@"setting":setting,@"recordedCode":value};
    }
    if(!any)return nil;
    return @{@"schema":@1,@"provider":@"sony-subifd-recorded-settings-v1",@"sourceGroup":@"SubIFD",@"cameraMake":@"SONY",@"cameraModel":model,
        @"components":components,@"provesBakedCorrection":@NO,@"provesDecoderCorrection":@NO};
}
