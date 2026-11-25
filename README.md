<div align="center">

# 🎛️ PressStream

**A lightweight macOS screen recorder built for DJs and music producers.**

Record Ableton Live or Rekordbox with your camera and your mix — without choking an 8 GB M1.

[Português](README.pt-BR.md) · [Architecture](docs/ARCHITECTURE.md) · [Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md)

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-optimized-blue)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

</div>

---

## Why

General-purpose recorders do a lot of work you don't need. When your DAW or DJ software
is already using most of the machine, every extra copy of a frame counts. PressStream
keeps the whole video path on the GPU and the media engine, so the CPU stays free for
your music.

## Features

| | |
|---|---|
| 🖥️ **Source** | Full display **or a single window** (e.g. only Ableton: no menu bar, no Dock) |
| 🎚️ **Audio** | Up to 3 separate tracks: **Music** (controller / interface / virtual device), **Microphone** and **Mac audio** |
| 🔊 **Levels** | Per-track volume (−∞ to +6 dB) with peak meters, adjustable **while recording** |
| 📷 **Camera** | **Bubble** (floating, zero-cost) or **Side** panel taking 1/4 of the frame, left or right, with live zoom |
| 📐 **Layout** | *Fit to source* (no black bars) or fixed *16:9* (stream-ready) |
| 🎞️ **Quality** | 720p / 1080p / 1440p, 30 / 60 fps, H.264 or HEVC hardware encoding |
| 🛟 **Safety** | Fragmented `.mov`: if anything crashes, what was recorded is still playable |
| 🙈 **Clean output** | The PressStream panel never shows up in the recording |

## Requirements

- macOS 13 Ventura or later (macOS 14+ recommended)
- Apple Silicon (Intel Macs work, but weren't the target)
- Xcode or the Command Line Tools (`xcode-select --install`)

## Getting started

```bash
git clone https://github.com/<your-user>/pressstream.git
cd pressstream
make run
```

`make run` builds the Swift package, assembles `build/PressStream.app`, signs it and opens it.

| Command | What it does |
|---|---|
| `make build` | Build and bundle `build/PressStream.app` |
| `make run` | Build and open the app |
| `make clean` | Remove build artifacts |

Recordings are saved to `~/Movies/PressStream`.

### Permissions

On first launch macOS will ask for:

1. **Screen Recording:** allow PressStream in *System Settings → Privacy & Security → Screen Recording*, then **reopen the app**.
2. **Camera / Microphone:** requested when you turn the camera on or pick an audio input.

> **Tip:** if you have an *Apple Development* certificate (Xcode → Settings → Accounts), the
> build script signs with it automatically and the Screen Recording permission survives rebuilds.
> Without it the app is signed ad-hoc and macOS may ask again after each build.
> You can force an identity with `SIGN_IDENTITY="Apple Development: Name (TEAMID)" make run`.

## Usage tips for DJs

### Recording Rekordbox (or any app routed to a virtual device)

1. In Rekordbox, send the master output to your virtual / aggregate device.
2. In PressStream, choose that device under **Music**.
3. Choose your real microphone under **Microphone**. Each one gets its own track and fader.
4. Turn **Mac audio** off if Rekordbox is the only sound you need, to avoid doubling.

> PressStream records the **first two channels** of each input device. If your aggregate device
> puts the microphone on channels 1–2, select the virtual device itself (e.g. BlackHole / Loopback)
> under **Music** instead of the aggregate.

### Keeping the DJ software smooth on an 8 GB machine

- **30 fps** halves capture, composition and encoding work. Waveforms still look fine.
- Prefer **Window** capture: fewer pixels than the whole display.
- **Bubble** camera costs nothing; **Side** camera adds a (low-priority) GPU composition step.
- **H.264** is slightly lighter than HEVC on the M1 media engine.
- Close browsers and other GPU-heavy apps while recording.

### Using your iPhone as the camera (Continuity Camera)

An iPhone usually looks much better than a 1080p webcam, especially in low light, and its
microphone is good too. PressStream supports it out of the box.

**Requirements:** iPhone XR or later on iOS 16+ (iOS 17+ recommended), macOS 13+, the same Apple ID
on both devices, Wi-Fi and Bluetooth on, and *Settings → General → AirPlay & Continuity →
Continuity Camera* enabled on the iPhone.

1. Put the iPhone on a stand, **locked**, rear camera facing you. It must be still.
2. Pick it in the camera list (e.g. "Wallace's iPhone Camera"). The list updates when it connects.
3. Optionally pick the iPhone microphone under **Microphone**.

Tips:

- **Shaky image?** The iPhone's optical stabilization amplifies small vibrations. Every touch on
  the controller travels through the desk. Use a tripod standing on the floor or a mount on
  another piece of furniture, or at least a rubber pad under the stand.
- **Turn off Center Stage** (*Control Center → Video Effects*). It keeps reframing as you move,
  which looks like wobble in the Side layout.
- **Use a cable** (USB-C / Lightning) for long sessions: steadier video, and the phone charges.
- **Portrait orientation** fits the Side layout best: the vertical image needs almost no cropping.
- Portrait mode and Studio Light run on the iPhone itself, so they cost nothing on the Mac.

### Multiple audio tracks

The `.mov` contains one audio track per source, in this order: **Music → Microphone → Mac audio**.
QuickTime plays all of them mixed; editors like DaVinci Resolve, Final Cut and Premiere import
them as separate tracks so you can rebalance later.

## How it stays light

```
ScreenCaptureKit ──(YUV 4:2:0, GPU-scaled IOSurface)──► AVAssetWriter ──► VideoToolbox (HW) ──► .mov
                                                       ▲
AVCaptureSession (music, mic) ──(PCM + vDSP gain)──────┘
```

- Frames are delivered already **scaled and in the encoder's native format**: no CPU color conversion.
- Frames never leave GPU memory (IOSurface) on their way to the hardware encoder.
- Video, audio and composition share **one serial queue**: no locks, no cross-thread copies.
- Unchanged frames are skipped; the side-camera compositor only renders when something changed,
  at **low GPU priority**.

Details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Roadmap

- [ ] Live streaming (RTMP / SRT) sharing the same encoded video as the file
- [ ] Global hotkey to start/stop
- [ ] Choose which input channels to record (multichannel interfaces / aggregate devices)
- [ ] Horizontal framing offset for the side camera
- [ ] Bubble size and shape options
- [ ] Menu bar mode and app icon
- [ ] Signed and notarized releases

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.
Performance is a feature here: changes to the capture pipeline should come with a note on CPU / GPU / memory impact.

## License

[MIT](LICENSE)
