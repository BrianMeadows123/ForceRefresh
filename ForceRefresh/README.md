# ForceRefresh

A menu bar app that forces a specific external display to run at
3840x2160 @ 59.94 Hz on Apple Silicon Macs, by injecting a patched EDID
whenever the display connects (or the Mac wakes from sleep).

## Why this needs to exist

On Apple Silicon, macOS's display pipeline runs through the DCP
(Display CoProcessor), which ignores the classic
`/Library/Displays/.../Overrides` plist method Intel Macs used for
custom EDIDs. The only thing that currently works is injecting a
virtual EDID at runtime through a private, undocumented API
(`IOAVServiceSetVirtualEDIDMode`). That's what this app does.

Two honest caveats:
- It's a private/undocumented API. It could stop working in a future
  macOS update.
- The override isn't persistent -- it has to be reapplied every time
  the display connects or the Mac wakes up, which is why this is a
  background app rather than a one-shot script.

## How 59.94 Hz gets built

Rather than inventing a brand-new custom timing, `patch_edid_5994.py`
takes your display's *existing* 3840x2160@60Hz detailed timing and
multiplies only the pixel clock by 1000/1001 -- the same "NTSC
pulldown" factor broadcast video has used forever to turn 60 into
59.94, 30 into 29.97, 24 into 23.976. Horizontal/vertical totals and
sync widths stay identical to what the display already advertises (and
what macOS already accepts) at the whole-number rate.

## Quick start

1. **Clone and open.**
   ```bash
   git clone <your-repo-url>
   open ForceRefresh/ForceRefresh.xcodeproj
   ```
   Or in Xcode: File -> Clone Repository... and paste the URL.

2. **Turn off App Sandbox.** Select the ForceRefresh target ->
   Signing & Capabilities. If a "App Sandbox" capability is present,
   remove it (click the "x" in its corner) -- sandboxed apps can't
   reach the IOKit services this needs. A fresh clone of this repo has
   no entitlements file, so this is usually already off; just confirm
   the capability isn't there.

3. **Build and run** (Cmd+R). A small TV-shaped icon appears in your
   menu bar.

4. **Dump your display's real EDID**, with it connected directly
   (skip any KVM/switcher for this step):
   ```bash
   ioreg -l -w0 -r -c IOMobileFramebuffer | grep -A1 "IODisplayEDID" | tail -1 | sed 's/.*<//;s/>//' | xxd -r -p > monitor.bin
   ```

5. **Patch it:**
   ```bash
   python3 patch_edid_5994.py monitor.bin --list          # confirm you see 3840x2160
   python3 patch_edid_5994.py monitor.bin 3840 2160 monitor_59_94.bin
   ```

6. **Load it in the app.** Menu bar icon -> "Set Custom EDID..." ->
   "Choose File..." -> select `monitor_59_94.bin` -> "Save & Apply".

7. **Verify.** System Settings -> Displays should now offer 59.94 Hz.
   If you have a signal analyzer / test monitor, trust that reading
   over the OS's own dropdown -- it reports the actual transmitted
   signal rather than just echoing back what the EDID claims.

## Limitations worth knowing before you rely on this

- **Bandwidth**: 3840x2160 at ~59.94 Hz needs roughly the same pixel
  clock as 4K@60 (~590+ MHz depending on your display's exact
  blanking). Confirm your connection (HDMI 2.0/2.1, DisplayPort,
  Thunderbolt dock) already handles 4K@60 cleanly -- if it doesn't,
  59.94 won't either.
- This targets *all* connected external displays, not one specific
  one. If you regularly connect other displays that shouldn't get this
  treatment, open an issue / ask for vendor-ID filtering to be added
  to `DisplayWatcher`.
- This project was assembled by hand (including the `.xcodeproj`) and
  hasn't been opened in a real copy of Xcode to confirm it loads
  cleanly. If Xcode reports any project-file error on open, share the
  exact message and it can be fixed immediately -- worst case, the
  source files under `ForceRefresh/` are plain Swift/Obj-C and can be
  dropped into a fresh Xcode-generated project in a couple of minutes.

## Project layout

```
ForceRefresh/
├── patch_edid_5994.py              # EDID pulldown patcher (run from Terminal)
├── ForceRefresh.xcodeproj/
└── ForceRefresh/
    ├── AppDelegate.swift           # menu bar item + menu
    ├── DisplayWatcher.swift        # detects connect/wake, reapplies EDID
    ├── EDIDSourceWindowController.swift  # "Set Custom EDID..." window
    ├── EDIDInjector.h / .m         # private IOAVService API wrapper
    ├── ForceRefresh-Bridging-Header.h
    └── Info.plist                  # sets LSUIElement (no Dock icon)
```
