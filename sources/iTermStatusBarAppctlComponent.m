//
//  iTermStatusBarAppctlComponent.m
//  iTerm2SharedARC
//

#import "iTermStatusBarAppctlComponent.h"

#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"

#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const kAppctlSocketPath = @"/tmp/appctl.sock";
static NSString *const kAppctlProcsRegistryPath = @".appctl/procs/registry.json";

@implementation iTermStatusBarAppctlComponent {
    NSString *_cachedText;
    BOOL _fetching;
}

#pragma mark - iTermStatusBarComponent

- (nullable NSImage *)statusBarComponentIcon {
    return nil;
}

- (NSString *)statusBarComponentShortDescription {
    return @"appctl Status";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows VS Code windows, Chrome sessions, and background processes managed by appctl.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"VS forma(1)  CH Profile 1  ●backend ●backoffice";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return 5.0;
}

- (nullable NSArray<NSString *> *)stringVariants {
    return @[ _cachedText ?: @"appctl" ];
}

- (void)statusBarComponentUpdate {
    [self refresh];
}

#pragma mark - Init

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        _cachedText = @"appctl…";
        [self refresh];
    }
    return self;
}

#pragma mark - Data fetching

- (void)refresh {
    if (_fetching) return;
    _fetching = YES;

    dispatch_group_t group = dispatch_group_create();
    __block NSString *vsText = nil;
    __block NSString *chText = nil;
    __weak __typeof(self) weakSelf = self;

    // Query VS Code windows from daemon
    dispatch_group_enter(group);
    [self queryDaemon:@{ @"target": @"vscode", @"command": @"windows" }
           completion:^(NSDictionary * _Nullable result) {
        vsText = [weakSelf formatVscodeWindows:result];
        dispatch_group_leave(group);
    }];

    // Query Chrome sessions from daemon
    dispatch_group_enter(group);
    [self queryDaemon:@{ @"target": @"chrome", @"command": @"sessions" }
           completion:^(NSDictionary * _Nullable result) {
        chText = [weakSelf formatChromeSessions:result];
        dispatch_group_leave(group);
    }];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSString *procText = [strongSelf readProcList];
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        if (vsText.length)   [parts addObject:vsText];
        if (chText.length)   [parts addObject:chText];
        if (procText.length) [parts addObject:procText];

        strongSelf->_cachedText = parts.count ? [parts componentsJoinedByString:@"  ·  "] : @"appctl";
        strongSelf->_fetching = NO;
        [strongSelf updateTextFieldIfNeeded];
    });
}

/// Connects to /tmp/appctl.sock, sends `payload` as a newline-terminated JSON
/// object, reads the response, and calls `completion` on the main queue.
/// Calls completion(nil) on any error.
- (void)queryDaemon:(NSDictionary *)payload
         completion:(void (^)(NSDictionary * _Nullable))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *result = [self synchronousQueryDaemon:payload];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    });
}

- (nullable NSDictionary *)synchronousQueryDaemon:(NSDictionary *)payload {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return nil;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, kAppctlSocketPath.UTF8String, sizeof(addr.sun_path));

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return nil;
    }

    // Set a 2-second read/write timeout so a hung daemon doesn't block the UI
    struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!jsonData) { close(fd); return nil; }

    NSMutableData *toSend = [jsonData mutableCopy];
    [toSend appendBytes:"\n" length:1];
    write(fd, toSend.bytes, toSend.length);

    NSMutableData *buffer = [NSMutableData data];
    char chunk[4096];
    ssize_t n;
    while ((n = read(fd, chunk, sizeof(chunk))) > 0) {
        [buffer appendBytes:chunk length:n];
    }
    close(fd);

    if (!buffer.length) return nil;
    return [NSDictionary castFrom:[NSJSONSerialization JSONObjectWithData:buffer options:0 error:nil]];
}

#pragma mark - Formatting

- (NSString *)formatVscodeWindows:(nullable NSDictionary *)result {
    if (![result[@"ok"] boolValue]) return @"VS —";
    NSArray *windows = [NSArray castFrom:result[@"windows"]];
    if (!windows.count) return @"VS —";

    NSInteger activeIdx = [[NSNumber castFrom:result[@"active"]] integerValue];
    NSDictionary *activeWin = (activeIdx < (NSInteger)windows.count)
        ? windows[activeIdx] : windows.firstObject;
    NSString *title = [NSString castFrom:activeWin[@"title"]] ?: @"?";
    // Use last path component of the title (VS Code shows directory as title)
    NSString *name = title.pathComponents.lastObject ?: title;
    if (name.length > 16) name = [name substringToIndex:16];
    return [NSString stringWithFormat:@"VS %@(%ld)", name, (long)windows.count];
}

- (NSString *)formatChromeSessions:(nullable NSDictionary *)result {
    if (![result[@"ok"] boolValue]) return @"CH —";
    NSArray *sessions = [NSArray castFrom:result[@"sessions"]];
    if (!sessions.count) return @"CH —";

    // The last session is the most recently activated one
    NSDictionary *active = sessions.lastObject;
    NSString *profile = [NSString castFrom:active[@"profile"]] ?: @"?";
    if (profile.length > 12) profile = [profile substringToIndex:12];
    return [NSString stringWithFormat:@"CH %@(%ld)", profile, (long)sessions.count];
}

/// Reads ~/.appctl/procs/registry.json directly and formats running/stopped procs.
- (NSString *)readProcList {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:kAppctlProcsRegistryPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @"";

    NSArray *procs = [NSArray castFrom:[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]];
    if (!procs.count) return @"";

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSDictionary *p in procs) {
        NSNumber *pidNum = [NSNumber castFrom:p[@"pid"]];
        NSString *name = [NSString castFrom:p[@"name"]] ?: @"?";
        BOOL alive = pidNum && (kill(pidNum.intValue, 0) == 0);
        [parts addObject:[NSString stringWithFormat:@"%@%@", alive ? @"●" : @"○", name]];
    }
    return [parts componentsJoinedByString:@" "];
}

@end

NS_ASSUME_NONNULL_END
