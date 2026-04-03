//
//  iTermOpenQuicklyView.m
//  iTerm
//
//  Created by George Nachman on 7/13/14.
//
//

#import "iTermOpenQuicklyView.h"
#import "NSView+iTerm.h"
#import "NSColor+iTerm.h"

@implementation iTermOpenQuicklyView {
    NSView *_backgroundEffectView;
    NSView *_glassContentView;
    NSView *_container;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)awakeFromNib {
    // Flip subviews
    NSArray *subviews = [self subviews];
    CGFloat height = self.bounds.size.height;
    for (NSView *view in subviews) {
        NSRect frame = view.frame;
        frame.origin.y = height - NSMaxY(frame);
        view.frame = frame;
    }

    _container = [[NSView alloc] initWithFrame:self.bounds];
    [self insertSubview:_container atIndex:0];

    {
        NSVisualEffectView *visual = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
        visual.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        visual.material = NSVisualEffectMaterialMenu;
        visual.state = NSVisualEffectStateActive;
        _backgroundEffectView = visual;
        [_container addSubview:_backgroundEffectView];
    }

    // Even though this is set in IB, we have to set it manually.
    self.autoresizesSubviews = NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    return;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    _container.frame = self.bounds;
    _backgroundEffectView.frame = _container.bounds;
    _glassContentView.frame = _backgroundEffectView.bounds;
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
    [super resizeWithOldSuperviewSize:oldSize];
    _container.frame = self.bounds;
    _backgroundEffectView.frame = _container.bounds;
    _glassContentView.frame = _backgroundEffectView.bounds;
}

@end
