#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import "LensNativeDocument.h"
#import "LensNativeProfileEngine.h"
#import "LensNativeState.h"
#import "LensCorrectionSettings.h"
#import "LensCornerAssessment.h"
#import "LensLiveDocument.h"
#import "LensRecommendationPolicy.h"
#import "LensHostDiagnostics.h"
#import "LensGainMap.h"
#import "LensCalibrationEvidence.h"
#import "LensProfilePicker.h"
#import "LensCaptureParameters.h"
#import "LensConstrainedCrop.h"
Class LensRegisterVignettingFilter(void);
static id getter(id obj,NSString*name){SEL s=NSSelectorFromString(name);Method m=class_getInstanceMethod([obj class],s);if(!m||method_getNumberOfArguments(m)!=2)return nil;char*t=method_copyReturnType(m);BOOL object=t&&t[0]=='@';free(t);return object?((id(*)(id,SEL))objc_msgSend)(obj,s):nil;}
static id rawLayer(id script){Ivar i=class_getInstanceVariable([script class],"layer");if(!i)return nil;void*p=NULL;memcpy(&p,(char*)(__bridge void*)script+ivar_getOffset(i),8);return (__bridge id)p;}
static id findLayer(id holder,NSString*uuid,int depth){if(depth>50)return nil;for(id script in getter(holder,@"scriptLayers")){if([getter(script,@"scriptUniqueID")isEqual:uuid])return script;id found=findLayer(script,uuid,depth+1);if(found)return found;}return nil;}
static NSTextField*label(NSString*text,NSRect frame,CGFloat size,NSFontWeight weight){NSTextField*v=[NSTextField labelWithString:text];v.frame=frame;v.font=[NSFont systemFontOfSize:size weight:weight];v.textColor=NSColor.labelColor;v.lineBreakMode=NSLineBreakByWordWrapping;v.maximumNumberOfLines=0;return v;}
static NSView*card(NSRect frame){NSView*v=[[NSView alloc]initWithFrame:frame];v.wantsLayer=YES;v.layer.cornerRadius=14;v.layer.backgroundColor=[NSColor colorWithWhite:1 alpha:.065].CGColor;v.layer.borderWidth=.7;v.layer.borderColor=[NSColor colorWithWhite:1 alpha:.09].CGColor;v.autoresizingMask=NSViewWidthSizable;return v;}
static BOOL sameJSON(NSData*a,NSData*b){return LensEffectsEquivalent(a,b);}
static NSString*amountText(double value,NSUInteger index){
 NSNumberFormatter*f=[NSNumberFormatter new];f.numberStyle=NSNumberFormatterDecimalStyle;f.usesGroupingSeparator=NO;f.maximumFractionDigits=3;return [NSString stringWithFormat:@"%@%@",[f stringFromNumber:@(value)],index==0?@"%":index==1?@" px":@" EV"];
}
static double niceMaximum(double value){if(value<=0||!isfinite(value))return 1;double scale=pow(10,floor(log10(value))),n=value/scale,result=1;for(NSNumber*step in @[@1,@1.25,@1.5,@2,@2.5,@3,@4,@5,@6,@8,@10])if(step.doubleValue<=n)result=step.doubleValue;return result*scale;}
static NSString*displayNumber(NSNumber*number){
 if(!number)return @"—";NSNumberFormatter*f=[NSNumberFormatter new];f.numberStyle=NSNumberFormatterDecimalStyle;f.usesGroupingSeparator=NO;f.maximumFractionDigits=2;return [f stringFromNumber:number]?:@"—";
}
static NSDictionary*pickerReboundPlan(NSDictionary*generated,NSDictionary*context,NSDictionary*metadata){
 if(!generated)return nil;NSMutableDictionary*p=[generated mutableCopy],*r=[generated[@"report"]mutableCopy];
 for(NSString*key in @[@"workingTransfer",@"assessmentPreviewSource",@"assessmentPreviewTransfer"])if(context[@"report"][key])r[key]=context[@"report"][key];
 for(NSString*key in @[@"baseMetadata",@"parameterOverrides",@"liveFingerprint",@"sourceBinding",@"assessmentPreviewData"])if(context[key])p[key]=context[key];
 if([context[@"parameterOverrides"]boolValue]&&LensPositiveCaptureNumber(metadata[@"FocusDistance"]))r[@"distance_source"]=@"manual";
 p[@"report"]=r;p[@"metadata"]=metadata;
 if([p[@"assessmentPreviewData"]length]){NSDictionary*assessment=LensAssessCornerPreviewData(p[@"assessmentPreviewData"],p[@"linearGainFloat32BottomUp"],[r[@"width"]unsignedIntegerValue],[r[@"height"]unsignedIntegerValue],r[@"assessmentPreviewTransfer"]?:r[@"workingTransfer"],nil);if(assessment){NSMutableDictionary*a=[assessment mutableCopy];a[@"assessmentSource"]=r[@"assessmentPreviewSource"]?:@"saved_preview";p[@"cornerAssessment"]=a;}}
 return p;
}

@interface LensPanelController:NSObject<NSWindowDelegate>
@property NSPanel*panel;
@property(weak)NSWindow*hostWindow;
@property NSTextField*cameraLabel,*lensLabel,*parameterLabel,*badge,*status,*riskLabel;
@property NSArray<NSButton*>*checks,*recommendButtons;
@property NSArray<NSView*>*recommendMarkers;
@property NSArray<NSSlider*>*sliders;
@property NSArray<NSTextField*>*percents,*availability,*hints,*unitLabels,*relativeFields;
@property NSTextField*focalField,*apertureField,*distanceField,*detailsNote;
@property NSButton*applyButton,*autoButton,*detailsButton,*cropButton;
@property NSButton*rematchButton;
@property NSButton*profileButton;
@property LensProfilePicker*profilePicker;
@property NSDictionary*matchContext;
@property NSProgressIndicator*activity;
@property NSDictionary*plan,*metadata;
@property(weak)NSDocument*document;
@property NSString*layerIdentifier;
@property NSUInteger generation;
@property BOOL busy,userTouched,hasOwnEffect;
@property NSPopover*details;
@property NSMapTable<NSDocument*,NSUndoManager*>*undoManagers;
@property NSButton*undoButton,*redoButton;
- (NSDocument*)activeDocument;
- (void)show:(id)sender;
- (void)match:(id)sender;
- (void)changed:(id)sender;
- (void)apply:(id)sender;
- (void)automatic:(id)sender;
- (void)showDetails:(id)sender;
- (void)updateParameters:(id)sender;
- (void)useRecommendation:(id)sender;
- (void)undoCorrection:(id)sender;
- (void)redoCorrection:(id)sender;
- (void)clearMatchWithMessage:(NSString*)message requiresRAW:(BOOL)requiresRAW;
- (void)showProfiles:(id)sender;
- (void)recalculateProfile:(NSDictionary*)selection;
- (void)rememberPendingContext:(NSDictionary*)context metadata:(NSDictionary*)metadata message:(NSString*)message;
@end
@implementation LensPanelController
- (NSDocument*)activeDocument{
 NSDocument*doc=NSDocumentController.sharedDocumentController.currentDocument;
 if(!doc)doc=NSApp.mainWindow.windowController.document;
 if(!doc)doc=NSApp.keyWindow.windowController.document;
 if(!doc){NSArray*documents=NSDocumentController.sharedDocumentController.documents;for(NSDocument*candidate in documents)for(NSWindowController*window in candidate.windowControllers)if(window.window.isMainWindow||window.window.isKeyWindow)doc=candidate;if(!doc&&documents.count==1)doc=documents.firstObject;}
 if(!doc&&[NSDocumentController.sharedDocumentController.documents containsObject:self.document])doc=self.document;
 return doc;
}
- (void)createPanel{
 self.panel=[[NSPanel alloc]initWithContentRect:NSMakeRect(0,0,700,750) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];self.panel.title=@"镜头矫正";self.panel.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];self.panel.releasedWhenClosed=NO;self.panel.delegate=self;
 NSView*root=self.panel.contentView;root.wantsLayer=YES;root.layer.backgroundColor=[NSColor colorWithWhite:.105 alpha:1].CGColor;
 NSTextField*title=label(@"镜头矫正",NSMakeRect(26,684,500,42),28,NSFontWeightSemibold);[root addSubview:title];
 self.badge=label(@"等待匹配",NSMakeRect(540,695,134,24),12,NSFontWeightMedium);self.badge.alignment=NSTextAlignmentRight;self.badge.textColor=NSColor.secondaryLabelColor;[root addSubview:self.badge];
 self.activity=[[NSProgressIndicator alloc]initWithFrame:NSMakeRect(514,699,16,16)];self.activity.style=NSProgressIndicatorStyleSpinning;self.activity.controlSize=NSControlSizeSmall;self.activity.indeterminate=YES;self.activity.displayedWhenStopped=NO;self.activity.accessibilityLabel=@"正在处理镜头矫正";[root addSubview:self.activity];
 NSView*profile=card(NSMakeRect(24,544,652,126));[root addSubview:profile];self.cameraLabel=label(@"选择 RAW 图层",NSMakeRect(18,85,456,22),12,NSFontWeightRegular);self.cameraLabel.textColor=NSColor.secondaryLabelColor;[profile addSubview:self.cameraLabel];self.lensLabel=label(@"自动识别相机与镜头",NSMakeRect(18,43,610,38),18,NSFontWeightMedium);self.lensLabel.selectable=YES;[profile addSubview:self.lensLabel];self.parameterLabel=label(@"焦距 · 光圈 · 对焦距离",NSMakeRect(18,15,600,22),12,NSFontWeightRegular);self.parameterLabel.textColor=NSColor.secondaryLabelColor;[profile addSubview:self.parameterLabel];
 self.profileButton=[NSButton buttonWithTitle:@"选择配置…" target:self action:@selector(showProfiles:)];self.profileButton.frame=NSMakeRect(484,81,148,30);self.profileButton.controlSize=NSControlSizeSmall;self.profileButton.enabled=NO;self.profileButton.toolTip=@"核对相机拍摄模式及镜头校准版本；手动选择随效果保存。";[profile addSubview:self.profileButton];
 NSArray*titles=@[@"畸变矫正",@"色差矫正",@"去暗角"];
 NSArray*descriptions=@[@"修正桶形与枕形弯曲",@"对齐红、绿、蓝通道的边缘",@"仅补偿镜头标定的边角亮度下降"];
 NSMutableArray*checks=[NSMutableArray new],*sliders=[NSMutableArray new],*values=[NSMutableArray new],*availability=[NSMutableArray new],*recommendButtons=[NSMutableArray new],*markers=[NSMutableArray new],*hints=[NSMutableArray new],*units=[NSMutableArray new];
 for(int i=0;i<3;i++){
  NSView*row=card(NSMakeRect(24,438-i*102,652,90));[root addSubview:row];NSButton*c=[NSButton checkboxWithTitle:titles[i] target:self action:@selector(changed:)];c.frame=NSMakeRect(18,51,180,25);c.font=[NSFont systemFontOfSize:15 weight:NSFontWeightMedium];c.enabled=NO;[row addSubview:c];[checks addObject:c];
  NSTextField*hint=label(descriptions[i],NSMakeRect(39,29,574,20),11,NSFontWeightRegular);hint.textColor=NSColor.secondaryLabelColor;[row addSubview:hint];[hints addObject:hint];
  NSButton*recommended=[NSButton buttonWithTitle:@"推荐 —" target:self action:@selector(useRecommendation:)];recommended.tag=i;recommended.frame=NSMakeRect(426,49,206,29);recommended.controlSize=NSControlSizeSmall;recommended.font=[NSFont systemFontOfSize:11 weight:NSFontWeightMedium];recommended.enabled=NO;[row addSubview:recommended];[recommendButtons addObject:recommended];
  NSView*marker=[[NSView alloc]initWithFrame:NSMakeRect(289,3,2,7)];marker.wantsLayer=YES;marker.layer.backgroundColor=NSColor.systemOrangeColor.CGColor;marker.hidden=YES;[row addSubview:marker];[markers addObject:marker];
  NSTextField*state=label(@"等待匹配",NSMakeRect(310,54,106,19),11,NSFontWeightRegular);state.alignment=NSTextAlignmentRight;state.textColor=NSColor.secondaryLabelColor;[row addSubview:state];[availability addObject:state];
  NSSlider*s=[NSSlider sliderWithValue:0 minValue:0 maxValue:200 target:self action:@selector(changed:)];s.frame=NSMakeRect(39,7,468,20);s.continuous=YES;s.enabled=NO;s.accessibilityLabel=[titles[i]stringByAppendingString:@"强度"];[row addSubview:s];[sliders addObject:s];
  NSTextField*v=[[NSTextField alloc]initWithFrame:NSMakeRect(529,7,82,24)];v.stringValue=@"0";v.alignment=NSTextAlignmentRight;v.font=[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];v.target=self;v.action=@selector(changed:);v.enabled=NO;v.accessibilityLabel=[titles[i]stringByAppendingString:i==0?@"短边位移百分比":i==1?@"通道位移像素":@"最大边角补偿 EV"];s.toolTip=v.toolTip=@"0% 为关闭补偿，100% 为完整镜头标定，200% 为两倍补偿。可在推荐位置上下调整。";NSNumberFormatter*f=[NSNumberFormatter new];f.minimum=@0;f.maximum=@200;f.maximumFractionDigits=3;v.formatter=f;[row addSubview:v];[values addObject:v];NSTextField*unit=label(i==0?@"%":i==1?@"px":@"EV",NSMakeRect(617,9,30,20),11,NSFontWeightRegular);[row addSubview:unit];[units addObject:unit];
 }
 self.checks=checks;self.sliders=sliders;self.percents=values;self.availability=availability;self.recommendButtons=recommendButtons;self.recommendMarkers=markers;self.hints=hints;self.unitLabels=units;
 NSView*risks=card(NSMakeRect(24,131,652,87));[root addSubview:risks];[risks addSubview:label(@"边角与高光",NSMakeRect(18,55,200,20),12,NSFontWeightMedium)];self.riskLabel=label(@"匹配后检测边角内容和补偿风险。三项校正可分别选择。",NSMakeRect(18,11,613,42),11,NSFontWeightRegular);self.riskLabel.textColor=NSColor.secondaryLabelColor;[risks addSubview:self.riskLabel];
 self.cropButton=[NSButton checkboxWithTitle:@"约束边缘 · 自动裁切" target:self action:@selector(changed:)];self.cropButton.frame=NSMakeRect(400,52,232,25);self.cropButton.font=[NSFont systemFontOfSize:12 weight:NSFontWeightRegular];self.cropButton.enabled=NO;self.cropButton.toolTip=@"依据当前标定与强度，居中裁去透明边缘并等比放大至原画布大小，视角会缩小。只改变可编辑效果，保留完整 RAW；关闭可恢复完整视角。";[risks addSubview:self.cropButton];
 self.detailsButton=[NSButton buttonWithTitle:@"详细设置…" target:self action:@selector(showDetails:)];self.detailsButton.frame=NSMakeRect(24,87,110,30);[root addSubview:self.detailsButton];self.rematchButton=[NSButton buttonWithTitle:@"重新匹配" target:self action:@selector(match:)];self.rematchButton.frame=NSMakeRect(140,87,110,30);self.rematchButton.toolTip=@"重新读取当前 RAW，载入最新建议。处理完成后可再次匹配。";[root addSubview:self.rematchButton];
 self.autoButton=[NSButton buttonWithTitle:@"采用自动建议" target:self action:@selector(automatic:)];self.autoButton.frame=NSMakeRect(367,87,140,30);self.autoButton.enabled=NO;[root addSubview:self.autoButton];
 self.applyButton=[NSButton buttonWithTitle:@"应用到 RAW" target:self action:@selector(apply:)];self.applyButton.frame=NSMakeRect(520,87,156,30);self.applyButton.bezelStyle=NSBezelStyleRounded;self.applyButton.bezelColor=NSColor.controlAccentColor;self.applyButton.enabled=NO;[root addSubview:self.applyButton];
 self.status=label(@"默认采用检测建议 · 主滑块显示实际校正量，可向上或向下调整。",NSMakeRect(238,19,438,49),11,NSFontWeightRegular);self.status.textColor=NSColor.secondaryLabelColor;[root addSubview:self.status];
 self.status.selectable=YES;
 self.undoButton=[NSButton buttonWithTitle:@"撤销校正" target:self action:@selector(undoCorrection:)];self.undoButton.frame=NSMakeRect(24,28,98,30);self.undoButton.enabled=NO;[root addSubview:self.undoButton];
 self.redoButton=[NSButton buttonWithTitle:@"重做" target:self action:@selector(redoCorrection:)];self.redoButton.frame=NSMakeRect(126,28,92,30);self.redoButton.enabled=NO;[root addSubview:self.redoButton];
}
- (NSUndoManager*)correctionUndoManager:(NSDocument*)doc{
 if(!doc)return nil;if(!self.undoManagers)self.undoManagers=[NSMapTable weakToStrongObjectsMapTable];NSUndoManager*m=[self.undoManagers objectForKey:doc];
 if(!m){m=[NSUndoManager new];m.groupsByEvent=NO;m.levelsOfUndo=5;[self.undoManagers setObject:m forKey:doc];}return m;
}
- (void)registerRestore:(NSData*)json expected:(NSData*)expected document:(NSDocument*)doc uuid:(NSString*)uuid{
 NSUndoManager*m=[self correctionUndoManager:doc];BOOL group=!m.isUndoing&&!m.isRedoing; if(group)[m beginUndoGrouping];__weak NSDocument*weakDoc=doc;
 [m registerUndoWithTarget:self handler:^(LensPanelController*target){[target restore:json expected:expected document:weakDoc identifier:uuid];}];[m setActionName:@"镜头矫正"];if(group)[m endUndoGrouping];
}
- (void)undoCorrection:(id)sender{if(!self.busy){[[self correctionUndoManager:self.document]undo];[self syncControls];}}
- (void)redoCorrection:(id)sender{if(!self.busy){[[self correctionUndoManager:self.document]redo];[self syncControls];}}
- (NSDictionary*)settings{
 NSArray*keys=@[@"distortion",@"tca",@"vignetting"];NSMutableDictionary*s=[NSMutableDictionary new];
 for(int i=0;i<3;i++){s[[keys[i]stringByAppendingString:@"Enabled"]]=@(self.checks[i].state==NSControlStateValueOn);s[[keys[i]stringByAppendingString:@"Strength"]]=@(round(LensCorrectionStrengthFromAmount(self.plan[@"report"],i,self.sliders[i].doubleValue)*1e9)/1e9);}s[@"constrainCropEnabled"]=@(self.cropButton.state==NSControlStateValueOn);return s;
}
- (void)loadSettings:(NSDictionary*)settings{
 self.cropButton.state=[settings[@"constrainCropEnabled"]boolValue]?NSControlStateValueOn:NSControlStateValueOff;
 NSArray*keys=@[@"distortion",@"tca",@"vignetting"],*available=[self availabilityValues],*recommended=[self recommendations];
 [self syncControls];
 for(int i=0;i<3;i++){BOOL ok=[available[i]boolValue];self.checks[i].state=ok&&[settings[[keys[i]stringByAppendingString:@"Enabled"]]boolValue]?NSControlStateValueOn:NSControlStateValueOff;NSNumber*n=settings[[keys[i]stringByAppendingString:@"Strength"]];self.sliders[i].maxValue=MAX(1e-8,LensDisplayCorrectionAmount(self.plan[@"report"],i,200));self.sliders[i].doubleValue=ok?LensDisplayCorrectionAmount(self.plan[@"report"],i,n?n.doubleValue:[recommended[i]doubleValue]):0;self.percents[i].doubleValue=self.sliders[i].doubleValue;}[self syncControls];
}
- (NSArray<NSNumber*>*)recommendations{return LensRecommendationPolicy(self.plan)[@"strengths"];}
- (NSArray<NSNumber*>*)availabilityValues{
 NSDictionary*r=self.plan[@"report"];return @[@(LensGeometryCalibrationNeeded(r,@"distortion")&&[r[@"distortionPeakShiftPercent"]doubleValue]>0),@(LensGeometryCalibrationNeeded(r,@"tca")&&[r[@"tcaPeakSeparationPixels"]doubleValue]>0),@([r[@"vignettingProfileAvailable"]boolValue]&&[r[@"vignettingCorrectionNeeded"]boolValue])];
}
- (void)updateRisk{
 if(!self.plan){self.riskLabel.stringValue=self.busy?@"正在检测当前照片，完成后显示建议与高光风险。":@"请选择 RAW 图层并匹配镜头，完成后显示建议数值。";return;}NSDictionary*a=self.plan[@"cornerAssessment"];
 NSDictionary*r=self.plan[@"report"];
 if([r[@"supplementalVignettingOnly"]boolValue]){
  NSString*nativeState=[self.plan[@"liveFingerprint"][@"rawParameters"][1][@"lc"]boolValue]?@"原生矫正已开启":@"原生矫正开关当前关闭，保留你的选择";
  NSString*extra=[r[@"vignettingProfileAvailable"]boolValue]&&[r[@"vignettingCorrectionNeeded"]boolValue]?@"有独立暗角标定，可手动试调；尚未测得原生处理后的残余暗角，推荐 0 EV。":@"没有可用的独立暗角补偿，推荐 0 EV。";
  self.riskLabel.stringValue=[NSString stringWithFormat:@"%@。%@",nativeState,extra];return;
 }
 if([r[@"vignettingCalibrationWarning"]length]){self.riskLabel.stringValue=r[@"vignettingCalibrationWarning"];return;}
 if(![r[@"vignettingProfileAvailable"]boolValue]){self.riskLabel.stringValue=LensPositiveCaptureNumber(r[@"aperture"])?@"尚缺有效的镜头暗角标定，推荐保持关闭（0 EV）。当前原图亮度保留。":@"光圈未知，未计算暗角补偿，保持关闭（0 EV）。畸变与色差按已读到的焦距匹配。";return;}
 if(![r[@"vignettingCorrectionNeeded"]boolValue]){self.riskLabel.stringValue=@"此镜头标定无需暗角补偿，推荐 0 EV。当前原图亮度保留。";return;}
 NSDictionary*policy=LensRecommendationPolicy(self.plan);
 if(![policy[@"vignettingMeasured"]boolValue]){self.riskLabel.stringValue=@"边角检测未完成，保守默认值 0 EV，保持关闭。重新匹配后会计算试用建议；目前无法估计高光风险。";return;}
 int amount=MAX(0,MIN(200,(int)round(LensCorrectionStrengthFromAmount(r,2,self.sliders[2].doubleValue))));NSArray*curve=a[@"clippingFractionByStrengthPercent"];
 double clip=curve.count>amount?[curve[amount]doubleValue]:[a[@"predictedNewHighlightClippingFraction"]doubleValue];
 if([policy[@"vignettingState"]isEqual:@"highlight-limited"]){self.riskLabel.stringValue=[NSString stringWithFormat:@"高光预算内建议 0 EV，默认关闭。%@预计新增 %.2f%% 高光溢出；可手动调节并预览。",self.checks[2].state==NSControlStateValueOn?@"当前强度":@"启用当前强度后",clip*100];return;}
 self.riskLabel.stringValue=[NSString stringWithFormat:@"%@。%@ %@；%@预计新增 %.2f%% 高光溢出。",[policy[@"vignettingState"]isEqual:@"trial"]?@"内容难以确认暗角，建议关闭自动去暗角":@"观察到一致的边角衰减",[policy[@"vignettingState"]isEqual:@"trial"]?@"保守试用值":@"推荐强度",amountText(LensDisplayCorrectionAmount(r,2,[[self recommendations][2]doubleValue]),2),self.checks[2].state==NSControlStateValueOn?@"当前强度":@"启用当前强度后",clip*100];
}
- (void)syncControls{
 if(self.busy){[self.activity startAnimation:nil];self.badge.stringValue=@"正在处理";self.badge.textColor=NSColor.secondaryLabelColor;}
 else{[self.activity stopAnimation:nil];if(self.plan){self.badge.stringValue=[self.plan[@"report"][@"supplementalVignettingOnly"]boolValue]?@"原生支持矫正":[self.plan[@"report"][@"manualProfileSelection"]count]?@"手选配置":@"已匹配配置";self.badge.textColor=NSColor.systemGreenColor;}}
 self.rematchButton.enabled=!self.busy;
 self.profileButton.enabled=!self.busy&&(self.plan||self.matchContext)&&self.metadata!=nil;
 NSArray*available=[self availabilityValues],*recommended=[self recommendations];NSDictionary*r=self.plan[@"report"];
 BOOL native=[r[@"supplementalVignettingOnly"]boolValue];self.checks[2].title=native?@"额外去暗角":@"去暗角";
 for(int i=0;i<3;i++){
  BOOL ok=[available[i]boolValue];double maximum=LensDisplayCorrectionAmount(r,i,200),suggested=LensDisplayCorrectionAmount(r,i,[recommended[i]doubleValue]);
  self.sliders[i].maxValue=MAX(niceMaximum(maximum),MIN(maximum,self.sliders[i].doubleValue));if(!self.plan){self.checks[i].state=NSControlStateValueOff;self.sliders[i].doubleValue=0;self.availability[i].stringValue=self.busy?@"正在匹配":@"等待匹配";self.availability[i].textColor=NSColor.secondaryLabelColor;}
  self.sliders[i].doubleValue=ok?MIN(maximum,MAX(0,self.sliders[i].doubleValue)):0;
  self.checks[i].enabled=ok&&!self.busy;self.sliders[i].enabled=ok&&!self.busy;self.percents[i].enabled=ok&&!self.busy;
  ((NSNumberFormatter*)self.percents[i].formatter).maximum=@(maximum);
  self.percents[i].doubleValue=self.sliders[i].doubleValue;self.recommendButtons[i].enabled=ok&&!self.busy;
  NSDictionary*policy=LensRecommendationPolicy(self.plan);NSString*kind=i==2&&[policy[@"vignettingState"]isEqual:@"trial"]?@"试用":@"推荐";
  self.recommendButtons[i].title=native&&i<2?@"自动跳过":ok?[NSString stringWithFormat:@"%@ %@",kind,amountText(suggested,i)]:self.plan?[NSString stringWithFormat:@"建议 %@",amountText(0,i)]:@"等待检测";
  self.recommendButtons[i].toolTip=@"载入这一项的最新建议量并启用。建议为零时保持关闭；不会添加没有标定依据的校正。";
  NSArray*names=@[@"画面短边的最大几何位移",@"红蓝通道相对绿色的最大位移",@"标定最暗位置的最大亮度补偿"];
  double delta=self.sliders[i].doubleValue-suggested;NSString*position=fabs(delta)<1e-6?@"位于建议值":[NSString stringWithFormat:@"%@建议 %@",delta>0?@"高于":@"低于",amountText(fabs(delta),i)];
  self.hints[i].stringValue=native&&i<2?@"原生支持，跳过补充矫正；保留 RAW 的原生开关状态":ok?[NSString stringWithFormat:@"%@ · %@%@",names[i],position,self.checks[i].state==NSControlStateValueOn?@"":@" · 未启用"]:i==2&&[r[@"vignettingCalibrationWarning"]length]?@"标定产生无效增益，已单独关闭去暗角":self.plan?@"缺少非零有效补偿，建议保留原样":@"匹配后显示当前照片的实际建议量";
  self.sliders[i].accessibilityValueDescription=ok?[NSString stringWithFormat:@"当前 %@，%@ %@，%@，%@",amountText(self.sliders[i].doubleValue,i),kind,amountText(suggested,i),position,self.checks[i].state==NSControlStateValueOn?@"已启用":@"未启用"]:@"等待有效补偿，当前零";
  self.sliders[i].toolTip=self.percents[i].toolTip=[NSString stringWithFormat:@"%@。滑块范围 0–%@；数字框可调至 %@（两倍标定）。详细配置保留标定倍率。",names[i],amountText(self.sliders[i].maxValue,i),amountText(maximum,i)];
  self.recommendMarkers[i].hidden=!ok;self.recommendMarkers[i].frame=NSMakeRect(49+448*suggested/self.sliders[i].maxValue,3,2,7);
 }
 BOOL active=NO;for(int i=0;i<3;i++)if(self.checks[i].state==NSControlStateValueOn&&self.sliders[i].doubleValue>0&&[available[i]boolValue])active=YES;
 self.cropButton.enabled=!self.busy&&self.plan&&((self.checks[0].state==NSControlStateValueOn&&self.sliders[0].doubleValue>0)||(self.checks[1].state==NSControlStateValueOn&&self.sliders[1].doubleValue>0));
 self.applyButton.enabled=self.plan!=nil&&!self.busy&&(active||self.hasOwnEffect);self.autoButton.enabled=self.plan!=nil&&!self.busy;self.detailsButton.enabled=(self.plan||self.matchContext)&&self.metadata!=nil&&!self.busy;NSUndoManager*m=[self correctionUndoManager:self.document];self.undoButton.enabled=m.canUndo&&!self.busy;self.redoButton.enabled=m.canRedo&&!self.busy;[self updateRisk];
}
- (void)useRecommendation:(NSButton*)sender{
 if(self.busy)return;NSInteger i=sender.tag;double strength=[[self recommendations][i]doubleValue];self.sliders[i].doubleValue=LensDisplayCorrectionAmount(self.plan[@"report"],i,strength);self.checks[i].state=strength>0?NSControlStateValueOn:NSControlStateValueOff;[self changed:sender];
}
- (void)changed:(id)sender{NSUInteger i=[self.percents indexOfObjectIdenticalTo:sender];if(i!=NSNotFound){self.sliders[i].maxValue=MAX(self.sliders[i].maxValue,MIN(self.percents[i].doubleValue,LensDisplayCorrectionAmount(self.plan[@"report"],i,200)));self.sliders[i].doubleValue=self.percents[i].doubleValue;}self.userTouched=YES;[self syncControls];self.status.stringValue=@"新的校正量尚未应用。点击“应用到 RAW”保存这一组参数。";}
- (void)show:(id)sender{NSDocument*owner=[self activeDocument];if(owner)self.document=owner;LensWriteHostState(owner,@"before-panel");NSWindow*window=NSApp.keyWindow?:NSApp.mainWindow;if(window&&window!=self.panel)self.hostWindow=window;if(!self.panel)[self createPanel];[self.panel center];if(self.hostWindow&&self.panel.parentWindow!=self.hostWindow){[self.panel.parentWindow removeChildWindow:self.panel];[self.hostWindow addChildWindow:self.panel ordered:NSWindowAbove];}[NSApp activateIgnoringOtherApps:YES];[self.panel makeKeyAndOrderFront:nil];if(!self.busy)[self match:nil];}
- (void)windowWillClose:(NSNotification*)notification{
 if(notification.object!=self.panel)return;NSWindow*window=self.hostWindow;[window removeChildWindow:self.panel];
 dispatch_async(dispatch_get_main_queue(),^{if(window.isVisible){[NSApp activateIgnoringOtherApps:YES];[window makeMainWindow];[window makeKeyAndOrderFront:nil];}
 LensWriteHostState(self.document,@"after-panel-close");
 NSString*diagnostic=[NSString stringWithFormat:@"host=%@ class=%@ visible=%d main=%@ key=%@ active=%d currentDocument=%@ ownDocument=%@",window.title,NSStringFromClass(object_getClass(window)),window.isVisible,NSApp.mainWindow.title,NSApp.keyWindow.title,NSApp.isActive,NSStringFromClass(object_getClass(NSDocumentController.sharedDocumentController.currentDocument)),NSStringFromClass(object_getClass(self.document))];[diagnostic writeToFile:[NSTemporaryDirectory()stringByAppendingPathComponent:@"LensPanelFocus.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 });
}
- (void)presentPlan:(NSDictionary*)plan document:(NSDocument*)doc identifier:(NSString*)uuid saved:(NSDictionary*)saved{
 NSMutableDictionary*livePlan=[plan mutableCopy];if(!livePlan[@"liveFingerprint"]){NSDictionary*f=LensLiveRAWFingerprint(doc,getter(doc,@"scriptingCurrentLayer"));if(f)livePlan[@"liveFingerprint"]=f;}plan=livePlan;self.plan=plan;self.document=doc;self.layerIdentifier=uuid;NSDictionary*r=plan[@"report"];self.cameraLabel.stringValue=[NSString stringWithFormat:@"相机  %@",r[@"camera"]?:@"—"];self.lensLabel.stringValue=r[@"lens"]?:@"未找到匹配配置";self.parameterLabel.stringValue=[NSString stringWithFormat:@"%@ mm   ·   f/%@   ·   %@",displayNumber(r[@"focal_mm"]),displayNumber(LensPositiveCaptureNumber(r[@"aperture"])),LensFocusDistanceTextForReport(r)];self.parameterLabel.toolTip=[NSString stringWithFormat:@"标定使用完整精度：焦距 %@ mm，光圈 f/%@，距离 %@ m。",r[@"focal_mm"],LensPositiveCaptureNumber(r[@"aperture"])?:@"未记录",r[@"focus_distance_m"]];
 self.badge.stringValue=@"已匹配配置";self.badge.textColor=NSColor.systemGreenColor;
 NSArray*available=[self availabilityValues];for(int i=0;i<3;i++){BOOL ok=[available[i]boolValue],identity=[r[@[@"distortionProfileAvailable",@"tcaProfileAvailable",@"vignettingProfileAvailable"][i]]boolValue]&&!ok;self.checks[i].enabled=ok;self.availability[i].stringValue=ok?@"标定可用":i==2&&[r[@"vignettingCalibrationWarning"]length]?@"标定不可用":identity?@"建议保留原样":i==2&&!LensPositiveCaptureNumber(r[@"aperture"])?@"光圈未知":[r[@"supplementalVignettingOnly"]boolValue]&&i<2?@"原生支持":@"缺少标定";self.availability[i].textColor=ok?NSColor.systemGreenColor:NSColor.secondaryLabelColor;}
 NSDictionary*assessment=plan[@"cornerAssessment"];
 self.riskLabel.stringValue=assessment?[NSString stringWithFormat:@"%@。全强度去暗角预计新增 %.2f%% 高光溢出。自动建议%@；手动选择保留。",[assessment[@"sceneContentAmbiguous"]boolValue]?@"边角内容复杂，亮度不足以认定暗角":@"检测到较一致的边角亮度下降",[assessment[@"predictedNewHighlightClippingFraction"]doubleValue]*100,[assessment[@"automaticFullStrengthSuitable"]boolValue]?@"可预览":@"关闭去暗角"]:@"没有可用的去暗角检测结果。校正依照镜头标定，不从阴影推测镜头配置。";
 if(saved[@"correctionSettings"])[self loadSettings:saved[@"correctionSettings"]];else [self automatic:nil];
 LensWriteHostState(doc,@"after-present-plan");
 self.status.stringValue=saved?@"已读取文档内保存的配置，可继续调整。三项参数分别保存。":@"已载入本次建议量 · 三项独立开关，滑块可向上或向下调整。";[self syncControls];
}
- (void)automatic:(id)sender{
 NSDictionary*r=self.plan[@"report"];NSArray*recommended=[self recommendations];
 BOOL automatic=[LensRecommendationPolicy(self.plan)[@"vignettingAutomatic"]boolValue];
 [self loadSettings:@{@"distortionEnabled":@([r[@"distortionProfileAvailable"]boolValue]),@"tcaEnabled":@([r[@"tcaProfileAvailable"]boolValue]),@"vignettingEnabled":@(automatic),@"distortionStrength":recommended[0],@"tcaStrength":recommended[1],@"vignettingStrength":recommended[2],@"constrainCropEnabled":@YES}];
 self.userTouched=NO;if(sender)self.status.stringValue=@"已载入最新建议量，尚未应用；滑块与建议标记已同步。";
}
- (void)clearMatchWithMessage:(NSString*)message requiresRAW:(BOOL)requiresRAW{
 self.plan=nil;self.metadata=nil;self.matchContext=nil;self.userTouched=NO;self.cameraLabel.stringValue=requiresRAW?@"选择照片":@"当前 RAW 图层";
 self.lensLabel.stringValue=requiresRAW?@"先选择 RAW 图层":@"没有可用的镜头匹配";
 self.parameterLabel.stringValue=requiresRAW?@"打开 RAW 照片后，在图层列表中选中 RAW 图层。":@"原片与已有编辑保留，未应用新的校正。";
 self.badge.stringValue=requiresRAW?@"等待选择":@"未匹配";self.badge.textColor=NSColor.secondaryLabelColor;self.status.stringValue=message;[self syncControls];
}
- (void)match:(id)sender{
 if(self.busy)return;
 NSDocument*doc=[self activeDocument];id script=getter(doc,@"scriptingCurrentLayer");NSString*uuid=getter(script,@"scriptUniqueID");id layer=rawLayer(script);
 if(![NSStringFromClass(object_getClass(layer))isEqual:@"PXMEngine.RawLayer"]){[self clearMatchWithMessage:doc?@"请在图层列表中选中 RAW 图层，再点击“重新匹配”。":@"请先打开 RAW 照片，再在图层列表中选中 RAW 图层。" requiresRAW:YES];NSString*diagnostic=[NSString stringWithFormat:@"document=%@ documents=%lu script=%@ layer=%@ uuid=%@",NSStringFromClass(object_getClass(doc)),(unsigned long)NSDocumentController.sharedDocumentController.documents.count,NSStringFromClass(object_getClass(script)),NSStringFromClass(object_getClass(layer)),uuid];[diagnostic writeToFile:[NSTemporaryDirectory()stringByAppendingPathComponent:@"LensPanelSelection.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];return;}
 NSDictionary*saved=LensSavedCorrectionProfile(LensCopyLayerEffects(layer));
 NSDictionary*retainedSettings=sender?nil:saved[@"correctionSettings"];
 self.hasOwnEffect=saved!=nil;
 if(saved&&!sender&&saved[@"sourceBinding"]&&!LensCorrectionSourceMatches(saved[@"sourceBinding"],LensLiveRAWFingerprint(doc,script))){[self clearMatchWithMessage:@"原片、显影参数或图层状态已变化。请点击“重新匹配”检测当前照片；原有编辑保留。" requiresRAW:NO];return;}
 NSDictionary*retainedMetadata=!sender?saved[@"metadata"]:nil;BOOL retainedParameters=!sender&&[saved[@"parameterOverrides"]boolValue];
 self.plan=nil;self.matchContext=nil;self.busy=YES;self.cameraLabel.stringValue=@"当前 RAW 图层";self.lensLabel.stringValue=@"正在识别相机与镜头…";self.parameterLabel.stringValue=@"正在读取拍摄参数";[self syncControls];self.badge.stringValue=@"正在匹配";self.badge.textColor=NSColor.secondaryLabelColor;self.status.stringValue=@"正在读取当前 RAW 图层与镜头标定…";NSUInteger generation=++self.generation;NSURL*root=[NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"LensBridge"],*library=[NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"LensBridge/liblensfun.0.3.4.dylib"];
 NSURL*temp=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];NSError*snapshotError=nil;NSDictionary*snapshot=LensReadLiveRAWLayer(doc,script,temp,&snapshotError);
 if(!snapshot){[NSFileManager.defaultManager removeItemAtURL:temp error:nil];self.busy=NO;[self clearMatchWithMessage:snapshotError.localizedDescription?:@"当前 RAW 数据不可用。" requiresRAW:NO];return;}
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
  NSError*error=nil;NSDictionary*metadata=nil,*baseMetadata=nil,*plan=nil;
  if(snapshot)metadata=LensReadRawMetadata(snapshot[@"rawURL"],[root URLByAppendingPathComponent:@"exiftool/exiftool"],&error);
  baseMetadata=metadata;
  if(metadata&&retainedMetadata){NSMutableDictionary*m=[(retainedParameters?LensMetadataRestoringCaptureParameters(metadata,retainedMetadata):metadata)mutableCopy];if(retainedMetadata[@"LensDockProfileSelection"])m[@"LensDockProfileSelection"]=retainedMetadata[@"LensDockProfileSelection"];metadata=m;}
  NSMutableDictionary*context=metadata?[@{@"metadata":metadata,@"baseMetadata":baseMetadata,@"report":@{@"width":snapshot[@"width"],@"height":snapshot[@"height"],@"workingTransfer":snapshot[@"workingTransfer"],@"assessmentPreviewSource":snapshot[@"previewSource"],@"assessmentPreviewTransfer":snapshot[@"previewTransfer"]},@"liveFingerprint":snapshot[@"liveFingerprint"],@"sourceBinding":LensCorrectionSourceBinding(snapshot[@"liveFingerprint"]),@"assessmentPreviewData":[NSData dataWithContentsOfURL:snapshot[@"previewURL"]]?:NSData.data}mutableCopy]:nil;if(retainedParameters)context[@"parameterOverrides"]=@YES;
  if(metadata)plan=LensNativeProfilePlan(metadata,[root URLByAppendingPathComponent:@"db"],library,[snapshot[@"width"]unsignedIntegerValue],[snapshot[@"height"]unsignedIntegerValue],&error);
  if(plan)plan=pickerReboundPlan(plan,context,metadata);
  [NSFileManager.defaultManager removeItemAtURL:temp error:nil];dispatch_async(dispatch_get_main_queue(),^{if(generation!=self.generation)return;self.busy=NO;if(doc!=[self activeDocument]||![uuid isEqual:getter(getter(doc,@"scriptingCurrentLayer"),@"scriptUniqueID")]||![snapshot[@"liveFingerprint"]isEqual:LensLiveRAWFingerprint(doc,getter(doc,@"scriptingCurrentLayer"))]){[self clearMatchWithMessage:@"匹配期间 RAW 状态发生变化，请重新匹配。" requiresRAW:NO];return;}if(!plan){[self clearMatchWithMessage:error.localizedDescription?:@"没有唯一匹配配置，原片保留。" requiresRAW:NO];self.metadata=metadata;self.matchContext=context;self.document=doc;self.layerIdentifier=uuid;[self syncControls];return;}self.metadata=metadata;self.matchContext=context;[self presentPlan:plan document:doc identifier:uuid saved:retainedSettings?@{@"correctionSettings":retainedSettings}:nil];if(retainedSettings)self.status.stringValue=@"已重新检测当前 RAW，三项手动选择保留。新配置尚未应用。";});
 }});
}
- (void)showProfiles:(id)sender{
 if(self.busy||self.profilePicker||!self.profileButton.enabled)return;
 NSDictionary*context=self.plan?:self.matchContext;NSDocument*doc=[self activeDocument];NSString*uuid=getter(getter(doc,@"scriptingCurrentLayer"),@"scriptUniqueID");
 if(doc!=self.document||![uuid isEqual:self.layerIdentifier]||![context[@"liveFingerprint"]isEqual:LensLiveRAWFingerprint(doc,getter(doc,@"scriptingCurrentLayer"))]){self.status.stringValue=@"RAW 状态已变化，请重新匹配当前照片后选择配置。";return;}
 NSURL*root=[NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"LensBridge"],*library=[NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"LensBridge/liblensfun.0.3.4.dylib"];__weak LensPanelController*weakSelf=self;
 NSMutableDictionary*pickerMetadata=[context[@"metadata"]mutableCopy];if(!pickerMetadata[@"LensDockProfileSelection"]&&context[@"report"][@"matchedCameraProfileID"]&&context[@"report"][@"matchedLensProfileID"])pickerMetadata[@"LensDockProfileSelection"]=@{@"cameraID":context[@"report"][@"matchedCameraProfileID"],@"lensID":context[@"report"][@"matchedLensProfileID"]};
 self.profilePicker=[[LensProfilePicker alloc]initWithMetadata:pickerMetadata databaseURL:[root URLByAppendingPathComponent:@"db"] libraryURL:library completion:^(NSDictionary*selection){LensPanelController*target=weakSelf;target.profilePicker=nil;if(selection)[target recalculateProfile:selection];}];[self.profilePicker beginSheetForWindow:self.panel];
}
- (void)rememberPendingContext:(NSDictionary*)context metadata:(NSDictionary*)metadata message:(NSString*)message{
 NSMutableDictionary*pending=[context mutableCopy];pending[@"metadata"]=metadata;self.metadata=metadata;self.matchContext=pending;
 self.badge.stringValue=LensPositiveCaptureNumber(metadata[@"FocalLength"])?@"未匹配":@"待补参数";
 self.parameterLabel.stringValue=@"已保留待确认的配置与参数；原片和已有效果保留。";
 self.status.stringValue=[NSString stringWithFormat:@"%@ 点击“详细设置…”核对拍摄参数，或“选择配置…”核对标定。",message];[self syncControls];
}
- (void)recalculateProfile:(NSDictionary*)selection{
 NSDictionary*context=self.plan?:self.matchContext;if(!context||self.busy)return;NSDocument*doc=self.document;NSString*uuid=self.layerIdentifier;
 if(doc!=[self activeDocument]||![uuid isEqual:getter(getter(doc,@"scriptingCurrentLayer"),@"scriptUniqueID")]||![context[@"liveFingerprint"]isEqual:LensLiveRAWFingerprint(doc,getter(doc,@"scriptingCurrentLayer"))]){self.status.stringValue=@"选择期间 RAW 状态已变化，请重新匹配。";return;}
 NSMutableDictionary*metadata=[context[@"metadata"]mutableCopy];if(selection.count)metadata[@"LensDockProfileSelection"]=selection;else [metadata removeObjectForKey:@"LensDockProfileSelection"];
 NSURL*root=[NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"LensBridge"],*library=[NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"LensBridge/liblensfun.0.3.4.dylib"];self.busy=YES;NSUInteger generation=++self.generation;[self syncControls];self.status.stringValue=@"正在核对所选配置并重新计算建议…";
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
  NSError*error=nil;NSDictionary*generated=LensNativeProfilePlan(metadata,[root URLByAppendingPathComponent:@"db"],library,[context[@"report"][@"width"]unsignedIntegerValue],[context[@"report"][@"height"]unsignedIntegerValue],&error);NSDictionary*p=pickerReboundPlan(generated,context,metadata);
  dispatch_async(dispatch_get_main_queue(),^{if(generation!=self.generation)return;self.busy=NO;[self syncControls];if(doc!=[self activeDocument]||![uuid isEqual:getter(getter(doc,@"scriptingCurrentLayer"),@"scriptUniqueID")]||![context[@"liveFingerprint"]isEqual:LensLiveRAWFingerprint(doc,getter(doc,@"scriptingCurrentLayer"))]){self.status.stringValue=@"配置计算期间 RAW 状态已变化，未更新校正。";return;}if(!p){NSString*message=error.localizedDescription?:@"所选配置不可用，原有校正保留。";if(!self.plan)[self rememberPendingContext:context metadata:metadata message:message];else self.status.stringValue=message;return;}self.metadata=metadata;self.matchContext=p;[self presentPlan:p document:doc identifier:uuid saved:nil];self.status.stringValue=selection.count?@"已载入所选标定与最新建议，尚未应用。点击“应用到 RAW”后配置随效果保存。":@"已恢复自动匹配与最新建议，尚未应用。";});
 }});
}
- (void)restore:(NSData*)json expected:(NSData*)expected document:(NSDocument*)doc identifier:(NSString*)uuid{
 if(!doc||!json)return;id layer=rawLayer(findLayer(doc,uuid,0));id before=LensCopyLayerEffects(layer);NSData*redo=LensEffectsJSON(before,nil);if(!sameJSON(redo,expected)){[[self correctionUndoManager:doc]removeAllActions];self.status.stringValue=@"图层效果已有其他编辑，校正历史已清空；当前编辑保留。";return;}id effects=LensEffectsFromJSON(json);NSDictionary*targetBinding=LensSavedCorrectionProfile(effects)[@"sourceBinding"]?:self.plan[@"sourceBinding"];if(targetBinding&&!LensCorrectionSourceMatches(targetBinding,LensLiveRAWFingerprint(doc,findLayer(doc,uuid,0)))){self.status.stringValue=@"原片或 RAW 状态已变化，未执行校正历史；请重新匹配。";return;}NSError*restoreError=nil;if(!effects||!LensReplaceLayerCorrection(layer,effects,&restoreError)){self.status.stringValue=restoreError.localizedDescription?:@"无法恢复校正状态。";return;}
 LensRegisterLiveHistory(doc,findLayer(doc,uuid,0));
 [self registerRestore:redo expected:LensEffectsJSON(LensCopyLayerEffects(layer),nil) document:doc uuid:uuid];[doc updateChangeCount:NSChangeDone];
 NSDictionary*saved=LensSavedCorrectionProfile(effects);self.hasOwnEffect=saved!=nil;if(saved){NSMutableDictionary*p=[@{@"report":saved[@"matchedProfile"],@"normalizedGeometryMapsLZFSE":saved[@"normalizedGeometryMapsLZFSE"]?:@{}}mutableCopy];NSData*restoredGain=LensDecodedGainData(saved,nil);if(restoredGain)p[@"linearGainFloat32BottomUp"]=restoredGain;if(saved[@"geometryResidualMapsLZFSE"])p[@"geometryResidualMapsLZFSE"]=saved[@"geometryResidualMapsLZFSE"];for(NSString*key in @[@"cornerAssessment",@"metadata",@"baseMetadata",@"parameterOverrides",@"assessmentPreviewData",@"sourceBinding"])if(saved[key])p[key]=saved[key];self.metadata=saved[@"metadata"];[self presentPlan:p document:doc identifier:uuid saved:saved];}else{[self syncControls];self.status.stringValue=@"已撤销镜头矫正，原始 RAW 与其他效果保留。";}
}
- (void)commitPlan:(NSDictionary*)plan settings:(NSDictionary*)settings document:(NSDocument*)doc uuid:(NSString*)uuid before:(NSData*)before{
 id script=findLayer(doc,uuid,0),layer=rawLayer(script);NSDictionary*live=LensLiveRAWFingerprint(doc,script);if(!LensPlanAllowsLiveNativeCorrection(plan,live)||(plan[@"liveFingerprint"]&&![plan[@"liveFingerprint"]isEqual:live])||(plan[@"sourceBinding"]&&!LensCorrectionSourceMatches(plan[@"sourceBinding"],live))){self.status.stringValue=@"RAW 状态已变化，请重新匹配后应用。";return;}NSData*current=LensEffectsJSON(LensCopyLayerEffects(layer),nil);if(!sameJSON(before,current)){self.status.stringValue=@"生成映射期间图层效果发生变化，未覆盖现有编辑。";return;}
 NSError*error=nil;NSData*envelope=[NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"native-effects-template" withExtension:@"json"]];id effects=LensEffectsForCorrectionPlan(plan,envelope,settings,current,&error);if(!effects||!LensReplaceLayerCorrection(layer,effects,&error)){self.status.stringValue=error.localizedDescription?:@"配置不可用，未应用。";return;}
 LensRegisterLiveHistory(doc,script);
 [self registerRestore:before expected:LensEffectsJSON(effects,nil) document:doc uuid:uuid];[doc updateChangeCount:NSChangeDone];LensWriteHostState(doc,@"after-effect-commit");self.plan=plan;self.hasOwnEffect=YES;[self syncControls];double cropScale=[plan[@"constrainedCrop"][@"scale"]doubleValue];self.status.stringValue=[settings[@"constrainCropEnabled"]boolValue]&&cropScale>0&&cropScale<1?[NSString stringWithFormat:@"已应用，约束边缘等比放大 %.2f%%；完整 RAW 保留，可关闭裁切或撤销。",(1/cropScale-1)*100]:@"已应用，可用面板“撤销校正”恢复。三项参数与原始 RAW 均保留。";
}
- (void)apply:(id)sender{
 if(self.busy||!self.applyButton.enabled)return;[self.panel makeFirstResponder:nil];
 NSDocument*doc=[self activeDocument];NSString*uuid=getter(getter(doc,@"scriptingCurrentLayer"),@"scriptUniqueID");if(!self.plan||doc!=self.document||![uuid isEqual:self.layerIdentifier]){self.status.stringValue=@"请先匹配当前 RAW 图层。";return;}
 NSDictionary*live=LensLiveRAWFingerprint(doc,getter(doc,@"scriptingCurrentLayer"));if(!LensPlanAllowsLiveNativeCorrection(self.plan,live)||![live[@"width"]isEqual:self.plan[@"report"][@"width"]]||![live[@"height"]isEqual:self.plan[@"report"][@"height"]]||![live[@"workingTransfer"]isEqual:self.plan[@"report"][@"workingTransfer"]]||(self.plan[@"liveFingerprint"]&&![self.plan[@"liveFingerprint"]isEqual:live])||(self.plan[@"sourceBinding"]&&!LensCorrectionSourceMatches(self.plan[@"sourceBinding"],live))){self.status.stringValue=@"RAW 参数、尺寸或颜色空间已变化，请重新匹配。";return;}NSDictionary*settings=[self settings];NSData*before=LensEffectsJSON(LensCopyLayerEffects(rawLayer(getter(doc,@"scriptingCurrentLayer"))),nil);if(!before){self.status.stringValue=@"无法保留当前图层效果，未应用。";return;}
 BOOL needsMaps=([settings[@"distortionEnabled"]boolValue]||[settings[@"tcaEnabled"]boolValue])&&![self.plan[@"normalizedGeometryMapsLZFSE"]count];
 BOOL needsCrop=[settings[@"constrainCropEnabled"]boolValue]&&([settings[@"distortionEnabled"]boolValue]||[settings[@"tcaEnabled"]boolValue]);
 if(!needsMaps&&!needsCrop){[self commitPlan:self.plan settings:settings document:doc uuid:uuid before:before];return;}
 NSDictionary*metadata=self.plan[@"metadata"]?:self.metadata;
 if(needsMaps&&!metadata){self.status.stringValue=@"缺少原始匹配参数，请重新匹配。";return;}
 NSDictionary*previous=self.plan;NSURL*root=[NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"LensBridge"],*library=[NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"LensBridge/liblensfun.0.3.4.dylib"];
 self.busy=YES;[self syncControls];self.status.stringValue=needsMaps?@"正在生成畸变与通道映射，原始 RAW 保持不变…":@"正在按当前校正量核对安全裁切范围…";
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
  NSError*error=nil;NSMutableDictionary*p=nil;
  if(needsMaps){
   NSDictionary*generated=LensNativeProfilePlanIncludingGeometry(metadata,[root URLByAppendingPathComponent:@"db"],library,[previous[@"report"][@"width"]unsignedIntegerValue],[previous[@"report"][@"height"]unsignedIntegerValue],&error);
   p=generated?[generated mutableCopy]:nil;
   if(p){NSMutableDictionary*r=[generated[@"report"]mutableCopy];r[@"workingTransfer"]=previous[@"report"][@"workingTransfer"];for(NSString*key in @[@"assessmentPreviewSource",@"assessmentPreviewTransfer"])if(previous[@"report"][key])r[key]=previous[@"report"][key];if([previous[@"parameterOverrides"]boolValue]&&LensPositiveCaptureNumber(metadata[@"FocusDistance"]))r[@"distance_source"]=@"manual";p[@"report"]=r;p[@"metadata"]=metadata;for(NSString*key in @[@"baseMetadata",@"parameterOverrides",@"cornerAssessment",@"assessmentPreviewData",@"liveFingerprint",@"sourceBinding"])if(previous[key])p[key]=previous[key];}
  }else p=[previous mutableCopy];
  if(p&&needsCrop){NSDictionary*crop=LensConstrainedCrop(p,settings,&error);if(crop){p[@"constrainedCrop"]=crop;p[@"constrainedCropSettings"]=settings;}else p=nil;}
  dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;[self syncControls];if(!p){self.status.stringValue=error.localizedDescription?:@"映射或裁切范围不可用，未应用。";return;}if(doc!=[self activeDocument]){self.status.stringValue=@"当前文档已切换，未应用。";return;}[self commitPlan:p settings:settings document:doc uuid:uuid before:before];});
 }});
}
- (void)showDetails:(id)sender{
 if(!(self.plan?:self.matchContext)||!self.metadata||self.busy)return;
 if(!self.details){
  self.details=[NSPopover new];self.details.behavior=NSPopoverBehaviorTransient;
  NSViewController*c=[NSViewController new];c.view=[[NSView alloc]initWithFrame:NSMakeRect(0,0,440,500)];
  [c.view addSubview:label(@"标定参数",NSMakeRect(20,455,390,26),18,NSFontWeightSemibold)];
  NSArray*names=@[@"焦距（mm）",@"光圈（f 值）",@"对焦距离（m）"];
  NSMutableArray*fields=[NSMutableArray new];
  for(int i=0;i<3;i++){
   [c.view addSubview:label(names[i],NSMakeRect(20,414-i*39,260,24),12,NSFontWeightRegular)];
   NSTextField*f=[[NSTextField alloc]initWithFrame:NSMakeRect(294,414-i*39,122,25)];
   NSNumberFormatter*format=[NSNumberFormatter new];format.numberStyle=NSNumberFormatterDecimalStyle;format.usesGroupingSeparator=NO;format.maximumFractionDigits=4;f.formatter=format;f.accessibilityLabel=names[i];f.placeholderString=i==0?@"填写实际焦距":@"未知可留空";f.font=[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
   [c.view addSubview:f];[fields addObject:f];
  }
  self.focalField=fields[0];self.apertureField=fields[1];self.distanceField=fields[2];
  [c.view addSubview:label(@"标定倍率（完整标定为 100%）",NSMakeRect(20,299,398,23),12,NSFontWeightMedium)];
  NSMutableArray*relative=[NSMutableArray new];NSArray*relativeNames=@[@"畸变",@"色差",@"去暗角"];
  for(int i=0;i<3;i++){[c.view addSubview:label(relativeNames[i],NSMakeRect(20,266-i*35,260,24),12,NSFontWeightRegular)];NSTextField*f=[[NSTextField alloc]initWithFrame:NSMakeRect(294,266-i*35,122,25)];NSNumberFormatter*format=[NSNumberFormatter new];format.minimum=@0;format.maximum=@200;format.maximumFractionDigits=2;f.formatter=format;f.accessibilityLabel=[relativeNames[i]stringByAppendingString:@"标定倍率百分比"];[c.view addSubview:f];[relative addObject:f];}self.relativeFields=relative;
  self.detailsNote=label(@"",NSMakeRect(20,63,398,106),11,NSFontWeightRegular);self.detailsNote.textColor=NSColor.secondaryLabelColor;[c.view addSubview:self.detailsNote];
  NSButton*reset=[NSButton buttonWithTitle:@"恢复拍摄参数" target:self action:@selector(updateParameters:)];reset.tag=1;reset.frame=NSMakeRect(20,18,150,30);[c.view addSubview:reset];
  NSButton*update=[NSButton buttonWithTitle:@"重新计算配置" target:self action:@selector(updateParameters:)];update.frame=NSMakeRect(255,18,161,30);[c.view addSubview:update];
  self.details.contentViewController=c;
 }
 NSDictionary*context=self.plan?:self.matchContext,*r=self.plan[@"report"],*current=self.plan?[self settings]:nil;NSArray*keys=@[@"distortionStrength",@"tcaStrength",@"vignettingStrength"],*available=[self availabilityValues];for(int i=0;i<3;i++){self.relativeFields[i].doubleValue=current?[current[keys[i]]doubleValue]:0;self.relativeFields[i].enabled=self.plan&&[available[i]boolValue];}
 NSArray*values=LensCaptureParameterDisplayValues(context[@"metadata"]?:self.metadata),*fields=@[self.focalField,self.apertureField,self.distanceField];for(NSUInteger i=0;i<3;i++)[fields[i]setObjectValue:values[i]==NSNull.null?@"":values[i]];
 NSDictionary*effective=context[@"metadata"]?:self.metadata;for(NSUInteger i=0;i<3;i++){NSTextField*field=fields[i];BOOL fallback=i==2&&!LensPositiveCaptureNumber(effective[@"FocusDistance"])&&!LensPositiveCaptureNumber(effective[@"SubjectDistance"]);field.toolTip=fallback?LensFocusRangeFallbackNote(effective):values[i]==NSNull.null?@"原片未记录有效值；可填写已知的实际拍摄参数。未记录光圈时不会启用去暗角。":[context[@"parameterOverrides"]boolValue]?@"使用本次或文档内保存的参数覆盖；“恢复拍摄参数”重新采用原片记录。":@"自动读取自原片 EXIF 或相机 MakerNotes；无需手动输入。";}
 self.detailsNote.stringValue=[NSString stringWithFormat:@"来源：Lensfun 标定库，已加载 %@ 个配置文件。\n%@ · %@\n%@\n拍摄参数默认自动读取，可补全缺失信息或手动调整。\n不改写 RAW 元数据；重新计算后仍需点击“应用到 RAW”。",r[@"databaseFiles"]?:@0,[r[@"matchingIdentityMethod"]hasPrefix:@"normalized-exact"]?@"按数据库记录名称匹配":@"按唯一候选匹配",(@{@"LensModel":@"镜头名称",@"LensIDName":@"镜头 ID",@"Lens":@"镜头描述"}[r[@"matchingIdentitySource"]?:@""]?:@"已保存配置"),[r[@"metadataWarning"]length]?@"MakerNote 读取受限，当前使用标准 EXIF；未记录距离时采用远距离回退。":[r[@"distance_source"]isEqual:@"infinity_fallback"]?LensFocusRangeFallbackNote(effective):@"当前使用记录或手动指定的对焦距离。"];
 if(!self.plan)self.detailsNote.stringValue=@"已有拍摄参数已自动读取。只需补全缺失信息，必要时确认镜头配置。\n光圈未知可留空：畸变与色差仍可匹配，去暗角不启用。\n距离留空采用远距离标定；默认 1000 m 表示远距离回退。\n重新计算只更新建议，不改写原片 EXIF 或已保存效果。";
 [self.details showRelativeToRect:self.detailsButton.bounds ofView:self.detailsButton preferredEdge:NSRectEdgeMaxY];
}
- (void)updateParameters:(id)sender{
 NSDictionary*previous=self.plan?:self.matchContext;if(self.busy||!previous)return;
 NSDocument*doc=self.document;NSString*uuid=self.layerIdentifier;
 if(doc!=[self activeDocument]||![uuid isEqual:getter(getter(doc,@"scriptingCurrentLayer"),@"scriptUniqueID")]||![previous[@"liveFingerprint"]isEqual:LensLiveRAWFingerprint(doc,getter(doc,@"scriptingCurrentLayer"))]){self.detailsNote.stringValue=@"RAW 状态已变化，请关闭详细设置并重新匹配当前照片。";return;}
 if(![self.details.contentViewController.view.window makeFirstResponder:nil])return;
 NSDictionary*original=previous[@"baseMetadata"]?:previous[@"metadata"]?:self.metadata;
 if(!original){self.detailsNote.stringValue=@"此旧配置未保存拍摄参数，请使用原始 RAW 重新匹配。";return;}
 BOOL reset=[sender tag]==1;NSError*inputError=nil;
 NSDictionary*metadata=LensMetadataWithCaptureParameterText(original,previous[@"metadata"]?:self.metadata,@[self.focalField.stringValue,self.apertureField.stringValue,self.distanceField.stringValue],NSLocale.currentLocale,reset,&inputError);
 if(!metadata){self.detailsNote.stringValue=inputError.localizedDescription?:@"拍摄参数不可用，未改变校正。";return;}
 NSMutableDictionary*settings=self.plan?[[self settings]mutableCopy]:nil;if(!reset&&settings){NSArray*keys=@[@"distortionStrength",@"tcaStrength",@"vignettingStrength"];for(int i=0;i<3;i++){double value=self.relativeFields[i].doubleValue;if(!isfinite(value)||value<0||value>200){self.detailsNote.stringValue=@"标定倍率需在 0–200% 范围内。";return;}settings[keys[i]]=@(value);}}
 NSMutableDictionary*context=[previous mutableCopy];context[@"baseMetadata"]=original;if(reset)[context removeObjectForKey:@"parameterOverrides"];else context[@"parameterOverrides"]=@YES;
 NSURL*root=[NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"LensBridge"],*library=[NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"LensBridge/liblensfun.0.3.4.dylib"];
 self.busy=YES;NSUInteger generation=++self.generation;[self syncControls];[self.details close];self.status.stringValue=@"正在按指定拍摄参数重新计算标定…";
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
  NSError*error=nil;NSDictionary*generated=LensNativeProfilePlan(metadata,[root URLByAppendingPathComponent:@"db"],library,[context[@"report"][@"width"]unsignedIntegerValue],[context[@"report"][@"height"]unsignedIntegerValue],&error);
  NSDictionary*p=pickerReboundPlan(generated,context,metadata);
  dispatch_async(dispatch_get_main_queue(),^{
   if(generation!=self.generation)return;self.busy=NO;[self syncControls];
   if(doc!=[self activeDocument]||![uuid isEqual:getter(getter(doc,@"scriptingCurrentLayer"),@"scriptUniqueID")]||![previous[@"liveFingerprint"]isEqual:LensLiveRAWFingerprint(doc,getter(doc,@"scriptingCurrentLayer"))]){self.status.stringValue=@"计算期间 RAW 状态已变化，未更新配置。";return;}
   if(!p){NSString*message=error.localizedDescription?:@"指定参数没有有效标定，原配置保留。";if(!self.plan)[self rememberPendingContext:context metadata:metadata message:message];else self.status.stringValue=message;return;}
   self.metadata=metadata;self.matchContext=p;[self presentPlan:p document:doc identifier:uuid saved:settings?@{@"correctionSettings":settings}:nil];
   self.status.stringValue=reset?@"已恢复拍摄参数，尚未应用。三项选择保留。":@"已按指定参数重新计算，尚未应用。原始 RAW 元数据保留；未知光圈不启用去暗角。";
  });
 }});
}
@end
static LensPanelController*controller;
static void install(void){
 if(!NSApp.mainMenu)return;
 for(NSMenuItem*item in NSApp.mainMenu.itemArray)if([item.identifier isEqual:@"local.lensbridge.menu"])return;
 controller=[LensPanelController new];
 NSMenuItem*root=[[NSMenuItem alloc]initWithTitle:@"镜头矫正" action:nil keyEquivalent:@""];root.identifier=@"local.lensbridge.menu";
 NSMenu*menu=[[NSMenu alloc]initWithTitle:root.title];menu.autoenablesItems=NO;
 NSMenuItem*show=[[NSMenuItem alloc]initWithTitle:@"打开镜头矫正…" action:@selector(show:) keyEquivalent:@""];show.target=controller;show.enabled=YES;[menu addItem:show];
 root.submenu=menu;[NSApp.mainMenu insertItem:root atIndex:MAX(1,(NSInteger)NSApp.mainMenu.numberOfItems-1)];
}
__attribute__((constructor))static void loadLensPanel(void){@autoreleasepool{LensRegisterVignettingFilter();[NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){install();}];dispatch_async(dispatch_get_main_queue(),^{if(NSApp.isRunning)install();});}}
