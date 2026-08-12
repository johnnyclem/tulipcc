# AMYboard Starter

A simple **macOS app** for teachers and students using [AMYboard](https://amyboard.com).

- No terminal · no code · no browser account  
- Plug in USB-C → pick a **JUNO** or **DX-7** factory sound → play  
- UI styled after the **Roland JU-06A / Juno** and classic **Yamaha DX7** panels  
- Full factory banks: **128 JUNO** + **128 DX-7** presets  
- **128×128 front OLED**: shows engine / bank / patch and live notes; type a classroom message to push to the panel

## What it looks like

| Instrument | Panel | How you pick sounds |
|------------|--------|---------------------|
| **JUNO-6** | Black JU-06A-style face with LFO / DCO / VCF / ENV faders, red LED, BANK + PATCH pads | Group **A/B** × Bank **1–8** × Patch **1–8** (maps to factory A11–B88) |
| **DX7** | Beige DX7-style face with green LCD, algorithm box, operator buttons, voice grid | Bank **I–IV** × Voice **1–32** (128 FM presets) |

Audio comes out of the **AMYboard** jack — not Mac speakers.

## Build

```bash
cd tools/amyboard-starter
./build.sh
open "dist/AMYboard Starter.app"
```

Requires **macOS 13+** (Xcode Command Line Tools).

Regenerate patch name tables after `patches.py` changes:

```bash
python3 gen_patch_banks.py
```

## Give it to a non-technical friend

```bash
cd tools/amyboard-starter
./build.sh
cd dist && zip -r AMYboard-Starter.zip "AMYboard Starter.app"
```

Send the zip. First launch on their Mac: **right-click → Open**.

See **CLASSROOM.md** for a printable handout.

## Project layout

```
tools/amyboard-starter/
  Package.swift
  build.sh
  gen_patch_banks.py
  Info.plist
  Sources/
    AMYboardStarterApp.swift
    ContentView.swift
    AMYboardMIDI.swift
    JunoPanelView.swift      # JU-06A-style panel
    DX7PanelView.swift       # Classic DX7-style panel
    KeyboardView.swift
    Presets.swift
    PatchBanks.swift         # full 128+128 names (generated)
  CLASSROOM.md
  dist/
    AMYboard Starter.app
```

## How it talks to the board

Same path as the web editor / `amyboardctl`:

- SysEx `F0 00 03 45 … F7` with AMY wire `i1K{patch}ivN Z` to load a preset  
- Normal MIDI note on/off on channel 1 to play  
- Optional live filter/level tweaks via short `zP` Python lines  
- OLED updates via `zP` calling `amyboard.display` (stops any running sketch loop so it owns the panel)

See `docs/amyboard/control_api.md`.

### OLED notes

- Plug a supported **SH1107 / SSD1327** 128×128 into the **front** Grove I2C jack (not the rear Tulip jack).  
- On connect the app calls `amyboard.stop_sketch()` then draws status; restart the board (or `amyboard.restart_sketch()` from a REPL) to return to a saved sketch like `menu_nav`.
