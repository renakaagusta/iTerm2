//
//  iTermBottomBar.m
//  iTerm2
//

#import "iTermBottomBar.h"

#include <mach/mach.h>
#include <sys/mount.h>
#include <sys/statvfs.h>
#include <sys/sysctl.h>

const CGFloat iTermBottomBarHeight = 28.0;

// Horizontal padding inside the bar.
static const CGFloat kPadding = 8.0;
// Vertical inset so controls sit centred in the bar.
static const CGFloat kControlInset = 4.0;
// Width of the transparency slider.
static const CGFloat kSliderWidth = 100.0;

@implementation iTermBottomBar {
    NSSlider      *_transparencySlider;
    NSButton      *_floatButton;
    NSTextField   *_cpuLabel;
    NSTextField   *_ramLabel;
    NSTextField   *_diskLabel;
    NSTimer       *_statsTimer;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
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
    // Background – matches the window's title-bar / tab-bar feel.
    self.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;

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
    _diskLabel = [self _makeStatLabelAt:x y:y];
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
    // Top separator line
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(0, NSMaxY(self.bounds) - 1, NSWidth(self.bounds), 1));
}

@end
