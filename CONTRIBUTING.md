# Contributing to PressStream

Thanks for wanting to help! PressStream is small on purpose. The guiding rule:

> **Performance is a feature.** The app must stay light enough to run next to a DAW or DJ software
> on an 8 GB Apple Silicon Mac.

## Setup

```bash
git clone https://github.com/<your-user>/pressstream.git
cd pressstream
make run
```

You can also open `Package.swift` in Xcode to edit and navigate. Build and run through `make run`,
because the app needs its `Info.plist` (camera/microphone usage descriptions) inside a real `.app`
bundle.

## Before opening a pull request

- [ ] `make build` passes with no new errors.
- [ ] You tested a real recording (at least a minute) and the file plays in QuickTime.
- [ ] If you touched the capture, audio or composition path, describe the impact on
      **CPU, GPU and memory** (Activity Monitor numbers before and after are perfect).
- [ ] New UI text exists in Portuguese (the app's current language). An English localization is welcome as a separate PR.
- [ ] One feature or fix per PR, with a clear description.

## Code guidelines

- Swift 5.9 language mode, macOS 13 deployment target. Guard newer APIs with `#available`.
- Keep the video path **zero-copy**: avoid moving frames to CPU memory (`CIImage` → `CGImage`,
  `CVPixelBufferLockBaseAddress` for pixel work, etc.).
- Everything that touches `MovieWriter` runs on `CaptureSession`'s `sampleQueue`.
- UI state lives in `RecorderEngine` (`@MainActor`); views stay dumb.
- Prefer small, focused files that match the existing structure (see `docs/ARCHITECTURE.md`).

## Reporting bugs

Please include:

- macOS version and Mac model (chip + RAM)
- Source (display or window), camera mode, resolution, fps and codec
- Which audio devices you selected
- What happened vs. what you expected, and the output of `make run` if it is a build issue

## Good first issues

- Global start/stop hotkey
- Bubble size options
- App icon
- English localization
