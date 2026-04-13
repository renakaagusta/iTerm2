//
//  iTermStatusBarAppctlComponent.h
//  iTerm2SharedARC
//

#import "iTermStatusBarTextComponent.h"

NS_ASSUME_NONNULL_BEGIN

/// Status bar component that displays appctl VS Code windows, Chrome sessions,
/// and background processes. Polls every 5 seconds via the appctl daemon socket
/// (for VS Code / Chrome) and reads ~/.appctl/procs/registry.json directly
/// (for proc list).
@interface iTermStatusBarAppctlComponent : iTermStatusBarTextComponent

@end

NS_ASSUME_NONNULL_END
