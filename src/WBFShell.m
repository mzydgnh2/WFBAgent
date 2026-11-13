//
//  WBFShell.m
//

#import "WBFShell.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>
#import <spawn.h>
#import <sys/wait.h>
#import <signal.h>

extern char **environ;

static const int kWBFPort = 39393;

static int WBFConnect(double timeout) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons(kWBFPort);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    int r = connect(fd, (struct sockaddr *)&a, sizeof(a));
    if (r < 0 && errno == EINPROGRESS) {
        fd_set wf;
        FD_ZERO(&wf);
        FD_SET(fd, &wf);
        struct timeval tv;
        tv.tv_sec = (time_t)timeout;
        tv.tv_usec = (suseconds_t)((timeout - (double)(long)timeout) * 1e6);
        r = select(fd + 1, NULL, &wf, NULL, &tv);
        if (r <= 0) { close(fd); return -1; }
        int err = 0;
        socklen_t l = sizeof(err);
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &l);
        if (err != 0) { close(fd); return -1; }
        r = 0;
    }
    if (r < 0) { close(fd); return -1; }
    fcntl(fd, F_SETFL, flags);
    return fd;
}

static BOOL WBFWriteAll(int fd, const void *buf, size_t len) {
    const uint8_t *p = (const uint8_t *)buf;
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = write(fd, p + sent, len - sent);
        if (n <= 0) {
            if (n < 0 && errno == EINTR) continue;
            return NO;
        }
        sent += (size_t)n;
    }
    return YES;
}

@interface WBFShell ()
@property (nonatomic, assign) BOOL daemonChecked;
@property (nonatomic, assign) BOOL daemonOk;
@property (nonatomic, assign) int sessFd;
@property (nonatomic, strong) dispatch_source_t readSource;
@property (nonatomic, copy) NSString *cwd;
@end

@implementation WBFShell

+ (instancetype)shared {
    static WBFShell *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [WBFShell new]; inst.sessFd = -1; inst.cwd = @"/"; });
    return inst;
}

- (BOOL)recheckDaemon {
    self.daemonOk = (WBFConnect(0.4) >= 0);
    self.daemonChecked = YES;
    return self.daemonOk;
}

- (BOOL)daemonAvailable {
    if (!self.daemonChecked) return [self recheckDaemon];
    return self.daemonOk;
}

- (NSString *)engineName {
    if ([self daemonAvailable]) return @"root daemon (真实 root shell)";
    if ([self spawnWorks]) return @"posix_spawn (沙盒内 sh)";
    return @"builtin (受限内置命令)";
}

- (BOOL)spawnWorks {
    static int cached = -1;
    if (cached >= 0) return cached == 1;
    char *argv[] = {"/bin/sh", "-c", "true", NULL};
    pid_t pid = 0;
    int rc = posix_spawn(&pid, "/bin/sh", NULL, NULL, argv, environ);
    if (rc == 0 && pid > 0) {
        int st = 0;
        waitpid(pid, &st, 0);
        cached = 1;
        return YES;
    }
    cached = 0;
    return NO;
}

#pragma mark - execution

- (NSString *)execViaDaemon:(NSString *)command timeout:(double)timeout {
    int fd = WBFConnect(1.2);
    if (fd < 0) return nil;
    struct timeval tv;
    tv.tv_sec = (time_t)timeout;
    tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    const char *hdr = "EXEC\n";
    if (!WBFWriteAll(fd, hdr, strlen(hdr))) { close(fd); return nil; }
    NSData *body = [command dataUsingEncoding:NSUTF8StringEncoding];
    if (body.length && !WBFWriteAll(fd, body.bytes, body.length)) { close(fd); return nil; }
    shutdown(fd, SHUT_WR);

    NSMutableData *out = [NSMutableData data];
    uint8_t buf[8192];
    for (;;) {
        ssize_t n = read(fd, buf, sizeof(buf));
        if (n > 0) { [out appendBytes:buf length:(NSUInteger)n]; continue; }
        break;
    }
    close(fd);
    NSString *s = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithData:out encoding:NSISOLatin1StringEncoding];
    return s ?: @"";
}

- (NSString *)execViaSpawn:(NSString *)command timeout:(double)timeout {
    int fds[2];
    if (pipe(fds) != 0) return @"[spawn failed: pipe]";
    posix_spawn_file_actions_t acts;
    posix_spawn_file_actions_init(&acts);
    posix_spawn_file_actions_adddup2(&acts, fds[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&acts, fds[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&acts, fds[0]);

    NSString *cwd = self.cwd ?: @"/";
    NSString *wrapped = [NSString stringWithFormat:@"cd '%@' 2>/dev/null; %@", cwd, command];
    char *argv[] = {"/bin/sh", "-c", (char *)wrapped.UTF8String, NULL};
    pid_t pid = 0;
    int rc = posix_spawn(&pid, "/bin/sh", &acts, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&acts);
    close(fds[1]);
    if (rc != 0 || pid <= 0) {
        close(fds[0]);
        return nil;
    }

    NSMutableData *out = [NSMutableData data];
    struct timeval tv;
    tv.tv_sec = (time_t)timeout;
    tv.tv_usec = 0;
    setsockopt(fds[0], SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    uint8_t buf[8192];
    for (;;) {
        ssize_t n = read(fds[0], buf, sizeof(buf));
        if (n > 0) { [out appendBytes:buf length:(NSUInteger)n]; continue; }
        break;
    }
    close(fds[0]);
    int st = 0;
    waitpid(pid, &st, WNOHANG);
    NSString *s = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithData:out encoding:NSISOLatin1StringEncoding];
    return s ?: @"";
}

- (NSString *)builtin:(NSString *)raw {
    NSString *line = WBFTrim(raw);
    if (!line.length) return @"";
    NSArray *parts = [line componentsSeparatedByString:@" "];
    NSMutableArray *args = [NSMutableArray array];
    for (NSString *p in parts) if (p.length) [args addObject:p];
    if (!args.count) return @"";
    NSString *cmd = args[0];
    NSMutableArray *rest = [NSMutableArray arrayWithArray:args];
    [rest removeObjectAtIndex:0];

    if ([cmd isEqualToString:@"pwd"]) return self.cwd ?: @"/";
    if ([cmd isEqualToString:@"cd"]) {
        NSString *p = rest.count ? rest[0] : @"/";
        self.cwd = [p hasPrefix:@"/"] ? p : [self.cwd stringByAppendingPathComponent:p];
        return @"";
    }
    if ([cmd isEqualToString:@"echo"]) {
        return [rest componentsJoinedByString:@" "];
    }
    if ([cmd isEqualToString:@"id"] || [cmd isEqualToString:@"whoami"]) {
        return [NSString stringWithFormat:@"uid=%d euid=%d (app sandbox)", getuid(), geteuid()];
    }
    if ([cmd isEqualToString:@"date"]) {
        return [[NSDate date] description];
    }
    if ([cmd isEqualToString:@"uname"]) {
        return [NSString stringWithFormat:@"%@ %@", [[UIDevice currentDevice] systemName], [[UIDevice currentDevice] systemVersion]];
    }
    if ([cmd isEqualToString:@"ls"]) {
        NSString *p = rest.count ? rest[0] : (self.cwd ?: @"/");
        NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:p error:NULL];
        if (!items.count) return [NSString stringWithFormat:@"ls: %@: 无法读取", p];
        return [items componentsJoinedByString:@"\n"];
    }
    if ([cmd isEqualToString:@"cat"]) {
        if (!rest.count) return @"cat: 缺少参数";
        NSString *p = rest[0];
        NSData *d = [NSData dataWithContentsOfFile:p];
        if (!d) return [NSString stringWithFormat:@"cat: %@: 无权限或不存在", p];
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        return s ?: [NSString stringWithFormat:@"<二进制 %lu bytes>", (unsigned long)d.length];
    }
    if ([cmd isEqualToString:@"env"]) {
        NSMutableString *s = [NSMutableString string];
        NSDictionary *e = [[NSProcessInfo processInfo] environment];
        for (NSString *k in e) [s appendFormat:@"%@=%@\n", k, e[k]];
        return s;
    }
    if ([cmd isEqualToString:@"help"]) {
        return @"内置命令: pwd cd ls cat echo id date uname env openurl\n提示: 安装 root 守护进程后可获得完整 shell。";
    }
    if ([cmd isEqualToString:@"openurl"]) {
        if (!rest.count) return @"openurl: 缺少 URL";
        NSURL *u = [NSURL URLWithString:rest[0]];
        if (!u) return @"openurl: URL 无效";
        [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
        return [NSString stringWithFormat:@"opened %@", rest[0]];
    }
    return [NSString stringWithFormat:@"builtin: 未知命令 `%@`。安装 root 守护进程可获得完整 shell 能力。", cmd];
}

- (NSString *)exec:(NSString *)command timeout:(double)timeout {
    if (!command.length) return @"";
    double t = timeout > 0 ? timeout : 20.0;
    NSString *out = [self execViaDaemon:command timeout:t];
    if (out) return out;
    if ([self spawnWorks]) {
        out = [self execViaSpawn:command timeout:t];
        if (out) return out;
    }
    return [self builtin:command];
}

#pragma mark - interactive session

- (BOOL)sessionOpen {
    return self.sessFd >= 0;
}

- (BOOL)openSession {
    if (self.sessFd >= 0) return YES;
    if (![self daemonAvailable]) return NO;
    int fd = WBFConnect(1.2);
    if (fd < 0) return NO;
    const char *hdr = "SHELL\n";
    if (!WBFWriteAll(fd, hdr, strlen(hdr))) { close(fd); return NO; }
    self.sessFd = fd;

    __weak typeof(self) weakSelf = self;
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0,
                                                   dispatch_get_global_queue(0, 0));
    dispatch_source_set_event_handler(src, ^{
        uint8_t buf[4096];
        ssize_t n = read(fd, buf, sizeof(buf));
        if (n <= 0) {
            dispatch_source_cancel(src);
            return;
        }
        NSString *s = [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding];
        if (!s) s = [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSISOLatin1StringEncoding];
        NSString *text = s ?: @"";
        WBFDispatchMain(^{
            if (weakSelf.onOutput) weakSelf.onOutput(text);
        });
    });
    dispatch_source_set_cancel_handler(src, ^{
        close(fd);
    });
    self.readSource = src;
    dispatch_resume(src);
    return YES;
}

- (void)sendInput:(NSString *)input {
    if (self.sessFd < 0 || !input.length) return;
    NSData *d = [input dataUsingEncoding:NSUTF8StringEncoding];
    WBFWriteAll(self.sessFd, d.bytes, d.length);
}

- (void)closeSession {
    if (self.readSource) {
        dispatch_source_cancel(self.readSource);
        self.readSource = nil;
    }
    self.sessFd = -1;
}

@end
