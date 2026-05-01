//
//  iTermBottomBar.m
//  iTerm2
//

#import "iTermBottomBar.h"
#import "iTermActionsModel.h"
#import <objc/runtime.h>

#include <mach/mach.h>
#include <sys/mount.h>
#include <sys/statvfs.h>
#include <sys/sysctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>

const CGFloat iTermBottomBarHeight = 28.0;

// Horizontal padding inside the bar.
static const CGFloat kPadding = 8.0;
// Vertical inset so controls sit centred in the bar.
static const CGFloat kControlInset = 4.0;
// Width of the transparency slider.
static const CGFloat kSliderWidth = 100.0;

// ---------------------------------------------------------------------------
#pragma mark - Shortcuts popover
// ---------------------------------------------------------------------------

@interface iTermShortcutsPopoverViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithDelegate:(id<iTermBottomBarDelegate>)delegate
                       bottomBar:(iTermBottomBar *)bar
                         popover:(NSPopover *)popover;
@end

@implementation iTermShortcutsPopoverViewController {
    NSTableView                  *_tableView;
    NSButton                     *_runButton;
    NSButton                     *_newWindowButton;
    NSArray<iTermAction *>       *_actions;
    __weak id<iTermBottomBarDelegate>  _delegate;
    __weak iTermBottomBar        *_bottomBar;
    __weak NSPopover             *_popover;
}

- (instancetype)initWithDelegate:(id<iTermBottomBarDelegate>)delegate
                       bottomBar:(iTermBottomBar *)bar
                         popover:(NSPopover *)popover {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _delegate = delegate;
        _bottomBar = bar;
        _popover = popover;
    }
    return self;
}

- (void)loadView {
    const CGFloat W = 280, H = 300;
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, H)];

    // --- Title ---------------------------------------------------------------
    NSTextField *titleLabel = [NSTextField labelWithString:@"Shortcuts"];
    titleLabel.font = [NSFont boldSystemFontOfSize:13];
    titleLabel.frame = NSMakeRect(12, H - 32, W - 24, 20);
    [root addSubview:titleLabel];

    // --- Scrollable table ----------------------------------------------------
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 44, W, H - 44 - 36)];
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSNoBorder;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    col.width = W - 4;
    [_tableView addTableColumn:col];
    _tableView.headerView = nil;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.doubleAction = @selector(_doubleClick:);
    _tableView.target = self;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    scrollView.documentView = _tableView;
    [root addSubview:scrollView];

    // --- Button row ----------------------------------------------------------
    const CGFloat btnY = 10, btnH = 24;

    NSButton *manageButton = [NSButton buttonWithTitle:@"Manage..."
                                                target:self
                                                action:@selector(_manageClicked:)];
    manageButton.bezelStyle = NSBezelStyleRounded;
    [manageButton sizeToFit];
    manageButton.frame = NSMakeRect(12, btnY, manageButton.frame.size.width, btnH);
    [root addSubview:manageButton];

    _newWindowButton = [NSButton buttonWithTitle:@"New Window"
                                          target:self
                                          action:@selector(_newWindowClicked:)];
    _newWindowButton.bezelStyle = NSBezelStyleRounded;
    [_newWindowButton sizeToFit];
    CGFloat nwW = _newWindowButton.frame.size.width;
    _newWindowButton.frame = NSMakeRect(W - 12 - nwW, btnY, nwW, btnH);
    [root addSubview:_newWindowButton];

    _runButton = [NSButton buttonWithTitle:@"Run"
                                    target:self
                                    action:@selector(_runClicked:)];
    _runButton.bezelStyle = NSBezelStyleRounded;
    [_runButton sizeToFit];
    CGFloat runW = _runButton.frame.size.width;
    _runButton.frame = NSMakeRect(NSMinX(_newWindowButton.frame) - 8 - runW, btnY, runW, btnH);
    [root addSubview:_runButton];

    self.view = root;
    [self _reloadActions];
    [self _updateButtons];
}

- (void)_reloadActions {
    _actions = [[iTermActionsModel sharedInstance].actions copy];
    [_tableView reloadData];
}

- (void)_updateButtons {
    BOOL hasSelection = (_tableView.selectedRow >= 0);
    _runButton.enabled = hasSelection;
    _newWindowButton.enabled = hasSelection;
}

- (void)_doubleClick:(id)sender {
    [self _runInNewWindow:NO];
}

- (void)_runClicked:(id)sender {
    [self _runInNewWindow:NO];
}

- (void)_newWindowClicked:(id)sender {
    [self _runInNewWindow:YES];
}

- (void)_manageClicked:(id)sender {
    [_popover close];
    [_delegate bottomBarManageShortcutsClicked:_bottomBar];
}

- (void)_runInNewWindow:(BOOL)newWindow {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_actions.count) {
        return;
    }
    [_delegate bottomBar:_bottomBar runAction:_actions[row] inNewWindow:newWindow];
}

#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_actions.count;
}

#pragma mark NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    static NSString *const kID = @"ShortcutCell";
    NSTableCellView *cell = [tableView makeViewWithIdentifier:kID owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 276, 20)];
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.frame = NSMakeRect(4, 2, 268, 16);
        tf.autoresizingMask = NSViewWidthSizable;
        tf.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        [cell addSubview:tf];
        cell.textField = tf;
        cell.identifier = kID;
    }
    iTermAction *action = _actions[row];
    cell.textField.stringValue = (action.title.length > 0) ? action.title : @"Untitled";
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self _updateButtons];
}

@end

// Forward-declare private methods so the panel VC (defined after) can call them.
@interface iTermBottomBar (AppctlPrivate)
- (nullable NSDictionary *)_queryDaemonPayload:(NSDictionary *)payload;
- (void)_runAppctlCommand:(NSString *)command;
- (void)_fetchAppctlData;
@end

// Panel VC forward declaration
@interface iTermAppctlCommandPanelViewController : NSViewController
- (instancetype)initWithBar:(iTermBottomBar *)bar popover:(NSPopover *)popover;
@end

// ---------------------------------------------------------------------------
#pragma mark - iTermBottomBar
// ---------------------------------------------------------------------------

@implementation iTermBottomBar {
    NSSlider      *_transparencySlider;
    NSButton      *_floatButton;
    NSTextField   *_cpuLabel;
    NSTextField   *_ramLabel;
    NSTextField   *_diskLabel;
    NSTimer       *_statsTimer;
    NSButton      *_manageShortcutsButton;
    // appctl section
    NSButton      *_appctlButton;
    NSButton      *_appctlCommandsButton;
    BOOL           _appctlFetching;
    // Raw data for popover
    NSArray       *_vsWindows;
    NSInteger      _vsActiveIdx;
    NSArray       *_chSessions;
    NSArray       *_procs;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self _buildSubviews];
        [self _startStatsTimer];
    }
    return self;
}

- (void)dealloc {
    [_statsTimer invalidate];
}

// ---------------------------------------------------------------------------
#pragma mark - Layout
// ---------------------------------------------------------------------------

- (void)_buildSubviews {
    // Background is drawn in -drawRect: so it responds to dark/light mode changes.

    CGFloat x = kPadding;
    const CGFloat h = iTermBottomBarHeight - 2 * kControlInset;
    const CGFloat y = kControlInset;

    // --- Transparency label --------------------------------------------------
    NSTextField *transLabel = [self _makeLabelWithText:@"Transparency:"];
    transLabel.frame = NSMakeRect(x, y, 88, h);
    [self addSubview:transLabel];
    x += NSWidth(transLabel.frame) + 4;

    // --- Transparency slider -------------------------------------------------
    _transparencySlider = [[NSSlider alloc] initWithFrame:NSMakeRect(x, y, kSliderWidth, h)];
    _transparencySlider.minValue = 0.0;
    _transparencySlider.maxValue = 1.0;
    _transparencySlider.continuous = YES;
    _transparencySlider.target = self;
    _transparencySlider.action = @selector(_transparencyChanged:);
    _transparencySlider.toolTip = @"Session transparency (0 = opaque, 1 = transparent)";
    [self addSubview:_transparencySlider];
    x += kSliderWidth + kPadding * 2;

    // --- Float-on-top checkbox -----------------------------------------------
    _floatButton = [NSButton checkboxWithTitle:@"Float on top"
                                        target:self
                                        action:@selector(_floatToggled:)];
    [_floatButton sizeToFit];
    _floatButton.frame = NSMakeRect(x, y, NSWidth(_floatButton.frame), h);
    [self addSubview:_floatButton];
    x += NSWidth(_floatButton.frame) + kPadding * 2;

    // --- Separator -----------------------------------------------------------
    NSBox *sep = [[NSBox alloc] initWithFrame:NSMakeRect(x, 2, 1, iTermBottomBarHeight - 4)];
    sep.boxType = NSBoxSeparator;
    [self addSubview:sep];
    x += 1 + kPadding;

    // --- Stats labels --------------------------------------------------------
    _cpuLabel  = [self _makeStatLabelAt:x y:y];  x += 80;
    _ramLabel  = [self _makeStatLabelAt:x y:y];  x += 80;
    _diskLabel = [self _makeStatLabelAt:x y:y];  x += 76 + kPadding;

    // --- Separator before appctl section ------------------------------------
    NSBox *sep2 = [[NSBox alloc] initWithFrame:NSMakeRect(x, 2, 1, iTermBottomBarHeight - 4)];
    sep2.boxType = NSBoxSeparator;
    [self addSubview:sep2];
    x += 1 + kPadding;

    // --- appctl button (VS Code · Chrome · Procs) ----------------------------
    _appctlButton = [NSButton buttonWithTitle:@"appctl…"
                                       target:self
                                       action:@selector(_appctlClicked:)];
    _appctlButton.font = [NSFont monospacedDigitSystemFontOfSize:[NSFont smallSystemFontSize]
                                                          weight:NSFontWeightRegular];
    _appctlButton.bezelStyle = NSBezelStyleInline;
    _appctlButton.bordered = NO;
    _appctlButton.alignment = NSTextAlignmentLeft;
    _appctlButton.lineBreakMode = NSLineBreakByTruncatingTail;
    _appctlButton.toolTip = @"VS Code windows, Chrome sessions, background procs";
    _appctlButton.frame = NSMakeRect(x, y, 100 /* will be stretched in -layout */, h);
    [self addSubview:_appctlButton];

    // --- appctl Commands button (pinned right of appctl status) --------------
    _appctlCommandsButton = [NSButton buttonWithTitle:@"⚙ appctl"
                                               target:self
                                               action:@selector(_appctlCommandsClicked:)];
    _appctlCommandsButton.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    _appctlCommandsButton.bezelStyle = NSBezelStyleInline;
    _appctlCommandsButton.toolTip = @"All appctl commands";
    [_appctlCommandsButton sizeToFit];
    _appctlCommandsButton.autoresizingMask = NSViewMinXMargin;
    [self addSubview:_appctlCommandsButton];

    // --- Manage Shortcuts button (pinned to right edge) ----------------------
    _manageShortcutsButton = [NSButton buttonWithTitle:@"Manage Shortcuts"
                                                target:self
                                                action:@selector(_manageShortcutsClicked:)];
    _manageShortcutsButton.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    _manageShortcutsButton.bezelStyle = NSBezelStyleInline;
    _manageShortcutsButton.toolTip = @"Open keyboard shortcut settings";
    [_manageShortcutsButton sizeToFit];
    _manageShortcutsButton.autoresizingMask = NSViewMinXMargin;
    [self addSubview:_manageShortcutsButton];
    // Frame is set in -layout once bounds are known.
}

- (void)layout {
    [super layout];
    if (_manageShortcutsButton) {
        NSSize btnSize = _manageShortcutsButton.frame.size;
        CGFloat y = kControlInset;
        CGFloat h = iTermBottomBarHeight - 2 * kControlInset;
        _manageShortcutsButton.frame = NSMakeRect(NSWidth(self.bounds) - btnSize.width - kPadding,
                                                  y,
                                                  btnSize.width,
                                                  h);
    }
    // Position "⚙ appctl" commands button left of "Manage Shortcuts".
    if (_appctlCommandsButton && _manageShortcutsButton) {
        CGFloat y = kControlInset;
        CGFloat h = iTermBottomBarHeight - 2 * kControlInset;
        CGFloat bw = _appctlCommandsButton.frame.size.width + 4;
        CGFloat x  = NSMinX(_manageShortcutsButton.frame) - bw - kPadding;
        _appctlCommandsButton.frame = NSMakeRect(x, y, bw, h);
    }
    // Stretch the appctl status button to fill space left of the commands button.
    if (_appctlButton && _appctlCommandsButton) {
        CGFloat leftEdge  = NSMinX(_appctlButton.frame);
        CGFloat rightEdge = NSMinX(_appctlCommandsButton.frame) - kPadding;
        if (rightEdge > leftEdge + 20) {
            _appctlButton.frame = NSMakeRect(leftEdge,
                                             _appctlButton.frame.origin.y,
                                             rightEdge - leftEdge,
                                             _appctlButton.frame.size.height);
        }
    }
}

- (NSTextField *)_makeLabelWithText:(NSString *)text {
    NSTextField *tf = [NSTextField labelWithString:text];
    tf.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    tf.textColor = [NSColor secondaryLabelColor];
    return tf;
}

- (NSTextField *)_makeStatLabelAt:(CGFloat)x y:(CGFloat)y {
    NSTextField *tf = [NSTextField labelWithString:@"—"];
    tf.font = [NSFont monospacedDigitSystemFontOfSize:[NSFont smallSystemFontSize] weight:NSFontWeightRegular];
    tf.textColor = [NSColor secondaryLabelColor];
    tf.frame = NSMakeRect(x, y, 76, iTermBottomBarHeight - 2 * kControlInset);
    [self addSubview:tf];
    return tf;
}

// ---------------------------------------------------------------------------
#pragma mark - Public API
// ---------------------------------------------------------------------------

- (void)refresh {
    if ([_delegate respondsToSelector:@selector(bottomBarCurrentTransparency:)]) {
        _transparencySlider.doubleValue = [_delegate bottomBarCurrentTransparency:self];
    }
    if ([_delegate respondsToSelector:@selector(bottomBarIsFloatingOnTop:)]) {
        _floatButton.state = [_delegate bottomBarIsFloatingOnTop:self] ? NSControlStateValueOn
                                                                       : NSControlStateValueOff;
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Control actions
// ---------------------------------------------------------------------------

- (void)_transparencyChanged:(NSSlider *)sender {
    [_delegate bottomBar:self setTransparency:sender.doubleValue];
}

- (void)_floatToggled:(NSButton *)sender {
    [_delegate bottomBar:self setFloatOnTop:(sender.state == NSControlStateValueOn)];
}

- (void)_manageShortcutsClicked:(NSButton *)sender {
    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.contentViewController = [[iTermShortcutsPopoverViewController alloc]
                                        initWithDelegate:_delegate
                                               bottomBar:self
                                                 popover:popover];
    [popover showRelativeToRect:sender.bounds
                         ofView:sender
                  preferredEdge:NSRectEdgeMaxY];
}

// ---------------------------------------------------------------------------
#pragma mark - System stats
// ---------------------------------------------------------------------------

- (void)_startStatsTimer {
    [self _updateStats];
    _statsTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                   target:self
                                                 selector:@selector(_updateStats)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (void)_updateStats {
    _cpuLabel.stringValue  = [NSString stringWithFormat:@"CPU: %.0f%%", [self _cpuUsagePercent]];
    _ramLabel.stringValue  = [NSString stringWithFormat:@"RAM: %.0f%%", [self _ramUsagePercent]];
    _diskLabel.stringValue = [NSString stringWithFormat:@"Disk: %.0f%%", [self _diskUsagePercent]];
    [self _fetchAppctlData];
}

// ---------------------------------------------------------------------------
#pragma mark - appctl integration
// ---------------------------------------------------------------------------

- (void)_fetchAppctlData {
    if (_appctlFetching) return;
    _appctlFetching = YES;

    dispatch_group_t group = dispatch_group_create();
    __block NSString *vsText = nil;
    __block NSString *chText = nil;
    __block NSDictionary *vsResult = nil;
    __block NSDictionary *chResult = nil;
    __weak __typeof(self) weakSelf = self;

    dispatch_group_enter(group);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *r = [weakSelf _queryDaemonPayload:@{ @"target": @"vscode", @"command": @"windows" }];
        vsResult = r;
        vsText = [weakSelf _formatVSCode:r];
        dispatch_group_leave(group);
    });

    dispatch_group_enter(group);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *r = [weakSelf _queryDaemonPayload:@{ @"target": @"chrome", @"command": @"sessions" }];
        chResult = r;
        chText = [weakSelf _formatChrome:r];
        dispatch_group_leave(group);
    });

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        // Cache raw data for the popover
        if ([vsResult[@"ok"] boolValue]) {
            strongSelf->_vsWindows   = [vsResult[@"windows"] isKindOfClass:[NSArray class]] ? vsResult[@"windows"] : @[];
            strongSelf->_vsActiveIdx = [vsResult[@"active"] integerValue];
        }
        if ([chResult[@"ok"] boolValue]) {
            strongSelf->_chSessions = [chResult[@"sessions"] isKindOfClass:[NSArray class]] ? chResult[@"sessions"] : @[];
        }
        // Read procs
        NSString *procPath = [NSHomeDirectory() stringByAppendingPathComponent:@".appctl/procs/registry.json"];
        NSData *procData = [NSData dataWithContentsOfFile:procPath];
        if (procData) {
            id parsed = [NSJSONSerialization JSONObjectWithData:procData options:0 error:nil];
            if ([parsed isKindOfClass:[NSArray class]]) strongSelf->_procs = parsed;
        }
        NSString *procText = [strongSelf _readProcListText];
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        if (vsText.length)   [parts addObject:vsText];
        if (chText.length)   [parts addObject:chText];
        if (procText.length) [parts addObject:procText];
        [strongSelf->_appctlButton setTitle:(parts.count
            ? [parts componentsJoinedByString:@"    "]
            : @"appctl offline")];
        strongSelf->_appctlFetching = NO;
    });
}

/// Synchronously connects to /tmp/appctl.sock, sends payload, returns parsed response or nil.
- (nullable NSDictionary *)_queryDaemonPayload:(NSDictionary *)payload {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return nil;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, "/tmp/appctl.sock", sizeof(addr.sun_path));

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd); return nil;
    }
    struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) { close(fd); return nil; }
    NSMutableData *msg = [json mutableCopy];
    [msg appendBytes:"\n" length:1];
    write(fd, msg.bytes, msg.length);

    NSMutableData *buf = [NSMutableData data];
    char chunk[4096];
    ssize_t n;
    while ((n = read(fd, chunk, sizeof(chunk))) > 0) {
        [buf appendBytes:chunk length:n];
    }
    close(fd);
    if (!buf.length) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:buf options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

- (NSString *)_formatVSCode:(nullable NSDictionary *)result {
    if (![result[@"ok"] boolValue]) return nil;
    NSArray *windows = result[@"windows"];
    if (![windows isKindOfClass:[NSArray class]] || !windows.count) return nil;
    NSInteger activeIdx = [result[@"active"] integerValue];
    NSDictionary *active = (activeIdx < (NSInteger)windows.count) ? windows[activeIdx] : windows.firstObject;
    NSString *title = [active[@"title"] isKindOfClass:[NSString class]] ? active[@"title"] : @"?";
    NSString *name = title.pathComponents.lastObject ?: title;
    if (name.length > 16) name = [name substringToIndex:16];
    return [NSString stringWithFormat:@"VS %@(%ld)", name, (long)windows.count];
}

- (NSString *)_formatChrome:(nullable NSDictionary *)result {
    if (![result[@"ok"] boolValue]) return nil;
    NSArray *sessions = result[@"sessions"];
    if (![sessions isKindOfClass:[NSArray class]] || !sessions.count) return nil;
    NSDictionary *active = sessions.lastObject;
    NSString *profile = [active[@"profile"] isKindOfClass:[NSString class]] ? active[@"profile"] : @"?";
    if (profile.length > 12) profile = [profile substringToIndex:12];
    return [NSString stringWithFormat:@"CH %@(%ld)", profile, (long)sessions.count];
}

- (NSString *)_readProcListText {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".appctl/procs/registry.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    NSArray *procs = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![procs isKindOfClass:[NSArray class]] || !procs.count) return nil;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSDictionary *p in procs) {
        if (![p isKindOfClass:[NSDictionary class]]) continue;
        NSNumber *pid = p[@"pid"];
        NSString *name = [p[@"name"] isKindOfClass:[NSString class]] ? p[@"name"] : @"?";
        BOOL alive = [pid isKindOfClass:[NSNumber class]] && (kill(pid.intValue, 0) == 0);
        [parts addObject:[NSString stringWithFormat:@"%@%@", alive ? @"●" : @"○", name]];
    }
    return parts.count ? [parts componentsJoinedByString:@" "] : nil;
}

- (void)_appctlClicked:(NSButton *)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"appctl"];

    // --- VS Code windows ---------------------------------------------------
    [menu addItemWithTitle:@"VS Code Windows" action:nil keyEquivalent:@""];
    menu.itemArray.lastObject.enabled = NO;
    if (_vsWindows.count) {
        for (NSUInteger i = 0; i < _vsWindows.count; i++) {
            NSDictionary *win = _vsWindows[i];
            NSString *title = [win[@"title"] isKindOfClass:[NSString class]] ? win[@"title"] : @"?";
            NSString *label = [NSString stringWithFormat:@"%@  %@", (i == (NSUInteger)_vsActiveIdx ? @"▶" : @" "), title];
            NSMenuItem *item = [menu addItemWithTitle:label action:@selector(_focusVSCodeWindow:) keyEquivalent:@""];
            item.target = self;
            item.tag = (NSInteger)i;
        }
    } else {
        NSMenuItem *none = [menu addItemWithTitle:@"  (none)" action:nil keyEquivalent:@""];
        none.enabled = NO;
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Chrome sessions ---------------------------------------------------
    [menu addItemWithTitle:@"Chrome Sessions" action:nil keyEquivalent:@""];
    menu.itemArray.lastObject.enabled = NO;
    if (_chSessions.count) {
        for (NSDictionary *s in _chSessions) {
            NSString *profile = [s[@"profile"] isKindOfClass:[NSString class]] ? s[@"profile"] : @"?";
            BOOL active = [s[@"active"] boolValue];
            NSString *label = [NSString stringWithFormat:@"%@  %@", active ? @"▶" : @" ", profile];
            NSMenuItem *item = [menu addItemWithTitle:label action:@selector(_switchChromeSession:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = profile;
        }
    } else {
        NSMenuItem *none = [menu addItemWithTitle:@"  (none)" action:nil keyEquivalent:@""];
        none.enabled = NO;
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Background procs --------------------------------------------------
    [menu addItemWithTitle:@"Background Procs" action:nil keyEquivalent:@""];
    menu.itemArray.lastObject.enabled = NO;
    if (_procs.count) {
        for (NSDictionary *p in _procs) {
            if (![p isKindOfClass:[NSDictionary class]]) continue;
            NSNumber *pid = p[@"pid"];
            NSString *name = [p[@"name"] isKindOfClass:[NSString class]] ? p[@"name"] : @"?";
            NSString *cwd  = [p[@"cwd"]  isKindOfClass:[NSString class]] ? p[@"cwd"]  : @"";
            BOOL alive = [pid isKindOfClass:[NSNumber class]] && (kill(pid.intValue, 0) == 0);
            NSString *label = [NSString stringWithFormat:@"%@  %@  %@",
                               alive ? @"●" : @"○", name,
                               cwd.lastPathComponent ?: @""];
            NSMenuItem *item = [menu addItemWithTitle:label action:@selector(_openProcLogs:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = p;
            item.toolTip = [NSString stringWithFormat:@"Open live log for %@", name];
        }
    } else {
        NSMenuItem *none = [menu addItemWithTitle:@"  (none)" action:nil keyEquivalent:@""];
        none.enabled = NO;
    }

    [menu popUpMenuPositioningItem:menu.itemArray.firstObject
                        atLocation:NSMakePoint(0, NSHeight(sender.bounds))
                            inView:sender];
}

- (void)_focusVSCodeWindow:(NSMenuItem *)item {
    NSInteger idx = item.tag;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        // Tell the daemon which window is active
        NSString *focusCmd = [NSString stringWithFormat:@"appctl vscode focus %ld", (long)idx];
        NSTask *t = [[NSTask alloc] init];
        t.launchPath = @"/bin/zsh";
        t.arguments  = @[ @"-lc", focusCmd ];
        [t launch]; [t waitUntilExit];

        // Bring VS Code to the front
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray<NSRunningApplication *> *apps =
                [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.microsoft.VSCode"];
            [apps.firstObject activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            [self _fetchAppctlData];
        });
    });
}

- (void)_switchChromeSession:(NSMenuItem *)item {
    NSString *profile = item.representedObject;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *switchCmd = [NSString stringWithFormat:@"appctl chrome switch --profile \"%@\"", profile];
        NSTask *t = [[NSTask alloc] init];
        t.launchPath = @"/bin/zsh";
        t.arguments  = @[ @"-lc", switchCmd ];
        [t launch]; [t waitUntilExit];

        dispatch_async(dispatch_get_main_queue(), ^{
            // Activate the Chrome process for this profile (each profile is its own process)
            NSArray<NSRunningApplication *> *apps =
                [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.google.Chrome"];
            [apps.firstObject activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            [self _fetchAppctlData];
        });
    });
}

- (void)_openProcLogs:(NSMenuItem *)item {
    NSDictionary *proc = item.representedObject;
    NSString *logFile = [proc[@"logFile"] isKindOfClass:[NSString class]] ? proc[@"logFile"] : nil;
    NSString *name    = [proc[@"name"]    isKindOfClass:[NSString class]] ? proc[@"name"]    : @"proc";

    if (!logFile) {
        // Fallback: derive from id
        NSString *procId = [proc[@"id"] isKindOfClass:[NSString class]] ? proc[@"id"] : @"";
        logFile = [NSHomeDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@".appctl/procs/%@.log", procId]];
    }

    // Open a new iTerm2 window and tail the log
    NSString *escapedLog  = [logFile stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    NSString *escapedName = [name    stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    NSString *script = [NSString stringWithFormat:
        @"tell application \"iTerm2\"\n"
        @"    activate\n"
        @"    set newWin to (create window with default profile)\n"
        @"    tell current session of newWin\n"
        @"        set name to \"logs: %@\"\n"
        @"        write text \"tail -f '%@'\"\n"
        @"    end tell\n"
        @"end tell",
        escapedName, escapedLog];

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/osascript";
    task.arguments  = @[ @"-e", script ];
    [task launch];
}

- (void)_appctlCommandsClicked:(NSButton *)sender {
    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.contentViewController = [[iTermAppctlCommandPanelViewController alloc]
                                        initWithBar:self popover:popover];
    [popover showRelativeToRect:sender.bounds
                         ofView:sender
                  preferredEdge:NSRectEdgeMaxY];
}

- (void)_runAppctlCommand:(NSString *)command {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/bin/zsh";
        task.arguments  = @[ @"-lc", command ];
        [task launch];
        [task waitUntilExit];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self _fetchAppctlData];
        });
    });
}

- (double)_cpuUsagePercent {
    // Sum user + system ticks across all CPUs.
    natural_t cpuCount = 0;
    processor_info_array_t cpuInfo = NULL;
    mach_msg_type_number_t infoCount = 0;
    kern_return_t kr = host_processor_info(mach_host_self(),
                                           PROCESSOR_CPU_LOAD_INFO,
                                           &cpuCount,
                                           &cpuInfo,
                                           &infoCount);
    if (kr != KERN_SUCCESS) {
        return 0.0;
    }

    static uint64_t sPrevUser   = 0;
    static uint64_t sPrevSystem = 0;
    static uint64_t sPrevIdle   = 0;

    uint64_t user = 0, system = 0, idle = 0;
    for (natural_t i = 0; i < cpuCount; i++) {
        processor_cpu_load_info_t load = (processor_cpu_load_info_t)(cpuInfo + i * CPU_STATE_MAX);
        user   += load->cpu_ticks[CPU_STATE_USER]   + load->cpu_ticks[CPU_STATE_NICE];
        system += load->cpu_ticks[CPU_STATE_SYSTEM];
        idle   += load->cpu_ticks[CPU_STATE_IDLE];
    }
    vm_deallocate(mach_task_self(), (vm_address_t)cpuInfo, infoCount * sizeof(integer_t));

    uint64_t du = user   - sPrevUser;
    uint64_t ds = system - sPrevSystem;
    uint64_t di = idle   - sPrevIdle;
    uint64_t total = du + ds + di;

    sPrevUser   = user;
    sPrevSystem = system;
    sPrevIdle   = idle;

    if (total == 0) {
        return 0.0;
    }
    return 100.0 * (double)(du + ds) / (double)total;
}

- (double)_ramUsagePercent {
    vm_size_t pageSize;
    host_page_size(mach_host_self(), &pageSize);

    vm_statistics64_data_t vmStats;
    mach_msg_type_number_t infoCount = HOST_VM_INFO64_COUNT;
    kern_return_t kr = host_statistics64(mach_host_self(),
                                         HOST_VM_INFO64,
                                         (host_info64_t)&vmStats,
                                         &infoCount);
    if (kr != KERN_SUCCESS) {
        return 0.0;
    }

    uint64_t used = ((uint64_t)(vmStats.active_count +
                                vmStats.wire_count)) * pageSize;

    int mib[2] = { CTL_HW, HW_MEMSIZE };
    uint64_t totalMem = 0;
    size_t len = sizeof(totalMem);
    sysctl(mib, 2, &totalMem, &len, NULL, 0);

    if (totalMem == 0) {
        return 0.0;
    }
    return 100.0 * (double)used / (double)totalMem;
}

- (double)_diskUsagePercent {
    struct statvfs stat;
    if (statvfs("/", &stat) != 0) {
        return 0.0;
    }
    uint64_t total = (uint64_t)stat.f_blocks * stat.f_frsize;
    uint64_t avail = (uint64_t)stat.f_bfree  * stat.f_frsize;
    if (total == 0) {
        return 0.0;
    }
    return 100.0 * (double)(total - avail) / (double)total;
}

// ---------------------------------------------------------------------------
#pragma mark - Drawing
// ---------------------------------------------------------------------------

- (void)drawRect:(NSRect)dirtyRect {
    // Fill the background using a semantic color so dark/light mode is handled automatically.
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(self.bounds);
    // Top separator line
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(0, NSMaxY(self.bounds) - 1, NSWidth(self.bounds), 1));
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

@end

// ============================================================================
#pragma mark - iTermAppctlCommandPanelViewController
// ============================================================================

static char kBtnPayloadKey;
static inline void setBtnPayload(NSButton *btn, id obj) {
    objc_setAssociatedObject(btn, &kBtnPayloadKey, obj, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static inline id getBtnPayload(NSButton *btn) {
    return objc_getAssociatedObject(btn, &kBtnPayloadKey);
}

// Flipped NSView so rows can be stacked top-to-bottom naturally (y=0 at top).
@interface iTermAppctlFlippedView : NSView
@end
@implementation iTermAppctlFlippedView
- (BOOL)isFlipped { return YES; }
@end

static const CGFloat kPanW   = 440;
static const CGFloat kPanH   = 460;
static const CGFloat kPanPad = 10;
static const CGFloat kPRowH  = 28;
static const CGFloat kPBtnH  = 22;

@implementation iTermAppctlCommandPanelViewController {
    __weak iTermBottomBar *_bar;
    __weak NSPopover      *_popover;
    NSSegmentedControl    *_seg;
    NSScrollView          *_scroll;
    // Cached data
    NSArray   *_vsWindows;
    NSInteger  _vsActiveIdx;
    NSArray   *_chSessions;
    NSArray   *_chProfiles;
    NSArray   *_vsHistory;
    NSArray   *_chHistory;
    NSArray   *_procs;
    // Chrome URL input
    NSTextField *_urlField;
    // New proc form fields
    NSTextField *_procNameField;
    NSTextField *_procCwdField;
    NSTextField *_procCmdField;
    BOOL         _procFormVisible;
}

- (instancetype)initWithBar:(iTermBottomBar *)bar popover:(NSPopover *)popover {
    self = [super initWithNibName:nil bundle:nil];
    if (self) { _bar = bar; _popover = popover; }
    return self;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanW, kPanH)];
    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _seg = [[NSSegmentedControl alloc] initWithFrame:
            NSMakeRect(kPanPad, kPanH - kPRowH - kPanPad, kPanW - 2*kPanPad, kPRowH)];
    _seg.segmentCount = 3;
    [_seg setLabel:@"VS Code" forSegment:0];
    [_seg setLabel:@"Chrome"  forSegment:1];
    [_seg setLabel:@"Procs"   forSegment:2];
    _seg.selectedSegment = 0;
    _seg.target = self;
    _seg.action = @selector(_segChanged:);
    [self.view addSubview:_seg];

    CGFloat scrollH = kPanH - kPRowH - 3 * kPanPad;
    _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kPanW, scrollH)];
    _scroll.hasVerticalScroller = YES;
    _scroll.autohidesScrollers  = YES;
    _scroll.borderType          = NSNoBorder;
    [self.view addSubview:_scroll];

    [self _fetchAndReload];
}

- (void)_segChanged:(id)sender { [self _rebuildContent]; }

- (void)_fetchAndReload {
    _scroll.documentView = [self _loadingView];
    dispatch_group_t g = dispatch_group_create();
    __weak __typeof(self) ws = self;
    iTermBottomBar *capturedBar = _bar;  // strong capture for background blocks
    __block NSDictionary *vsr = nil, *chr = nil, *cpr = nil;

    dispatch_group_enter(g);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        vsr = [capturedBar _queryDaemonPayload:@{@"target":@"vscode", @"command":@"windows"}];
        dispatch_group_leave(g);
    });
    dispatch_group_enter(g);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        chr = [capturedBar _queryDaemonPayload:@{@"target":@"chrome", @"command":@"sessions"}];
        dispatch_group_leave(g);
    });
    dispatch_group_enter(g);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        cpr = [capturedBar _queryDaemonPayload:@{@"target":@"chrome", @"command":@"list-profiles"}];
        dispatch_group_leave(g);
    });

    dispatch_group_notify(g, dispatch_get_main_queue(), ^{
        __strong __typeof(self) ss = ws; if (!ss) return;
        ss->_vsWindows   = [vsr[@"ok"] boolValue] && [vsr[@"windows"]  isKindOfClass:[NSArray class]] ? vsr[@"windows"]  : @[];
        ss->_vsActiveIdx = [vsr[@"active"] integerValue];
        ss->_chSessions  = [chr[@"ok"] boolValue] && [chr[@"sessions"] isKindOfClass:[NSArray class]] ? chr[@"sessions"] : @[];
        ss->_chProfiles  = [cpr[@"ok"] boolValue] && [cpr[@"profiles"] isKindOfClass:[NSArray class]] ? cpr[@"profiles"] : @[];

        NSString *rp = [NSHomeDirectory() stringByAppendingPathComponent:@".appctl/procs/registry.json"];
        NSData *rd = [NSData dataWithContentsOfFile:rp];
        id parsed = rd ? [NSJSONSerialization JSONObjectWithData:rd options:0 error:nil] : nil;
        ss->_procs = [parsed isKindOfClass:[NSArray class]] ? parsed : @[];

        // Load appctl history
        NSString *hp = [NSHomeDirectory() stringByAppendingPathComponent:@".appctl/history.json"];
        NSData *hd = [NSData dataWithContentsOfFile:hp];
        id hist = hd ? [NSJSONSerialization JSONObjectWithData:hd options:0 error:nil] : nil;
        if ([hist isKindOfClass:[NSDictionary class]]) {
            ss->_vsHistory = [hist[@"projects"] isKindOfClass:[NSArray class]] ? hist[@"projects"] : @[];
            ss->_chHistory = [hist[@"profiles"] isKindOfClass:[NSArray class]] ? hist[@"profiles"] : @[];
        }

        [ss _rebuildContent];
    });
}

- (NSView *)_loadingView {
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanW, 50)];
    NSTextField *l = [NSTextField labelWithString:@"Loading…"];
    l.alignment = NSTextAlignmentCenter;
    l.frame = NSMakeRect(0, 16, kPanW, 18);
    [v addSubview:l];
    return v;
}

- (void)_rebuildContent {
    NSView *content;
    switch (_seg.selectedSegment) {
        case 0:  content = [self _vsCodeView];  break;
        case 1:  content = [self _chromeView];  break;
        default: content = [self _procsView];   break;
    }
    CGFloat minH = _scroll.frame.size.height;
    if (NSHeight(content.frame) < minH) {
        NSRect f = content.frame; f.size.height = minH; content.frame = f;
    }
    _scroll.documentView = content;
    [content scrollPoint:NSMakePoint(0, 0)];  // y=0 = top in flipped view
}

// ---------------------------------------------------------------------------
#pragma mark VS Code tab
// ---------------------------------------------------------------------------

- (NSView *)_vsCodeView {
    NSMutableArray<NSView *> *rows = [NSMutableArray array];

    // Active windows at top
    [rows addObject:[self _sectionHeader:@"OPEN WINDOWS"]];
    if (_vsWindows.count == 0) {
        [rows addObject:[self _labelRow:@"No VS Code windows open"]];
    } else {
        for (NSUInteger i = 0; i < _vsWindows.count; i++) {
            NSDictionary *win = _vsWindows[i];
            NSString *title = [win[@"title"] isKindOfClass:[NSString class]] ? win[@"title"] : @"?";
            NSString *icon  = (i == (NSUInteger)_vsActiveIdx) ? @"▶ " : @"   ";
            NSButton *focusBtn = [self _btn:@"Focus" sel:@selector(_vsFocusWindow:)];
            focusBtn.tag = (NSInteger)i;
            [rows addObject:[self _textRow:[icon stringByAppendingString:title] btns:@[focusBtn]]];
        }
    }

    // History
    [rows addObject:[self _sep]];
    [rows addObject:[self _sectionHeader:@"RECENT PROJECTS"]];
    if (_vsHistory.count == 0) {
        [rows addObject:[self _labelRow:@"No recent projects"]];
    } else {
        for (id entry in _vsHistory) {
            NSString *path = [entry isKindOfClass:[NSString class]] ? entry
                           : ([entry isKindOfClass:[NSDictionary class]] ? entry[@"path"] : nil);
            if (!path) continue;
            NSString *label = path.lastPathComponent.length ? path.lastPathComponent : path;
            NSButton *openBtn = [self _btn:@"Open" sel:@selector(_vsHistoryOpen:)];
            setBtnPayload(openBtn, path);
            NSView *row = [self _textRow:label btns:@[openBtn]];
            row.toolTip = path;
            [rows addObject:row];
        }
    }

    // Actions at bottom
    [rows addObject:[self _sep]];
    NSView *actRow = [self _blankRow];
    NSButton *openBtn   = [self _btn:@"Open Project…" sel:@selector(_vsOpenProject:)];
    NSButton *newWinBtn = [self _btn:@"New Window…"   sel:@selector(_vsNewWindow:)];
    NSButton *stopBtn   = [self _btn:@"Stop VS Code"  sel:@selector(_vsStop:)];
    [self _packBtns:@[openBtn, newWinBtn, stopBtn] into:actRow leftAligned:YES];
    [rows addObject:actRow];

    return [self _stack:rows];
}

- (void)_vsOpenProject:(id)sender {
    [_popover close];
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.canChooseFiles = NO; p.canChooseDirectories = YES;
    p.title = @"Open Project in VS Code";
    [p beginWithCompletionHandler:^(NSModalResponse r) {
        if (r == NSModalResponseOK) {
            NSString *path = [p.URL.path stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
            [self->_bar _runAppctlCommand:[NSString stringWithFormat:@"appctl vscode new-window \"%@\"", path]];
        }
    }];
}

- (void)_vsNewWindow:(id)sender {
    [_popover close];
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.canChooseFiles = NO; p.canChooseDirectories = YES;
    p.title = @"Open New VS Code Window";
    [p beginWithCompletionHandler:^(NSModalResponse r) {
        if (r == NSModalResponseOK) {
            NSString *path = [p.URL.path stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
            [self->_bar _runAppctlCommand:[NSString stringWithFormat:@"appctl vscode new-window \"%@\"", path]];
        }
    }];
}

- (void)_vsHistoryOpen:(NSButton *)sender {
    NSString *path = getBtnPayload(sender);
    if (!path) return;
    NSString *ePath = [path stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    [_bar _runAppctlCommand:[NSString stringWithFormat:@"appctl vscode new-window \"%@\"", ePath]];
    NSArray<NSRunningApplication *> *apps =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.microsoft.VSCode"];
    [apps.firstObject activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    [_popover close];
}

- (void)_vsStop:(id)sender {
    [_bar _runAppctlCommand:@"appctl vscode stop"];
    [_popover close];
}

- (void)_vsFocusWindow:(NSButton *)sender {
    [_bar _runAppctlCommand:[NSString stringWithFormat:@"appctl vscode focus %ld", (long)sender.tag]];
    NSArray<NSRunningApplication *> *apps =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.microsoft.VSCode"];
    [apps.firstObject activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    [_popover close];
}

// ---------------------------------------------------------------------------
#pragma mark Chrome tab
// ---------------------------------------------------------------------------

- (NSView *)_chromeView {
    NSMutableArray<NSView *> *rows = [NSMutableArray array];

    // Build lookup: profile directory name (id) → "Profile N - email" or "Profile N - displayName"
    NSMutableDictionary<NSString *, NSString *> *profileDisplayNames = [NSMutableDictionary dictionary];
    for (NSDictionary *p in _chProfiles) {
        NSString *pid = [p[@"id"] isKindOfClass:[NSString class]] ? p[@"id"] : nil;
        NSString *pname = [p[@"name"] isKindOfClass:[NSString class]] ? p[@"name"] : nil;
        NSString *pemail = [p[@"email"] isKindOfClass:[NSString class]] ? p[@"email"] : nil;
        if (pid) {
            NSString *suffix = pemail ?: pname;
            profileDisplayNames[pid] = suffix ? [NSString stringWithFormat:@"%@ - %@", pid, suffix] : pid;
        }
    }

    // Active sessions at top
    [rows addObject:[self _sectionHeader:@"ACTIVE SESSIONS"]];
    if (_chSessions.count == 0) {
        [rows addObject:[self _labelRow:@"No Chrome sessions active"]];
    } else {
        for (NSDictionary *s in _chSessions) {
            NSString *profile = [s[@"profile"] isKindOfClass:[NSString class]] ? s[@"profile"] : @"?";
            BOOL active = [s[@"active"] boolValue];
            NSString *displayName = profileDisplayNames[profile] ?: profile;
            NSString *label = [NSString stringWithFormat:@"%@ %@", active ? @"▶" : @"   ", displayName];
            NSButton *switchBtn = [self _btn:@"Switch" sel:@selector(_chromeSwitchSession:)];
            NSButton *stopBtn   = [self _btn:@"Stop"   sel:@selector(_chromeStopSession:)];
            setBtnPayload(switchBtn, profile);
            setBtnPayload(stopBtn, profile);
            [rows addObject:[self _textRow:label btns:@[switchBtn, stopBtn]]];
        }
    }

    // History
    [rows addObject:[self _sep]];
    [rows addObject:[self _sectionHeader:@"RECENT PROFILES"]];
    if (_chHistory.count == 0) {
        [rows addObject:[self _labelRow:@"No recent profiles"]];
    } else {
        for (id entry in _chHistory) {
            NSString *name = [entry isKindOfClass:[NSString class]] ? entry
                           : ([entry isKindOfClass:[NSDictionary class]]
                              ? (entry[@"name"] ?: entry[@"profile"]) : nil);
            if (!name) continue;
            NSString *displayName = profileDisplayNames[name] ?: name;
            NSButton *launchBtn = [self _btn:@"Launch" sel:@selector(_chHistoryLaunch:)];
            setBtnPayload(launchBtn, name);
            [rows addObject:[self _textRow:displayName btns:@[launchBtn]]];
        }
    }

    // Actions at bottom
    [rows addObject:[self _sep]];
    NSView *urlRow = [self _blankRow];
    _urlField = [NSTextField textFieldWithString:@""];
    _urlField.placeholderString = @"https://";
    _urlField.frame = NSMakeRect(kPanPad, (kPRowH - 22)/2, kPanW - 2*kPanPad - 88, 22);
    [urlRow addSubview:_urlField];
    NSButton *openUrlBtn = [self _btn:@"Open URL" sel:@selector(_chromeOpenURL:)];
    openUrlBtn.frame = NSMakeRect(kPanW - kPanPad - 84, (kPRowH - kPBtnH)/2, 84, kPBtnH);
    [urlRow addSubview:openUrlBtn];
    [rows addObject:urlRow];

    NSView *profRow = [self _blankRow];
    NSButton *launchBtn  = [self _btn:@"Launch Profile…" sel:@selector(_chromeLaunchProfile:)];
    NSButton *stopAllBtn = [self _btn:@"Stop All"        sel:@selector(_chromeStopAll:)];
    [self _packBtns:@[launchBtn, stopAllBtn] into:profRow leftAligned:YES];
    [rows addObject:profRow];

    return [self _stack:rows];
}

- (void)_chHistoryLaunch:(NSButton *)sender {
    NSString *name = getBtnPayload(sender);
    if (!name) return;
    NSString *eName = [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    [_bar _runAppctlCommand:[NSString stringWithFormat:@"appctl chrome launch --profile \"%@\"", eName]];
    NSArray<NSRunningApplication *> *apps =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.google.Chrome"];
    [apps.firstObject activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    [_popover close];
}

- (void)_chromeOpenURL:(id)sender {
    NSString *url = _urlField.stringValue;
    if (!url.length) return;
    NSString *escaped = [url stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    [_bar _runAppctlCommand:[NSString stringWithFormat:@"appctl chrome open \"%@\"", escaped]];
    NSArray<NSRunningApplication *> *apps =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.google.Chrome"];
    [apps.firstObject activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    [_popover close];
}

- (void)_chromeLaunchProfile:(NSButton *)sender {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSDictionary *p in _chProfiles) {
        NSString *n = [p[@"name"] isKindOfClass:[NSString class]] ? p[@"name"] : nil;
        if (n) [names addObject:n];
    }
    if (!names.count) {
        for (NSDictionary *s in _chSessions) {
            NSString *n = s[@"profile"];
            if (n && ![names containsObject:n]) [names addObject:n];
        }
    }
    if (!names.count) [names addObject:@"Default"];

    NSMenu *menu = [[NSMenu alloc] init];
    for (NSString *name in names) {
        NSMenuItem *item = [menu addItemWithTitle:name
                                           action:@selector(_chromeLaunchProfileItem:)
                                    keyEquivalent:@""];
        item.target = self;
        item.representedObject = name;
    }
    [menu popUpMenuPositioningItem:menu.itemArray.firstObject
                        atLocation:NSMakePoint(0, NSHeight(sender.bounds))
                            inView:sender];
}

- (void)_chromeLaunchProfileItem:(NSMenuItem *)item {
    NSString *p = [item.representedObject stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    [_bar _runAppctlCommand:[NSString stringWithFormat:@"appctl chrome launch --profile \"%@\"", p]];
    [_popover close];
}

- (void)_chromeStopAll:(id)sender {
    [_bar _runAppctlCommand:@"appctl chrome stop --all"];
    [_popover close];
}

- (void)_chromeSwitchSession:(NSButton *)sender {
    NSString *p = [(NSString *)getBtnPayload(sender)
                   stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    [_bar _runAppctlCommand:[NSString stringWithFormat:@"appctl chrome switch --profile \"%@\"", p]];
    NSArray<NSRunningApplication *> *apps =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.google.Chrome"];
    [apps.firstObject activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    [_popover close];
}

- (void)_chromeStopSession:(NSButton *)sender {
    NSString *p = [(NSString *)getBtnPayload(sender)
                   stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    [_bar _runAppctlCommand:[NSString stringWithFormat:@"appctl chrome stop --profile \"%@\"", p]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self _fetchAndReload];
    });
}

// ---------------------------------------------------------------------------
#pragma mark Procs tab
// ---------------------------------------------------------------------------

- (NSView *)_procsView {
    NSMutableArray<NSView *> *rows = [NSMutableArray array];

    // "New Process" toggle
    NSView *newRow = [self _blankRow];
    NSButton *newBtn = [self _btn:(_procFormVisible ? @"▾ New Process" : @"▸ New Process")
                              sel:@selector(_procToggleForm:)];
    [self _packBtns:@[newBtn] into:newRow leftAligned:YES];
    [rows addObject:newRow];

    if (_procFormVisible) {
        // Name
        NSTextField *nameField = nil;
        [rows addObject:[self _fieldRow:@"Name:"    placeholder:@"backend"      outField:&nameField]];
        _procNameField = nameField;
        // CWD + Browse
        NSView *cwdRow = [self _blankRow];
        NSTextField *cwdLbl = [NSTextField labelWithString:@"CWD:"];
        cwdLbl.frame = NSMakeRect(kPanPad, (kPRowH-16)/2, 40, 16);
        _procCwdField = [NSTextField textFieldWithString:@""];
        _procCwdField.placeholderString = @"/path/to/project";
        _procCwdField.frame = NSMakeRect(kPanPad+44, (kPRowH-22)/2, kPanW-2*kPanPad-44-66, 22);
        NSButton *browseBtn = [self _btn:@"Browse…" sel:@selector(_procBrowse:)];
        browseBtn.frame = NSMakeRect(kPanW-kPanPad-62, (kPRowH-kPBtnH)/2, 62, kPBtnH);
        [cwdRow addSubview:cwdLbl]; [cwdRow addSubview:_procCwdField]; [cwdRow addSubview:browseBtn];
        [rows addObject:cwdRow];
        // Command
        NSTextField *cmdField = nil;
        [rows addObject:[self _fieldRow:@"Command:" placeholder:@"npm run dev"  outField:&cmdField]];
        _procCmdField = cmdField;
        // Run button
        NSView *runRow = [self _blankRow];
        NSButton *runBtn = [self _btn:@"▶ Run Process" sel:@selector(_procRun:)];
        [self _packBtns:@[runBtn] into:runRow leftAligned:YES];
        [rows addObject:runRow];
    }

    [rows addObject:[self _sep]];

    if (_procs.count == 0) {
        [rows addObject:[self _labelRow:@"No background processes"]];
    } else {
        for (NSDictionary *p in _procs) {
            if (![p isKindOfClass:[NSDictionary class]]) continue;
            NSNumber *pid  = p[@"pid"];
            NSString *name = [p[@"name"] isKindOfClass:[NSString class]] ? p[@"name"] : @"?";
            NSString *cwd  = [p[@"cwd"]  isKindOfClass:[NSString class]] ? p[@"cwd"]  : @"";
            BOOL alive = [pid isKindOfClass:[NSNumber class]] && (kill(pid.intValue, 0) == 0);
            NSString *label = [NSString stringWithFormat:@"%@ %@  %@",
                               alive ? @"●" : @"○", name, cwd.lastPathComponent ?: @""];
            NSButton *logsBtn   = [self _btn:@"Logs"  sel:@selector(_procLogs:)];
            NSButton *stopBtn   = [self _btn:@"Stop"  sel:@selector(_procStop:)];
            NSButton *removeBtn = [self _btn:@"✕"     sel:@selector(_procRemove:)];
            stopBtn.enabled = alive;
            setBtnPayload(logsBtn, p); setBtnPayload(stopBtn, p); setBtnPayload(removeBtn, p);
            [rows addObject:[self _textRow:label btns:@[logsBtn, stopBtn, removeBtn]]];
        }
    }
    return [self _stack:rows];
}

- (void)_procToggleForm:(id)sender {
    _procFormVisible = !_procFormVisible;
    [self _rebuildContent];
}

- (void)_procBrowse:(id)sender {
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.canChooseFiles = NO; p.canChooseDirectories = YES;
    p.title = @"Choose Working Directory";
    [p beginWithCompletionHandler:^(NSModalResponse r) {
        if (r == NSModalResponseOK) self->_procCwdField.stringValue = p.URL.path;
    }];
}

- (void)_procRun:(id)sender {
    NSString *name = _procNameField.stringValue;
    NSString *cwd  = _procCwdField.stringValue;
    NSString *cmd  = _procCmdField.stringValue;
    if (!name.length || !cwd.length || !cmd.length) return;

    NSString *eName = [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *eCwd  = [cwd  stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *eCmd  = [cmd  stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    [_bar _runAppctlCommand:
        [NSString stringWithFormat:@"appctl proc run --name \"%@\" --cwd \"%@\" %@", eName, eCwd, eCmd]];
    _procFormVisible = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self _fetchAndReload];
    });
}

- (void)_procLogs:(NSButton *)sender {
    NSDictionary *proc = getBtnPayload(sender);
    NSString *logFile = [proc[@"logFile"] isKindOfClass:[NSString class]] ? proc[@"logFile"] : nil;
    NSString *name    = [proc[@"name"]    isKindOfClass:[NSString class]] ? proc[@"name"]    : @"proc";
    if (!logFile) {
        NSString *pid = [proc[@"id"] isKindOfClass:[NSString class]] ? proc[@"id"] : @"";
        logFile = [NSHomeDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@".appctl/procs/%@.log", pid]];
    }
    NSString *eLog  = [logFile stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    NSString *eName = [name    stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    NSString *script = [NSString stringWithFormat:
        @"tell application \"iTerm2\"\n"
        @"    activate\n"
        @"    set w to (create window with default profile)\n"
        @"    tell current session of w\n"
        @"        write text \"tail -n 200 -f '%@'\"\n"
        @"    end tell\n"
        @"end tell", eLog];
    (void)eName;
    NSTask *t = [[NSTask alloc] init];
    t.launchPath = @"/usr/bin/osascript";
    t.arguments  = @[ @"-e", script ];
    [t launch];
    [_popover close];
}

- (void)_procStop:(NSButton *)sender {
    NSDictionary *proc = getBtnPayload(sender);
    NSString *name = [proc[@"name"] isKindOfClass:[NSString class]] ? proc[@"name"] : nil;
    if (!name) return;
    NSString *eName = [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    [_bar _runAppctlCommand:[NSString stringWithFormat:@"appctl proc stop \"%@\"", eName]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self _fetchAndReload];
    });
}

- (void)_procRemove:(NSButton *)sender {
    NSDictionary *proc = getBtnPayload(sender);
    NSString *name = [proc[@"name"] isKindOfClass:[NSString class]] ? proc[@"name"] : nil;
    if (!name) return;
    NSString *eName = [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    [_bar _runAppctlCommand:[NSString stringWithFormat:@"appctl proc remove \"%@\"", eName]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self _fetchAndReload];
    });
}

// ---------------------------------------------------------------------------
#pragma mark Layout helpers
// ---------------------------------------------------------------------------

- (NSView *)_blankRow {
    return [[iTermAppctlFlippedView alloc] initWithFrame:NSMakeRect(0, 0, kPanW, kPRowH)];
}

- (NSButton *)_btn:(NSString *)title sel:(SEL)sel {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:sel];
    b.bezelStyle = NSBezelStyleRounded;
    b.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    [b sizeToFit];
    NSRect f = b.frame; f.size.width += 8; f.size.height = kPBtnH; b.frame = f;
    return b;
}

- (void)_packBtns:(NSArray<NSButton *> *)btns into:(NSView *)view leftAligned:(BOOL)left {
    CGFloat x = left ? kPanPad : (kPanW - kPanPad);
    if (!left) {
        for (NSButton *b in btns.reverseObjectEnumerator) {
            x -= NSWidth(b.frame);
            b.frame = NSMakeRect(x, (kPRowH - kPBtnH)/2, NSWidth(b.frame), kPBtnH);
            [view addSubview:b];
            x -= 6;
        }
    } else {
        for (NSButton *b in btns) {
            b.frame = NSMakeRect(x, (kPRowH - kPBtnH)/2, NSWidth(b.frame), kPBtnH);
            [view addSubview:b];
            x += NSWidth(b.frame) + 6;
        }
    }
}

- (NSView *)_textRow:(NSString *)text btns:(NSArray<NSButton *> *)btns {
    NSView *row = [self _blankRow];
    CGFloat bx = kPanW - kPanPad;
    for (NSButton *b in btns.reverseObjectEnumerator) {
        bx -= NSWidth(b.frame);
        b.frame = NSMakeRect(bx, (kPRowH - kPBtnH)/2, NSWidth(b.frame), kPBtnH);
        [row addSubview:b];
        bx -= 4;
    }
    NSTextField *lbl = [NSTextField labelWithString:text];
    lbl.font = [NSFont monospacedSystemFontOfSize:[NSFont smallSystemFontSize] weight:NSFontWeightRegular];
    lbl.lineBreakMode = NSLineBreakByTruncatingMiddle;
    lbl.frame = NSMakeRect(kPanPad, (kPRowH - 16)/2, bx - kPanPad - 4, 16);
    [row addSubview:lbl];
    return row;
}

- (NSView *)_labelRow:(NSString *)text {
    NSView *row = [self _blankRow];
    NSTextField *lbl = [NSTextField labelWithString:text];
    lbl.textColor = [NSColor secondaryLabelColor];
    lbl.frame = NSMakeRect(kPanPad, (kPRowH - 16)/2, kPanW - 2*kPanPad, 16);
    [row addSubview:lbl];
    return row;
}

- (NSView *)_fieldRow:(NSString *)label placeholder:(NSString *)ph outField:(NSTextField **)outField {
    NSView *row = [self _blankRow];
    NSTextField *lbl = [NSTextField labelWithString:label];
    lbl.alignment = NSTextAlignmentRight;
    lbl.frame = NSMakeRect(kPanPad, (kPRowH - 16)/2, 60, 16);
    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.placeholderString = ph;
    field.frame = NSMakeRect(kPanPad + 64, (kPRowH - 22)/2, kPanW - 2*kPanPad - 64, 22);
    *outField = field;
    [row addSubview:lbl]; [row addSubview:field];
    return row;
}

- (NSView *)_sep {
    NSView *wrapper = [[iTermAppctlFlippedView alloc] initWithFrame:NSMakeRect(0, 0, kPanW, 10)];
    NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(kPanPad, 4, kPanW - 2*kPanPad, 1)];
    box.boxType = NSBoxSeparator;
    [wrapper addSubview:box];
    return wrapper;
}

- (NSView *)_sectionHeader:(NSString *)title {
    NSView *row = [[iTermAppctlFlippedView alloc] initWithFrame:NSMakeRect(0, 0, kPanW, 22)];
    NSTextField *lbl = [NSTextField labelWithString:title];
    lbl.font = [NSFont boldSystemFontOfSize:9];
    lbl.textColor = [NSColor tertiaryLabelColor];
    lbl.frame = NSMakeRect(kPanPad, 4, kPanW - 2*kPanPad, 14);
    [row addSubview:lbl];
    return row;
}

// Stack rows top-to-bottom using a flipped view (y=0 at top).
- (NSView *)_stack:(NSArray<NSView *> *)rows {
    CGFloat total = 2 * kPanPad;
    for (NSView *r in rows) total += NSHeight(r.frame);

    iTermAppctlFlippedView *c = [[iTermAppctlFlippedView alloc]
                                  initWithFrame:NSMakeRect(0, 0, kPanW, total)];
    CGFloat y = kPanPad;
    for (NSView *r in rows) {
        r.frame = NSMakeRect(0, y, kPanW, NSHeight(r.frame));
        [c addSubview:r];
        y += NSHeight(r.frame);
    }
    return c;
}

@end
