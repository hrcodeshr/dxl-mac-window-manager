# dxl-mac-window-manager

Windows-style window snapping for macOS, written in Swift.

Drag a window to a screen edge or corner to tile it. Drag to the top of the screen to pick a multi-pane layout. After one window snaps, choose another open window to fill the remaining space.

## Why Swift

Swift is the most efficient implementation for this on Mac:

- The OS APIs that move other apps' windows (`AXUIElement`, Accessibility) are native Cocoa APIs. Swift talks to them directly, with no bridge.
- The snap overlay is an `NSPanel` drawn in AppKit. Same process, no Electron/JS hop.
- Production Mac window managers (Rectangle, AeroSpace, Loop) are Swift for the same reason.
- C/Obj-C is not faster here. The cost is Accessibility IPC and window-server round trips, not language overhead.
- Rust, Python, or Electron would wrap those same APIs with more code and worse overlay latency.

This repo cannot be compiled on Windows. Use GitHub Actions for a Mac build, or compile on a Mac.

You do not need Xcode. A Swift toolchain is enough. `make test` does not use XCTest.

## Build (macOS 13+)

```bash
git clone https://github.com/hrcodeshr/dxl-mac-window-manager.git
cd dxl-mac-window-manager
make test
make package
open "dist/DXL Window Manager.app"
```

Or open `Package.swift` in Xcode and run the `DXLWindowManager` target.

## First launch

1. Click the menu bar icon (split rectangle).
2. Choose **Request Accessibility Access…**
3. Enable **DXL Window Manager** in System Settings → Privacy & Security → Accessibility.
4. Drag a window to the left or right edge, a corner, or the top of the screen.

The app has no Dock icon. It lives in the menu bar.

If macOS Sequoia's built-in tiling also fires, turn off **Tile by dragging windows to screen edges** in System Settings → Desktop & Dock so only this app handles snap.

## Snap behavior

- **Left / right edge:** half screen
- **Corners:** quadrants
- **Top edge:** layout picker (two columns, 2/3, three columns, stacked, quadrants, two rows). Drop on a zone. If you miss a zone, the window maximizes.
- **After snap:** remaining windows are offered for the empty pane (Snap Assist). Click one, or click outside / press Esc to dismiss.
- **Unsnap:** drag a snapped window away from the edges and it returns to its previous size, the way Windows does.

## Keyboard

Hold Control-Option:

| Shortcut | Action |
| --- | --- |
| ← / → | Left / right half |
| ↑ | Maximize |
| ↓ | Bottom half |
| U I / J K | Quadrants |

## Log

The app writes `~/Library/Logs/dxl-window-manager.log`. Use **Open Log** or **Reveal Log in Finder** from the menu bar icon. That file is the first thing to check if snap does nothing on a Mac.

## CI

Pushes to `main` run tests and package the `.app` on GitHub-hosted macOS. Download the artifact from the Actions run if you want a build without compiling locally.

## Requirements

- macOS 13 Ventura or later
- Accessibility permission
- Not sandboxed (it has to resize other apps' windows)
