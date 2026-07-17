# pnotepad

A fast, native notepad for KDE Plasma written in Rust (cxx-qt) with a QML interface styled by Breeze.

## Features

- Tabs, like Windows 11 Notepad
- Never asks to save: every tab is continuously autosaved and fully restored on the next launch, including cursor position and the active tab
- Clear dump: files away all unsaved notes into a folder of your choice, naming each file from its content, then closes them
- Find and replace, word wrap, zoom, status bar with line/column and character count
- Fully offline, no telemetry, tiny footprint

## Build

Requires Rust (rustup), Qt 6 development headers, and the KDE QtQuick style:

```
sudo dnf install gcc-c++ qt6-qtbase-devel qt6-qtdeclarative-devel kf6-qqc2-desktop-style
cargo build --release
```

The binary is at `target/release/pnotepad`.

## Storage

Session data lives in `~/.local/share/pnotepad/session/`. Each tab is one text file plus an `index.json` with metadata.
