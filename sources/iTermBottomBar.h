//
//  iTermBottomBar.h
//  iTerm2
//
//  A slim toolbar at the bottom of each terminal window with:
//    • Transparency slider
//    • Float-on-top toggle
//    • Live CPU / RAM / Disk usage labels
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermAction;
@class iTermBottomBar;

@protocol iTermBottomBarDelegate <NSObject>

/// Returns the current transparency value (0 = opaque, 1 = fully transparent).
- (CGFloat)bottomBarCurrentTransparency:(iTermBottomBar *)sender;

/// Called when the user moves the transparency slider.
- (void)bottomBar:(iTermBottomBar *)sender setTransparency:(CGFloat)transparency;

/// Returns YES if the window is currently floating on top.
- (BOOL)bottomBarIsFloatingOnTop:(iTermBottomBar *)sender;

/// Called when the user toggles the float-on-top button.
- (void)bottomBar:(iTermBottomBar *)sender setFloatOnTop:(BOOL)floatOnTop;

/// Called when the user wants to run a shortcut action.
/// Pass newWindow=YES to run it in a new terminal window instead of the current session.
- (void)bottomBar:(iTermBottomBar *)sender runAction:(iTermAction *)action inNewWindow:(BOOL)newWindow;

/// Called when the user clicks "Manage..." to open the shortcuts preferences panel.
- (void)bottomBarManageShortcutsClicked:(iTermBottomBar *)sender;

@end

/// Preferred height for the bottom bar (points).
extern const CGFloat iTermBottomBarHeight;

@interface iTermBottomBar : NSView

@property (nonatomic, weak, nullable) id<iTermBottomBarDelegate> delegate;

/// Refresh the control states from the delegate (called after window focus changes, etc.)
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
