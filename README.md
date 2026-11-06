# PowerPresenter

A high-performance, broadcast-grade presentation engine built natively for macOS using **Swift 6, SwiftUI, AppKit, CoreAnimation, CoreText, and AVFoundation**.

Designed for live productions, multi-screen houses of worship, and zero-latency operator control.

---

## ⚡ Key Capabilities

### 1. Direct PowerPoint (.pptx) Import & Named Element Extraction
- **Native Ingestion**: Direct import of `.pptx`, `.ppt`, and `.pdf` presentation decks via the **`Import...`** toolbar button.
- **Microsoft PowerPoint Engine**: Automates Microsoft PowerPoint (`com.microsoft.Powerpoint`) directly via Apple Events to render 100% native slide graphics and formatting, with native macOS vector fallback. Keynote is not used.
- **OpenXML Shape & Text Box Extraction**: Unpacks the `.pptx` container and scans all slide shapes. Grabs text from specific named text boxes (e.g. `name="something"`, `name="Title 1"`, `name="Speaker"`, `name="Subtitle"`).
- **Embedded Media & Speaker Notes**: Automatically extracts embedded audio/video files (`ppt/media/`) and presenter notes (`ppt/notesSlides/`).
- **4K Vector Slide Rendering**: Rasterizes slides at retina/4K resolution with zero font mismatching.

### 2. Service Liturgy Flow & One-Click Section Automation
- **Liturgy Quick Bar**: Categorize slides into liturgical sections (카운트다운영상, 호스팅, 찬양, 말씀, 결단찬양/기도, 광고).
- **Batch Range Selection**: Shift-Click (continuous range) and ⌘-Click (multi-select) slides to assign service sections with a single click.
- **Auto-Configured Stage Presets & MIDI Cues**: Selecting a section automatically links the preset stage display layout and triggers MIDI signals on the first slide of each section.
- **Customizable Order & Formats**: Reorder, add, or customize church service sections anytime.

### 3. In-App Slide Text & Content Editor
- Right-click or double-click any slide thumbnail to open the **Slide Content Editor**.
- Edit text in real-time right before or during live events without returning to PowerPoint.
- Smart CoreText vector overlay preserves background graphics, photos, and shapes with pixel precision.

### 4. Multi-Display Output Configurator
- Open via the **`Displays...`** toolbar button.
- Detects all connected physical displays and projectors (`NSScreen`).
- **Assign specific roles to each monitor**:
  - **Audience Output**: Pinned fullscreen borderless window (`.screenSaver` level, zero UI, VSync locked). Multiple displays can mirror or act as audience outputs simultaneously.
  - **Stage Display**: Dedicated confidence monitor facing the speaker on stage.
  - **Disabled**: Releases display.
- Also supports floating auxiliary windows for single-screen rehearsals.

### 5. Customizable Stage Screen (Confidence Monitor)
- Open the layout editor via **`Stage Layout...`** in the toolbar.
- **Named Element Extractor**: Prominently display the contents of a specific named text box from the active slide (e.g., grabbing a cue box named `"something"`).
- **Customizable Widgets**:
  - Digital Clock (`h:mm:ss a`)
  - Stage Timer (Start / Pause / Reset)
  - Slide Progress Counter (`Slide X / Total`)
  - Current Slide & Upcoming Slide previews
  - High-contrast Presenter Notes (customizable font size from 16pt to 36pt)
  - Stage Alert Banners (flashes operator messages in yellow across the stage display)
- **Color Themes**: High-Contrast Amber, Cyber Cyan, Classic White, and Stage Emerald.

### 6. Sound Output Routing & Hardware Device Selector
- **CoreAudio Hardware Routing**: Select specific audio destinations (USB Audio Interfaces, HDMI, Bluetooth speakers, Built-in Speakers, or macOS System Default) directly from the **`Audio...`** toolbar button or `Audio` menu bar.
- **Independent Playback Device**: AVPlayer routes video soundtracks and background media directly to the selected hardware without changing the macOS system-wide default audio device.
- **Real-Time Hotplug & Auto-Fallback**: Automatically detects newly connected or disconnected audio hardware in real time via CoreAudio listeners.
- **Audio Test Ping**: Play short diagnostic chimes to verify hardware sound routing before live services.
- **Media Master Volume**: In-app master volume control (0%–100%) independent of system volume.

### 7. MIDI Automation & Zero-Latency Engine (< 0.2ms)
- **Hardware MIDI Triggers**: Automatic Program Change, Control Change, or Note On triggers bound to slide entries for lighting consoles, audio mixers, and Ableton Live.
- **Unified `@MainActor` memory model** with direct `CATransaction` dispatch.
- **Hardware GPU Transitions**: Cut, Crossfade (0.35s / 0.75s), Push Left / Right, and Cinematic Zoom.
- **Emergency Blackout (`⌘ + B`)**: Instant cut-to-black on top-most `CALayer` (`zPosition: 9999`) with zero animation delay.
- **Clear Media (`⌘ + M`)**: Instant audio/video mute without disrupting slide visuals.

### 7. Over-The-Air (OTA) Auto-Updater
- Checks for updates directly from GitHub Releases via native REST API.
- Live download progress bar, release changelog viewer, and one-click update & restart.
- Automated release builds via GitHub Actions CI/CD.

---

## 🕹️ Keyboard Shortcuts

| Action | Shortcut |
| :--- | :--- |
| **Next Slide** | `Spacebar` / `Right Arrow` |
| **Previous Slide** | `Left Arrow` |
| **Emergency Blackout** | `⌘ + B` |
| **Clear / Mute Media** | `⌘ + M` |
| **Toggle Audience Window** | `⌘ + D` |
| **Toggle Stage View Window** | `⌘ + S` |
| **Zoom Slide Previews** | `⌘ + =` / `⌘ + -` / `⌘ + 0` |

---

## 🚀 Running & Building

### Quick Launch (Debug)
```bash
./scripts/run.sh
```

### Build & Open macOS App Bundle
```bash
./scripts/build_app.sh
open PowerPresenter.app
```

---

## 📦 GitHub Release & CI/CD

To publish a new release:
1. Bump the version in `scripts/build_app.sh` (e.g. `2.0.1`).
2. Commit and tag:
   ```bash
   git tag v2.0.1
   git push origin v2.0.1
   ```
3. GitHub Actions (`.github/workflows/release.yml`) will automatically build `PowerPresenter.app`, package `PowerPresenter.zip`, and publish the release with changelogs.
4. Installed PowerPresenter apps will automatically detect the new version and prompt users to update with one click!
