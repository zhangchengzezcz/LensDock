#import "LensProfilePicker.h"
#import "LensNativeProfileEngine.h"
static NSTextField*pickerLabel(NSString*text,NSRect frame,CGFloat size,NSFontWeight weight){NSTextField*f=[NSTextField labelWithString:text];f.frame=frame;f.font=[NSFont systemFontOfSize:size weight:weight];f.maximumNumberOfLines=0;f.lineBreakMode=NSLineBreakByWordWrapping;return f;}
@interface LensProfilePicker()<NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate,NSWindowDelegate>
@property NSPanel*sheet;
@property NSDictionary*metadata,*initialSelection,*catalog;
@property NSURL*database,*library;
@property(copy)void(^completion)(NSDictionary*);
@property NSTableView*cameraTable,*lensTable;
@property NSSearchField*cameraSearch,*lensSearch;
@property NSTextField*note,*cameraTitle,*lensTitle;
@property NSButton*choose,*automatic;
@property NSArray*cameraRows,*lensRows;
@property NSString*cameraID,*lensID;
@property NSUInteger generation;
@property BOOL busy,updating,finished;
@end
@implementation LensProfilePicker
- (instancetype)initWithMetadata:(NSDictionary*)metadata databaseURL:(NSURL*)database libraryURL:(NSURL*)library completion:(void(^)(NSDictionary*))completion{
 if((self=[super init])){self.metadata=metadata;self.initialSelection=[metadata[@"LensDockProfileSelection"]isKindOfClass:NSDictionary.class]?metadata[@"LensDockProfileSelection"]:@{};self.database=database;self.library=library;self.completion=completion;self.cameraRows=@[];self.lensRows=@[];}return self;
}
- (NSTableView*)tableInView:(NSView*)root frame:(NSRect)frame label:(NSString*)name{
 NSScrollView*scroll=[[NSScrollView alloc]initWithFrame:frame];scroll.hasVerticalScroller=YES;scroll.borderType=NSBezelBorder;scroll.autohidesScrollers=YES;
 NSTableView*table=[[NSTableView alloc]initWithFrame:scroll.bounds];NSTableColumn*column=[[NSTableColumn alloc]initWithIdentifier:@"profile"];column.width=frame.size.width-18;[table addTableColumn:column];table.headerView=nil;table.rowHeight=44;table.intercellSpacing=NSMakeSize(0,2);table.allowsMultipleSelection=NO;table.allowsEmptySelection=YES;table.dataSource=self;table.delegate=self;table.columnAutoresizingStyle=NSTableViewLastColumnOnlyAutoresizingStyle;table.accessibilityLabel=name;scroll.documentView=table;[root addSubview:scroll];return table;
}
- (void)beginSheetForWindow:(NSWindow*)window{
 self.sheet=[[NSPanel alloc]initWithContentRect:NSMakeRect(0,0,660,660) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];self.sheet.title=@"选择镜头配置";self.sheet.releasedWhenClosed=NO;self.sheet.delegate=self;NSView*root=self.sheet.contentView;
 [root addSubview:pickerLabel(@"选择相机与镜头标定",NSMakeRect(24,607,612,32),22,NSFontWeightSemibold)];
 NSString*model=self.metadata[@"Model"]?:@"未记录相机",*lens=self.metadata[@"LensModel"]?:self.metadata[@"LensIDName"]?:@"未记录镜头";
 NSTextField*source=pickerLabel([NSString stringWithFormat:@"原片记录：%@ · %@\n仅使用你确认的配置，不改写 RAW 元数据。",model,lens],NSMakeRect(24,552,612,48),12,NSFontWeightRegular);source.textColor=NSColor.secondaryLabelColor;[root addSubview:source];
 self.cameraTitle=pickerLabel(@"相机与拍摄模式",NSMakeRect(24,527,612,22),13,NSFontWeightMedium);[root addSubview:self.cameraTitle];
 self.cameraSearch=[[NSSearchField alloc]initWithFrame:NSMakeRect(24,493,612,28)];self.cameraSearch.placeholderString=@"搜索相机、厂商、裁切或拍摄模式";self.cameraSearch.delegate=self;self.cameraSearch.sendsSearchStringImmediately=YES;self.cameraSearch.accessibilityLabel=@"搜索相机配置";[root addSubview:self.cameraSearch];
 self.cameraTable=[self tableInView:root frame:NSMakeRect(24,361,612,125) label:@"相机模式候选"];
 self.lensTitle=pickerLabel(@"镜头校准",NSMakeRect(24,330,612,22),13,NSFontWeightMedium);[root addSubview:self.lensTitle];
 self.lensSearch=[[NSSearchField alloc]initWithFrame:NSMakeRect(24,298,612,28)];self.lensSearch.placeholderString=@"搜索兼容镜头、投影或校准尺寸";self.lensSearch.delegate=self;self.lensSearch.sendsSearchStringImmediately=YES;self.lensSearch.accessibilityLabel=@"搜索兼容镜头校准";[root addSubview:self.lensSearch];
 self.lensTable=[self tableInView:root frame:NSMakeRect(24,139,612,152) label:@"兼容镜头校准候选"];
 self.note=pickerLabel(@"正在读取配置…",NSMakeRect(24,64,612,62),12,NSFontWeightRegular);self.note.textColor=NSColor.secondaryLabelColor;[root addSubview:self.note];
 self.automatic=[NSButton buttonWithTitle:@"恢复自动匹配" target:self action:@selector(restoreAutomatic:)];self.automatic.frame=NSMakeRect(24,20,150,32);[root addSubview:self.automatic];
 NSButton*cancel=[NSButton buttonWithTitle:@"取消" target:self action:@selector(cancel:)];cancel.frame=NSMakeRect(380,20,104,32);cancel.keyEquivalent=@"\e";[root addSubview:cancel];
 self.choose=[NSButton buttonWithTitle:@"使用所选配置" target:self action:@selector(accept:)];self.choose.frame=NSMakeRect(494,20,142,32);self.choose.keyEquivalent=@"\r";self.choose.enabled=NO;[root addSubview:self.choose];
 [window beginSheet:self.sheet completionHandler:^(NSModalResponse response){}];[self loadCandidatesInitial:YES];
}
- (NSDictionary*)rowWithID:(NSString*)identifier in:(NSArray*)rows{for(NSDictionary*r in rows)if([r[@"id"]isEqual:identifier])return r;return nil;}
- (void)loadCandidatesInitial:(BOOL)initial{
 if(self.finished)return;self.busy=YES;self.choose.enabled=NO;self.automatic.enabled=NO;self.note.stringValue=@"正在核对相机卡口与校准版本…";NSUInteger generation=++self.generation;
 NSMutableDictionary*m=[self.metadata mutableCopy];[m removeObjectForKey:@"LensDockProfileSelection"];if(self.cameraID)m[@"LensDockProfileSelection"]=@{@"cameraID":self.cameraID};
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
  NSError*error=nil;NSDictionary*catalog=LensNativeProfileCandidates(m,self.database,self.library,&error);
  dispatch_async(dispatch_get_main_queue(),^{
   if(self.finished||generation!=self.generation)return;self.busy=NO;self.automatic.enabled=YES;
   if(!catalog){self.note.stringValue=error.localizedDescription?:@"配置读取失败，当前校正保留。";return;}
   self.catalog=catalog;
   if(initial&&[self rowWithID:self.initialSelection[@"cameraID"] in:catalog[@"cameras"]]&&! [self.initialSelection[@"cameraID"]isEqual:catalog[@"selectedCameraID"]]){self.cameraID=self.initialSelection[@"cameraID"];[self filterRows];[self loadCandidatesInitial:NO];return;}
   if(!self.cameraID)self.cameraID=[catalog[@"selectedCameraID"]length]?catalog[@"selectedCameraID"]:nil;
   NSString*wanted=self.initialSelection[@"lensID"];
   self.lensID=[self rowWithID:wanted in:catalog[@"lenses"]]?wanted:[catalog[@"selectedLensID"]length]?catalog[@"selectedLensID"]:nil;
   self.initialSelection=@{};[self filterRows];[self updateNote];
  });
 }});
}
- (NSArray*)filtered:(NSArray*)rows query:(NSString*)query{
 if(!query.length)return rows?:@[];NSMutableArray*out=[NSMutableArray new];for(NSDictionary*r in rows){NSString*haystack=[NSString stringWithFormat:@"%@ %@ %@",r[@"title"],r[@"maker"],r[@"subtitle"]];if([haystack rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound)[out addObject:r];}return out;
}
- (void)filterRows{
 self.cameraRows=[self filtered:self.catalog[@"cameras"] query:self.cameraSearch.stringValue];self.lensRows=[self filtered:self.catalog[@"lenses"] query:self.lensSearch.stringValue];self.updating=YES;
 for(NSTableView*table in @[self.cameraTable,self.lensTable]){NSArray*rows=table==self.cameraTable?self.cameraRows:self.lensRows;NSString*identifier=table==self.cameraTable?self.cameraID:self.lensID;[table reloadData];NSInteger selected=-1;for(NSUInteger i=0;i<rows.count;i++)if([rows[i][@"id"]isEqual:identifier]){selected=i;break;}if(selected>=0){[table selectRowIndexes:[NSIndexSet indexSetWithIndex:selected] byExtendingSelection:NO];[table scrollRowToVisible:selected];}else [table deselectAll:nil];}
 self.updating=NO;
}
- (void)controlTextDidChange:(NSNotification*)notification{[self filterRows];}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table{return (table==self.cameraTable?self.cameraRows:self.lensRows).count;}
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)index{
 NSDictionary*r=(table==self.cameraTable?self.cameraRows:self.lensRows)[index];NSView*cell=[[NSView alloc]initWithFrame:NSMakeRect(0,0,column.width,44)];cell.autoresizingMask=NSViewWidthSizable;
 NSTextField*title=pickerLabel(r[@"title"],NSMakeRect(10,23,column.width-20,19),13,NSFontWeightMedium);title.maximumNumberOfLines=1;title.lineBreakMode=NSLineBreakByTruncatingTail;title.autoresizingMask=NSViewWidthSizable;[cell addSubview:title];
 NSString*detail=[r[@"subtitle"]stringByAppendingString:[r[@"matchesMetadata"]boolValue]?@" · 原片匹配候选":@""];NSTextField*subtitle=pickerLabel(detail,NSMakeRect(10,3,column.width-20,18),11,NSFontWeightRegular);subtitle.maximumNumberOfLines=1;subtitle.lineBreakMode=NSLineBreakByTruncatingTail;subtitle.textColor=NSColor.secondaryLabelColor;subtitle.autoresizingMask=NSViewWidthSizable;[cell addSubview:subtitle];cell.toolTip=[NSString stringWithFormat:@"%@\n%@",r[@"title"],detail];cell.accessibilityLabel=cell.toolTip;return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification*)notification{
 if(self.updating||self.finished)return;NSTableView*table=notification.object;NSInteger row=table.selectedRow;if(row<0)return;
 if(table==self.cameraTable){NSString*identifier=self.cameraRows[row][@"id"];if([identifier isEqual:self.cameraID])return;self.cameraID=identifier;self.lensID=nil;self.initialSelection=@{};self.catalog=@{@"cameras":self.catalog[@"cameras"]?:@[],@"lenses":@[]};self.lensSearch.stringValue=@"";[self filterRows];[self loadCandidatesInitial:NO];}
 else if(!self.busy){self.lensID=self.lensRows[row][@"id"];[self updateNote];}
}
- (void)updateNote{
 NSDictionary*camera=[self rowWithID:self.cameraID in:self.catalog[@"cameras"]],*lens=[self rowWithID:self.lensID in:self.catalog[@"lenses"]];self.choose.enabled=!self.busy&&camera&&lens;
 self.cameraTitle.stringValue=camera?[NSString stringWithFormat:@"相机与拍摄模式 · %@",camera[@"title"]]:@"相机与拍摄模式 · 请确认拍摄模式";
 self.lensTitle.stringValue=lens?@"镜头校准 · 已选择一套标定":@"镜头校准 · 请选择明确的校准版本";
 if(!camera){self.note.stringValue=@"原片名称不能唯一确认相机模式。请先选择相机及拍摄时的裁切模式；不会从编辑后的画布比例猜测。";return;}
 if(!lens){self.note.stringValue=self.catalog[@"lenses"]&&[self.catalog[@"lenses"]count]?@"请选择你确认的镜头校准。相同名称的不同投影或裁切版本分别显示。":@"此相机没有兼容校准；可搜索并核对其他相机模式。当前校正保留。";return;}
 NSDictionary*a=lens[@"availableAtCapture"];NSMutableArray*parts=[NSMutableArray new];for(NSString*key in @[@"distortion",@"tca",@"vignetting"])if([a[key]boolValue])[parts addObject:@{@"distortion":@"畸变",@"tca":@"色差",@"vignetting":@"暗角"}[key]];
 self.note.stringValue=[NSString stringWithFormat:@"所选标定：%@\n当前拍摄参数可插值：%@。确认后重新计算建议；不会立即应用校正。",lens[@"title"],parts.count?[parts componentsJoinedByString:@"、"]:@"暂无，需要核对拍摄参数"];
}
- (void)finish:(NSDictionary*)selection{
 if(self.finished)return;self.finished=YES;self.generation++;[self.sheet.sheetParent endSheet:self.sheet];[self.sheet orderOut:nil];if(self.completion)self.completion(selection);
}
- (void)accept:(id)sender{if(self.choose.enabled)[self finish:@{@"cameraID":self.cameraID,@"lensID":self.lensID}];}
- (void)restoreAutomatic:(id)sender{if(!self.busy)[self finish:@{}];}
- (void)cancel:(id)sender{[self finish:nil];}
- (BOOL)windowShouldClose:(NSWindow*)window{[self cancel:nil];return NO;}
@end
