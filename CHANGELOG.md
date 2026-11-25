# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Camera zoom slider for the side layout (adjustable while recording), with blurred fill instead of black bars.

### Docs
- iPhone as camera (Continuity Camera): setup, requirements and stability tips.

### Fixed
- iPhone (Continuity Camera) now shows up in the camera list (`NSCameraUseContinuityCameraDeviceType` in `Info.plist`).

## [0.1.0] - 2026-11-25

### Added
- Screen recording with ScreenCaptureKit and hardware encoding (H.264 / HEVC), 720p–1440p, 30/60 fps.
- Full display or single-window capture.
- Separate audio tracks for music input, microphone and Mac audio, with live per-track volume and peak meters.
- Camera bubble (floating window) and side camera (1/4 of the frame, left or right).
- Side-camera layouts: fit to source (no black bars) or fixed 16:9.
- Best native camera format up to 1080p30 for the side camera.
- Fragmented `.mov` output, PressStream panel excluded from the recording.
- Low-priority GPU composition that only renders when the screen or camera changes.
