#import "LensNativeProfileEngine.h"

int main(void) {
    @autoreleasepool {
        NSData *input = [NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile];
        NSArray *requests = [NSJSONSerialization JSONObjectWithData:input options:0 error:nil];
        if (![requests isKindOfClass:NSArray.class]) return 1;
        NSURL *database = [NSURL fileURLWithPath:@"Resources/LensBridge/db"];
        NSURL *library = [NSURL fileURLWithPath:@"Vendor/Lib/liblensfun.0.3.4.dylib"];
        NSMutableDictionary *byMaker = [NSMutableDictionary new];
        NSUInteger accepted = 0;
        for (NSDictionary *metadata in requests) {
            @autoreleasepool {
                NSString *maker = metadata[@"Make"];
                NSMutableDictionary *counts = byMaker[maker];
                if (!counts) {
                    counts = [@{@"accepted": @0, @"unresolved": @0} mutableCopy];
                    byMaker[maker] = counts;
                }
                NSDictionary *plan = LensNativeProfilePlan(metadata, database, library, 96, 64, nil);
                BOOL matched = [plan[@"report"][@"matchedLensProfileID"] length] > 0;
                accepted += matched;
                NSString *outcome = matched ? @"accepted" : @"unresolved";
                counts[outcome] = @([counts[outcome] unsignedIntegerValue] + 1);
            }
        }
        NSDictionary *result = @{@"accepted": @(accepted), @"unresolved": @(requests.count - accepted), @"byMake": byMaker};
        NSData *output = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        if (!output) return 2;
        [NSFileHandle.fileHandleWithStandardOutput writeData:output];
    }
}
