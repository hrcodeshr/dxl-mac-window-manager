# dxl-mac-window-manager

Windows-style window snapping for macOS.

Drag a window to a screen edge or corner to tile it. Drag to the top of the screen to maximize or pick a multi-pane layout (halves, thirds, quadrants). After one window snaps, choose another open window to fill the remaining space.

## Status

Early scaffolding. Native implementation will target macOS (Swift / AppKit or SwiftUI) and is not usable yet.

## Goals

- Drag-to-edge snap (left/right halves, corner quarters)
- Drag-to-top layout picker, similar to Windows 11 Snap Layouts
- Fill remaining zones from other open windows (Snap Assist)
- Keyboard shortcuts for the same layouts
- Multi-monitor support
