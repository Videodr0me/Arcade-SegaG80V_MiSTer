# Star Trek, Tac/Scan, and Zektor for MiSTer FPGA

An FPGA implementation of Sega's G80 color-vector arcade hardware for the
[MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki) platform. The
current release includes **Star Trek: Strategic Operations Simulator**,
**Tac/Scan**, and **Zektor**, three distinctive 1982 space games built on the
same hardware.

Star Trek puts the Enterprise under direct command. Read the tactical scanner,
fight through the forward view, fire phasers and photon torpedoes, engage
impulse or warp, and listen to familiar bridge voices guide the mission.
Tac/Scan takes a very different approach, placing a formation of up to seven
fighters under one rotary control. Rebuild the squadron, fire every ship in a
single salvo, survive attacks from changing perspectives, and guide the fleet
through its glowing space-warp tunnel. In 1982, this gave Tac/Scan extraordinary
firepower for an arcade shooter: as many as seven player ships could fire at
once.

Zektor tasks the player with liberating eight cosmic cities seized by alien
robots. Follow the warrior-maiden's call and join the fight against Roboprobes,
Moboids, and Zizzers. The best warriors will confront each city's robot ruler
in the ultimate vector battle.

This core is a collaboration between **alanswx** and **Videodr0me**. The
original G80V machine core and speech implementation were created by alanswx
from Sega hardware documentation and Aaron Giles' detailed G80 research in
MAME.
Videodr0me rebuilt the vector generator for high-resolution raster
presentation, integrated the CRT-effects pipeline, added video modes and
geometry controls, expanded input support, and refined Universal Sound Board
filtering and mixing from Sega schematics and manuals. He also rebuilt
Zektor's discrete-audio implementation from its original schematics.

---

## Original Hardware

| Subsystem | Original Hardware | FPGA Implementation |
|---|---|---|
| **Main CPU** | Z80 at 3.867120 MHz from the 15.46848 MHz master clock | Cycle-based Z80-compatible G80 machine core with Sega address-security support |
| **Security** | Sega 315-0064 in Star Trek, 315-0076 in Tac/Scan, and 315-0082 in Zektor | Game-selected address permutation matching each security device |
| **Vector Generator** | Sega X-Y Timing board, vector RAM, sine/cosine PROM, DACs, and analog deflection | Native G80 vector sequencer with a doubled-density shadow DDA and high-resolution raster presentation |
| **Color** | Six-bit `RRGGBB` resistor-DAC output, with two bits per electron gun and 64 possible colors | All six native color bits are retained through drawing, crossings, phosphor decay, and presentation |
| **Audio** | Universal Sound Board in Star Trek and Tac/Scan; Star Trek and Zektor use 8035-controlled SP0250 speech, while Zektor adds a discrete sound board and AY-3-8912 | Universal Sound Board and speech models plus schematic-derived Zektor discrete audio and AY sound, with calibrated filtering and mixing |
| **Display** | Horizontal color X-Y monitor in Star Trek and Zektor; vertical color X-Y monitor in Tac/Scan | 1080p, 720p, 480p, 480i, and 240p output with rotation, bloom, halo, and phosphor behavior |
| **Controls** | Rotary control and action buttons | Spinner, mouse, analog stick, or digital rotation with adjustable direction and sensitivity |

---

## Controls

### Star Trek

| Input | Function |
|---|---|
| **Left / Right, Spinner, Mouse, or Analog Stick** | Rotate the Enterprise |
| **Phaser (Button A)** | Fire phasers |
| **Impulse (Button B)** | Engage impulse power |
| **Photon (Button X)** | Fire a photon torpedo |
| **Warp (Button Y)** | Engage warp drive |
| **Start 1 / Start 2** | Start a one-player or two-player game |
| **Coin** | Insert a credit |

### Tac/Scan

| Input | Function |
|---|---|
| **Left / Right, Spinner, Mouse, or Analog Stick** | Rotate the ship formation |
| **Fire (Button A)** | Fire the active formation |
| **Add Ship (Button B)** | Add a reserve ship to the formation |
| **Start 1 / Start 2** | Start a one-player or two-player game |
| **Coin** | Insert a credit |

### Zektor

| Input | Function |
|---|---|
| **Left / Right, Spinner, Mouse, or Analog Stick** | Rotate the ship |
| **Fire (Button A)** | Fire |
| **Thrust (Button B)** | Apply thrust |
| **Start 1 / Start 2** | Start a one-player or two-player game |
| **Coin** | Insert a credit |

### Keyboard

Keyboard controls use MiSTer's per-core keyboard mapping and can be reassigned
from the input mapping menu. Service and Self-Test remain in the DIP Switches
menu.

### Input Controls Menu

| Option | Function |
|---|---|
| **Direction** | Selects normal or reversed rotation. |
| **Sensitivity** | Adjusts spinner, mouse, analog stick, and digital rotation speed. |

The analog stick has a center dead zone and increases rotation speed with
travel. Digital Left and Right remain available as a fallback.

---

## Requirements

- DE10-Nano MiSTer
- 32 MB or larger SDRAM module
- ROMs matching the supplied MRA files

The SDRAM module is used by the video pipeline in addition to MiSTer's DDR3.
ROMs are not included.

## Installation

Copy the release RBF to `_Arcade/cores/` and these MRA files to `_Arcade/`:

- `Star Trek.mra`
- `Tac-Scan.mra`
- `Zektor (revision B).mra`

Launch a game through its MRA so MiSTer can assemble and download the required
ROM image.

## Recommended MiSTer Video Settings

The renderer supports 240p, 480i, 480p, 720p, and 1080p. **1080p is
recommended** with `hdr=1` for the highest vector detail and dynamic range.
Compatible 720p displays can also use the optional 120 Hz mode.

For high-resolution flat-panel output, place the following settings under the
exact `[SegaG80V]` header at the end of `MiSTer.ini`. The empty filter and
mask entries prevent MiSTer's scaler effects from altering the core's own CRT
pipeline.

```ini
[SegaG80V]
video_mode=8   ; 8 = 1080p, 0 = 720p
hdr=1
vsync_adjust=1 ; use 1 or 2 for 120 Hz output
vscale_mode=0
vfilter_default=
vfilter_vertical_default=
vfilter_scanlines_default=
shmask_default=
shmask_mode_default=0
```

### CRT and Direct Video Output

#### CRT Output

> **Required for CRT output:** Before loading the core, add all three entries
> below to the `[SegaG80V]` section of `MiSTer.ini`. They select a
> CRT-compatible timing and disable MiSTer's VGA scaler and scandoubler.
>
> Without these settings, VGA may receive an out-of-range HD timing, native
> 480i will not work correctly, and image quality will be reduced.

For a 15 kHz CRT:

```ini
[SegaG80V]
video_mode=720,240,60
vga_scaler=0
forced_scandoubler=0
```

Place the `[SegaG80V]` section at the end of `MiSTer.ini`. Later entries take
priority, ensuring that these core-specific settings override global settings.
At 15 kHz, **15 kHz Format** selects 480i or 240p, with 480i used by default.
Both formats require `vga_scaler=0` and `forced_scandoubler=0` for native
output, as shown above.

For a 31 kHz CRT, use `video_mode=720,480,60` instead.

#### Direct Video

Use `direct_video=1` in `MiSTer.ini`. The **Direct Video Scan Rate** option
then selects 15 kHz or 31 kHz output, while **15 kHz Format** selects 480i or
240p at 15 kHz.

#### Alternatives if Sync Fails

These alternatives are not recommended. Using `vga_scaler=1` greatly reduces
image quality and should be considered only when native output will not
synchronize. MiSTer's scaler then drives VGA using the selected `video_mode`,
but does not allow proper 480i output. `vsync_adjust=0` retains that modeline's
refresh rate; `1` or `2` adjusts its pixel clock to follow the core.

Keep the normal `vga_mode`, `composite_sync`, and `vga_sog` settings required
by your CRT connection.

---

## Video Options

### Video Profiles & Effects

| Profile | Description |
|---|---|
| **A Touch of CRT** | Modern clarity with subtle halo and bloom while vectors remain crisp. |
| **80s Cruise Control** | Richer glow and stronger bloom with a restrained color-vector CRT look. |
| **80s Overdrive** | Hot vectors, heavy bloom, and lingering phosphor trails. |
| **Neon Fever Dream** | Voltage-up neon color, vector flicker, and restless phosphor trails. |
| **Mutara Nebula** | Broad bloom, dense halo, and persistent trails push the color-vector look furthest. |
| **Custom 1 / Custom 2** | Two independent slots exposing the individual CRT controls. |
| **Off** | True short-path bypass of the CRT effects. |

> [!WARNING]
> **Neon Fever Dream** and **Mutara Nebula** can produce excessive flashing and
> bright light.

Custom profiles expose Dot Scale, Tone Mapping, Bloom, Halo, Inter-Frame and
Intra-Frame Decay, Color Space, Color Effect, and Slot Mask. Their exact
settings and every fixed-profile value are listed in the
[CRT Profile Settings](Profiles/README.md).

### Video Timing & Geometry

| Option | Description |
|---|---|
| **Orientation** | Selects normal, 90-degree clockwise, 180-degree, or 90-degree counterclockwise presentation. |
| **Open Matte** | Shows vector content outside the original display window where the output raster permits it. Enabled by default. |
| **Buffer Mode** | Selects EOF + VBL, VBL-only, or EOF-only frame presentation. |
| **120 Hz (720p only)** | Enables real 120 Hz presentation when the active host mode is 720p. |
| **Direct Video Scan Rate** | Selects 15 kHz or 31 kHz while Direct Video is active. |
| **15 kHz Format** | Selects 480i or 240p in the 15 kHz output bracket. |
| **Aspect Ratio** | Optimized is the intended default. Use the alternatives only when required, as they reduce image quality. |

---

## ROMs

The release supports these MAME ROM sets:

| Game | MRA | ROM archive |
|---|---|---|
| **Star Trek** | `releases/Star Trek.mra` | `startrek.zip` |
| **Tac/Scan** | `releases/Tac-Scan.mra` | `tacscan.zip` |
| **Zektor** | `releases/Zektor (revision B).mra` | `zektor.zip` |

Eliminator and Space Fury remain development targets and are not part of this
release.

## Compilation

Use Quartus Prime Lite 17.0.x. Open the project `Arcade-SegaG80V.qpf` and compile. The result is written to `output_files/Arcade-SegaG80V.rbf`.

## Credits and Acknowledgments

- **alanswx:** Original Sega G80V machine core, CPU and security integration,
  MRAs, and sound and speech foundation.
- **Videodr0me:** High-resolution vector presentation, framebuffer and CRT
  effects, expanded controls, schematic-derived Universal Sound Board
  filtering, and the Zektor discrete-audio implementation.
- **Aaron Giles and MAME contributors:** detailed G80 machine, vector, and
  sound research and executable reference.
- **JimmyStones and Arnim Laeuger:** T48 8035-compatible sound CPU work.
- **Jose Tejada:** `jt49` AY implementation retained in the source tree.
- **GI SP0250 digital LPC sound synthesizer:** O. Galibert.
- **Mark Jenison:** preserved Sega/Gremlin G80 hardware research.
- **MiSTer platform:** Sorgelig and the MiSTer community.

## License

This project is licensed under GPL-3.0. Individual vendored components retain
their original notices and licenses.
