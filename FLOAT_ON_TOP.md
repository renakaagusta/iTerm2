# iTerm2 — Float on Top Fork

A fork of [iTerm2 v3.6.9](https://github.com/gnachman/iTerm2/releases/tag/v3.6.9) with one added feature: **float the terminal window on top of all other apps**, similar to ChatGPT's desktop companion window.

## Added Feature

**Window → Float on Top** — toggles the current iTerm2 window to always float above all other applications. A checkmark appears in the menu when active.

### How it works

- Sets `NSFloatingWindowLevel` on the window when enabled
- Adds `NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary` so it works across Spaces and alongside fullscreen apps
- Restores `NSNormalWindowLevel` and original collection behavior when disabled
- State is per-window (each window has its own float toggle)
- Zero performance impact — it's a compositor hint only

### Files changed for this feature

| File | Change |
|------|--------|
| `sources/PseudoTerminal.h` | Declared `toggleFloatOnTop:` IBAction |
| `sources/PseudoTerminal.m` | Added `_floatOnTop` ivar, `toggleFloatOnTop:` implementation, `validateMenuItem:` support |
| `Interfaces/MainMenu.xib` | Added "Float on Top" menu item + separator in Window menu |

---

## Build Environment

Built and tested on:
- **macOS**: 15.x (Sequoia)
- **Xcode**: 16.3 (Swift 6.1)

The original repo targets **Xcode 26 beta (Swift 6.2.3)** for macOS 26 (Tahoe) features. Building on Xcode 16.3 required the compatibility fixes below.

---

## ⚠️ Stripped Features (Xcode 16.3 Compatibility)

These features exist in the original v3.6.9 source but were **disabled or replaced** to build on Xcode 16.3. They should be **re-enabled** when building with Xcode 26 beta or later.

### 1. Apple Intelligence — Command Safety Checker

**Files:** `sources/CommandSafetyChecker.swift`, `sources/RemoteCommand.swift`

The `CommandSafetyChecker` uses `FoundationModels` (Apple Intelligence API, macOS 26 only) to classify shell commands as SAFE / CAUTION / DANGEROUS before execution.

**What we did:** Wrapped the entire class and its call site in `#if canImport(FoundationModels)`.

**To restore:** Build with Xcode 26 beta — no code change needed, the `#if` guard handles it automatically.

---

### 2. Liquid Glass UI — NSGlassEffectView

**Files:** `sources/ChatInputTextFieldContainer.swift`, `sources/ChatToolbar.swift`, `sources/iTermOpenQuicklyView.m`, `sources/iTermPasswordManagerWindowController.m`

`NSGlassEffectView` is a new macOS 26 view that renders Apple's "Liquid Glass" material. Used in:
- Chat input field background
- Chat toolbar pill container
- Open Quickly popup background
- Password manager scrim overlay

**What we did:** Replaced with `NSVisualEffectView` (blur) or plain `NSView` fallbacks.

**To restore:** Remove the fallback code and restore the original `if #available(macOS 26, *)` blocks. The original code is in git history.

---

### 3. Liquid Glass Buttons — NSBezelStyleGlass / borderShape

**Files:** `sources/ChatListViewController.swift`, `sources/ChatInputView.swift`, `ThirdParty/PSMTabBarControl/source/PSMRolloverButton.m`

macOS 26 introduced `NSBezelStyleGlass` and `borderShape = .circle` for circular liquid glass buttons. Used for:
- New chat (+) button
- Send message button
- Attach file button
- Tab bar rollover buttons

**What we did:** Replaced with flat borderless buttons (`isBordered = false`) or standard bezel style.

**To restore:** Restore the `if #available(macOS 26, *)` blocks in each file.

---

### 4. Tahoe Tab Bar Style

**Files:** `sources/iTermTheme.m`, `sources/iTermTabBarControlView.m`, `sources/PseudoTerminal.m`, `ThirdParty/PSMTabBarControl/source/PSMTabBarControl.m`

`PSMTahoeTabStyle` (and its variants `PSMTahoeDarkTabStyle`, `PSMTahoeLightHighContrastTabStyle`, `PSMTahoeDarkHighContrastTabStyle`) is a new tab bar rendering style for macOS 26 with liquid glass aesthetics.

**What we did:** Replaced all `PSMTahoeTabStyle` references with `PSMYosemiteTabStyle` / `PSMDarkTabStyle` fallbacks. The `PSMTahoeTabStyle.swift` file itself is safe — it's already wrapped in `#if compiler(>=6.2)`.

**To restore:** Restore the `if #available(macOS 26, *)` blocks that select the Tahoe style.

---

### 5. Rebuilt Swift Frameworks

**Files:** `ThirdParty/SwiftyMarkdown.framework`, `ThirdParty/Highlightr.framework`

The pre-built frameworks in the repo were compiled with Swift 6.2.3 and cannot be imported by Swift 6.1.

**What we did:** Rebuilt both frameworks from source (`submodules/SwiftyMarkdown`, `submodules/Highlightr`) targeting Swift 6.1.

**To restore:** Run `make paranoid-deps` with Xcode 26 beta to rebuild with Swift 6.2.3.

---

### 6. Minor C Compatibility Fix

**File:** `sources/iTermPosixTTYReplacements.c`

`ENOTCAPABLE` is a BSD errno constant not defined in the macOS 15 SDK headers.

**What we did:** Wrapped with `#ifdef ENOTCAPABLE`.

**To restore:** Nothing needed — the `#ifdef` is harmless on any SDK version.

---

## Building

```bash
git clone https://github.com/renakaagusta/iTerm2.git
cd iTerm2
git submodule update --init --recursive
xcodebuild -version > last-xcode-version
xcodebuild -project submodules/SwiftyMarkdown/SwiftyMarkdown.xcodeproj \
  -target SwiftyMarkdown -configuration Release \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  ARCHS="arm64" ONLY_ACTIVE_ARCH=YES \
  "CONFIGURATION_BUILD_DIR=$(pwd)/ThirdParty"
xcodebuild -project submodules/Highlightr/Highlightr.xcodeproj \
  -target Highlightr-macOS -configuration Release \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  ARCHS="arm64" ONLY_ACTIVE_ARCH=YES \
  "CONFIGURATION_BUILD_DIR=$(pwd)/ThirdParty"
xcodebuild -scheme iTerm2 -configuration Development \
  -destination 'platform=macOS' -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  ARCHS="arm64" ONLY_ACTIVE_ARCH=YES
```

## License

Same as the original iTerm2 — see [LICENSE](LICENSE) and [README.license](README.license).
