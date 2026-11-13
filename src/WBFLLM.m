//
//  WBFLLM.m
//

#import "WBFLLM.h"

NSInteger WBFEstimateTokens(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || !text.length) return 0;
    NSInteger cjk = 0;
    NSInteger n = (NSInteger)text.length;
    for (NSInteger i = 0; i < n; i++) {
        unichar c = [text characterAtIndex:(NSUInteger)i];
        if (c >= 0x2E80 && c <= 0x9FFF) cjk++;
        else if (c >= 0xF900 && c <= 0xFAFF) cjk++;
        else if (c >= 0xFF00 && c <= 0xFFEF) cjk++;
    }
    NSInteger other = n - cjk;
    NSInteger t = cjk + (NSInteger)ceil((double)other / 3.4);
    return t + 4;
}

NSInteger WBFEstimateMessages(NSArray<WBFMsg *> *messages) {
    NSInteger total = 0;
    for (WBFMsg *m in messages) {
        total += WBFEstimateTokens(m.content);
        for (NSDictionary *c in m.toolCalls) {
            total += WBFEstimateTokens(c[@"name"]);
            total += WBFEstimateTokens(c[@"args"]);
        }
        total += 8;
        if (m.images.count) total += (NSInteger)m.images.count * 780; // rough vision cost
    }
    return total;
}

@interface WBFLLM ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation WBFLLM

+ (instancetype)shared {
    static WBFLLM *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [WBFLLM new];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 240;
        cfg.timeoutIntervalForResource = 300;
        cfg.HTTPAdditionalHeaders = @{};
        inst.session = [NSURLSession sessionWithConfiguration:cfg];
    });
    return inst;
}

- (NSString *)endpoint:(NSString *)suffix {
    WBFConfig *cfg = [WBFConfig shared];
    NSString *base = WBFTrim(cfg.baseURL);
    if (!base.length) base = @"https://api.openai.com/v1";
    while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    if ([base hasSuffix:@"chat/completions"] || [base hasSuffix:@"completions"]) {
        // user pasted a full endpoint
        if ([suffix isEqualToString:@"/chat/completions"]) return base;
        NSRange r = [base rangeOfString:@"/chat/completions"];
        if (r.location != NSNotFound) base = [base substringToIndex:r.location];
    }
    return [base stringByAppendingString:suffix];
}

- (NSError *)errorWith:(NSString *)msg code:(NSInteger)code {
    return [NSError errorWithDomain:@"WBFLLM" code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg ?: @"unknown error"}];
}

- (void)chat:(NSArray<WBFMsg *> *)messages tools:(NSArray *)tools completion:(WBFLLMCompletion)done {
    WBFConfig *cfg = [WBFConfig shared];
    if (!WBFTrim(cfg.apiKey).length) {
        if (done) done(nil, nil, [self errorWith:@"尚未填写 API Key，请先到「设置」页配置。" code:401]);
        return;
    }

    NSMutableArray *apiMessages = [NSMutableArray array];
    for (WBFMsg *m in messages) [apiMessages addObject:[m apiDict]];

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"model"] = cfg.model.length ? cfg.model : @"gpt-4o";
    body[@"messages"] = apiMessages;
    body[@"temperature"] = @(cfg.temperature);
    body[@"stream"] = @NO;
    if (tools.count) {
        body[@"tools"] = tools;
        body[@"tool_choice"] = @"auto";
    }
    if (cfg.maxTokens > 0) body[@"max_tokens"] = @(cfg.maxTokens);

    NSError *jsonErr = nil;
    NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
    if (!payload) {
        if (done) done(nil, nil, [self errorWith:@"请求序列化失败" code:400]);
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self endpoint:@"/chat/completions"]]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 240;
    [req setValue:[NSString stringWithFormat:@"Bearer %@", WBFTrim(cfg.apiKey)] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setHTTPBody:payload];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) { if (done) done(nil, nil, err); return; }
        NSInteger status = 200;
        if ([resp isKindOfClass:[NSHTTPURLResponse class]]) status = [(NSHTTPURLResponse *)resp statusCode];
        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (![obj isKindOfClass:[NSDictionary class]]) {
            NSString *snippet = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            if (snippet.length > 300) snippet = [snippet substringToIndex:300];
            if (done) done(nil, nil, [self errorWith:[NSString stringWithFormat:@"响应无法解析 (HTTP %ld): %@", (long)status, snippet] code:status]);
            return;
        }
        NSDictionary *root = (NSDictionary *)obj;
        if (root[@"error"]) {
            id e = root[@"error"];
            NSString *msg = [e isKindOfClass:[NSDictionary class]] ? (e[@"message"] ?: [e description]) : [e description];
            if (done) done(nil, nil, [self errorWith:[NSString stringWithFormat:@"API 错误: %@", msg] code:status]);
            return;
        }
        NSArray *choices = root[@"choices"];
        if (![choices isKindOfClass:[NSArray class]] || !choices.count) {
            if (done) done(nil, nil, [self errorWith:[NSString stringWithFormat:@"响应缺少 choices (HTTP %ld)", (long)status] code:status]);
            return;
        }
        NSDictionary *choice = choices[0];
        NSDictionary *message = [choice isKindOfClass:[NSDictionary class]] ? choice[@"message"] : nil;
        if (![message isKindOfClass:[NSDictionary class]]) {
            if (done) done(nil, nil, [self errorWith:@"响应缺少 message" code:status]);
            return;
        }
        NSDictionary *usage = root[@"usage"];
        if ([usage isKindOfClass:[NSDictionary class]]) {
            self.lastTotalTokens = [usage[@"total_tokens"] integerValue];
        }
        if (done) done(message, [usage isKindOfClass:[NSDictionary class]] ? usage : nil, nil);
    }];
    [task resume];
}

- (void)fetchModels:(WBFModelsCompletion)done {
    WBFConfig *cfg = [WBFConfig shared];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self endpoint:@"/models"]]];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 30;
    if (WBFTrim(cfg.apiKey).length) {
        [req setValue:[NSString stringWithFormat:@"Bearer %@", WBFTrim(cfg.apiKey)] forHTTPHeaderField:@"Authorization"];
    }
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) { if (done) done(nil, err); return; }
        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSMutableArray *ids = [NSMutableArray array];
        if ([obj isKindOfClass:[NSDictionary class]]) {
            id list = ((NSDictionary *)obj)[@"data"];
            if ([list isKindOfClass:[NSArray class]]) {
                for (id item in (NSArray *)list) {
                    if ([item isKindOfClass:[NSDictionary class]]) {
                        NSString *mid = item[@"id"];
                        if ([mid isKindOfClass:[NSString class]]) [ids addObject:mid];
                    }
                }
            } else if (((NSDictionary *)obj)[@"models"]) {
                id list2 = ((NSDictionary *)obj)[@"models"];
                if ([list2 isKindOfClass:[NSArray class]]) ids = [NSMutableArray arrayWithArray:list2];
            }
        }
        [ids sortUsingSelector:@selector(compare:)];
        if (!ids.count) {
            if (done) done(nil, [self errorWith:@"无法获取模型列表，请检查 Base URL / Key" code:404]);
            return;
        }
        if (done) done(ids, nil);
    }] resume];
}

- (void)probe:(void (^)(NSString *summary))done {
    WBFMsg *m = [WBFMsg role:@"user" content:@"回复两个字：正常"];
    [self chat:@[m] tools:nil completion:^(NSDictionary *message, NSDictionary *usage, NSError *error) {
        if (error) { if (done) done([NSString stringWithFormat:@"失败：%@", error.localizedDescription]); return; }
        NSString *txt = message[@"content"];
        if (![txt isKindOfClass:[NSString class]]) txt = @"(空)";
        if (done) done([NSString stringWithFormat:@"连通正常 · 回复：%@", txt]);
    }];
}

@end
