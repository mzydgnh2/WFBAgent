//
//  WBFConfig.m
//

#import "WBFConfig.h"

@interface WBFConfig () {
    NSMutableArray *_records;
}
@property (nonatomic, strong) NSMutableArray *records;
@end

@implementation WBFMsg

+ (instancetype)role:(NSString *)role content:(NSString *)content {
    WBFMsg *m = [WBFMsg new];
    m.role = role;
    m.content = content ?: @"";
    return m;
}

- (NSDictionary *)apiDict {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"role"] = self.role ?: @"user";
    if (self.images.count && ![self.role isEqualToString:@"tool"]) {
        NSMutableArray *parts = [NSMutableArray array];
        if (self.content.length) [parts addObject:@{@"type": @"text", @"text": self.content}];
        for (NSString *b64 in self.images) {
            [parts addObject:@{
                @"type": @"image_url",
                @"image_url": @{@"url": [NSString stringWithFormat:@"data:image/jpeg;base64,%@", b64]}
            }];
        }
        d[@"content"] = parts;
    } else {
        d[@"content"] = self.content ?: @"";
    }
    if (self.toolCalls.count) {
        NSMutableArray *tc = [NSMutableArray array];
        for (NSDictionary *c in self.toolCalls) {
            NSString *cid = c[@"id"] ?: @"";
            NSString *cname = c[@"name"] ?: @"";
            NSString *cargs = c[@"args"] ?: @"{}";
            [tc addObject:@{@"id": cid, @"type": @"function",
                            @"function": @{@"name": cname, @"arguments": cargs}}];
        }
        d[@"tool_calls"] = tc;
    }
    if (self.toolCallId.length) d[@"tool_call_id"] = self.toolCallId;
    return d;
}

- (NSDictionary *)logDict {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"role"] = self.role ?: @"user";
    d[@"text"] = self.content ?: @"";
    return d;
}

+ (instancetype)fromLogDict:(NSDictionary *)d {
    WBFMsg *m = [WBFMsg new];
    m.role = d[@"role"] ?: @"user";
    m.content = d[@"text"] ?: @"";
    return m;
}

@end

@implementation WBFTaskRecord

+ (instancetype)newTask:(NSString *)task {
    WBFTaskRecord *r = [WBFTaskRecord new];
    r.taskId = [[NSUUID UUID] UUIDString];
    r.task = task ?: @"";
    r.date = [NSDate date];
    r.log = [NSMutableArray array];
    r.status = @"running";
    r.tokens = 0;
    r.steps = 0;
    return r;
}

- (NSString *)displayTitle {
    NSString *t = WBFTrim(self.task);
    if (!t.length) return @"未命名任务";
    if (t.length > 24) return [[t substringToIndex:24] stringByAppendingString:@"…"];
    return t;
}

- (NSDictionary *)dict {
    return @{
        @"taskId": self.taskId ?: @"",
        @"task": self.task ?: @"",
        @"date": @([self.date timeIntervalSince1970]),
        @"log": self.log ?: @[],
        @"tokens": @(self.tokens),
        @"steps": @(self.steps),
        @"status": self.status ?: @"done"
    };
}

+ (instancetype)fromDict:(NSDictionary *)d {
    WBFTaskRecord *r = [WBFTaskRecord new];
    r.taskId = d[@"taskId"] ?: [[NSUUID UUID] UUIDString];
    r.task = d[@"task"] ?: @"";
    NSNumber *ts = d[@"date"];
    r.date = [NSDate dateWithTimeIntervalSince1970:ts.doubleValue];
    NSArray *log = d[@"log"];
    r.log = [NSMutableArray arrayWithArray:[log isKindOfClass:[NSArray class]] ? log : @[]];
    r.tokens = [d[@"tokens"] integerValue];
    r.steps = [d[@"steps"] integerValue];
    r.status = d[@"status"] ?: @"done";
    return r;
}

@end

@implementation WBFConfig

+ (instancetype)shared {
    static WBFConfig *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [WBFConfig new]; [inst load]; });
    return inst;
}

- (void)load {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    self.baseURL     = [d stringForKey:@"wbf_baseURL"] ?: @"https://api.openai.com/v1";
    self.apiKey      = [d stringForKey:@"wbf_apiKey"] ?: @"";
    self.model       = [d stringForKey:@"wbf_model"] ?: @"gpt-4o";
    self.modelList   = [d arrayForKey:@"wbf_modelList"] ?: @[];
    NSInteger mc     = [d integerForKey:@"wbf_maxContext"];
    self.maxContext  = mc > 0 ? mc : 128000;
    double t         = [d doubleForKey:@"wbf_temperature"];
    self.temperature = (t > 0.001) ? t : 0.3;
    NSInteger ms     = [d integerForKey:@"wbf_maxSteps"];
    self.maxSteps    = ms > 0 ? ms : 30;
    self.maxTokens   = [d integerForKey:@"wbf_maxTokens"];
    if ([d objectForKey:@"wbf_sendScreenshot"]) self.sendScreenshot = [d boolForKey:@"wbf_sendScreenshot"];
    else self.sendScreenshot = YES;
    if ([d objectForKey:@"wbf_confirmDanger"]) self.confirmDanger = [d boolForKey:@"wbf_confirmDanger"];
    else self.confirmDanger = NO;
    self.inputMode = [d integerForKey:@"wbf_inputMode"];
    double op = [d doubleForKey:@"wbf_ballOpacity"];
    self.ballOpacity = (op > 0.01) ? op : 0.92;
    self.ballAutostart = [d boolForKey:@"wbf_ballAutostart"];
    self.language = [d stringForKey:@"wbf_language"] ?: @"zh";
    self.terminalFallbackEcho = YES;
}

- (void)save {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:self.baseURL ?: @"" forKey:@"wbf_baseURL"];
    [d setObject:self.apiKey ?: @"" forKey:@"wbf_apiKey"];
    [d setObject:self.model ?: @"" forKey:@"wbf_model"];
    [d setObject:self.modelList ?: @[] forKey:@"wbf_modelList"];
    [d setInteger:self.maxContext forKey:@"wbf_maxContext"];
    [d setDouble:self.temperature forKey:@"wbf_temperature"];
    [d setInteger:self.maxSteps forKey:@"wbf_maxSteps"];
    [d setInteger:self.maxTokens forKey:@"wbf_maxTokens"];
    [d setBool:self.sendScreenshot forKey:@"wbf_sendScreenshot"];
    [d setInteger:self.inputMode forKey:@"wbf_inputMode"];
    [d setBool:self.confirmDanger forKey:@"wbf_confirmDanger"];
    [d setDouble:self.ballOpacity forKey:@"wbf_ballOpacity"];
    [d setBool:self.ballAutostart forKey:@"wbf_ballAutostart"];
    [d setObject:self.language ?: @"zh" forKey:@"wbf_language"];
    [d synchronize];
}

- (NSString *)historyPath {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = dirs.firstObject ?: NSTemporaryDirectory();
    return [dir stringByAppendingPathComponent:@"wbf_history.json"];
}

- (NSArray<WBFTaskRecord *> *)history {
    NSData *data = [NSData dataWithContentsOfFile:[self historyPath]];
    if (!data) return @[];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![obj isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *arr = [NSMutableArray array];
    for (NSDictionary *d in (NSArray *)obj) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        [arr addObject:[WBFTaskRecord fromDict:d]];
    }
    return arr;
}

- (void)saveHistory {
    NSMutableArray *raw = [NSMutableArray array];
    for (WBFTaskRecord *r in self.records) [raw addObject:[r dict]];
    NSData *data = [NSJSONSerialization dataWithJSONObject:raw options:0 error:NULL];
    [data writeToFile:[self historyPath] atomically:YES];
}

- (NSMutableArray *)records {
    if (!_records) {
        _records = [NSMutableArray arrayWithArray:[self history]];
    }
    return _records;
}

- (void)addRecord:(WBFTaskRecord *)rec {
    if (!rec) return;
    NSMutableArray *arr = self.records;
    [arr insertObject:rec atIndex:0];
    while (arr.count > 60) [arr removeLastObject];
    [self saveHistory];
}

- (void)removeRecord:(NSString *)taskId {
    NSMutableArray *arr = self.records;
    for (NSInteger i = arr.count - 1; i >= 0; i--) {
        WBFTaskRecord *r = arr[i];
        if ([r.taskId isEqualToString:taskId]) [arr removeObjectAtIndex:i];
    }
    [self saveHistory];
}

- (void)clearHistory {
    [self.records removeAllObjects];
    [self saveHistory];
}

@end
