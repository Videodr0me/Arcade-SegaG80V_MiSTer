# CRT Profile Settings

These tables list the fixed settings used by the current CRT profiles. Select
`Custom 1` or `Custom 2` in the OSD and enter the values from any row to use it
as a starting point for experimentation.

Profiles resolve independently for 240p, 480p/480i, 720p, and 1080p.

Grouped columns follow the OSD order:

- **Bloom:** Bloom Width / Bloom Curve
- **Halo:** Halo / Halo Curve / Halo Spread / Halo Compression
- **Decay:** Inter-Frame Decay / Intra-Frame Decay

## 240p

| Profile | Dot Scale | Tone Mapping | Bloom | Halo | Decay | Color Space | Color Effect | Slot Mask |
|---|---:|---|---|---|---|---|---|---|
| A Touch of CRT | 2x | Bright | Thin / Mild+ | 0.25x / Mild / Focus / 16 | Off / Off | Off | Original | Off |
| 80s Cruise Control | 2x | Bright | Tight / Mild | 0.25x / Mild / Focus / 16 | Short / Off | Off | Original | Off |
| 80s Overdrive | 2.5x | Linear 2 | Tight / Mild | 0.25x / Mild+ / Focus / 16 | Short / Off | Off | Original | Off |
| Neon Fever Dream | 2.5x | Linear 1 | Thin / Moderate | 0.33x / Mild / Focus / 8 | Medium / LUT C | Off | Original | Off |
| Mutara Nebula | 3x | Bright | Tight / Moderate | 0.33x / Moderate / Focus / 8 | Medium / LUT A | Off | Original | Off |

## 480p and 480i

| Profile | Dot Scale | Tone Mapping | Bloom | Halo | Decay | Color Space | Color Effect | Slot Mask |
|---|---:|---|---|---|---|---|---|---|
| A Touch of CRT | 2x | Bright | Tight / Mild | 0.25x / Mild / Focus / 32 | Off / Off | Off | Original | Off |
| 80s Cruise Control | 2x | Bright | Tight / Mild+ | 0.33x / Mild / Original / 8 | Short / Off | Off | Original | Off |
| 80s Overdrive | 2.5x | Linear 2 | Tight / Mod+ | 0.33x / Mild+ / Original / 32 | Short / Off | Off | Original | Off |
| Neon Fever Dream | 2.5x | Linear 1 | Tight / Strong- | 0.5x / Mild+ / Original / 24 | Medium / LUT C | Off | Original | Off |
| Mutara Nebula | 3x | Bright | Normal / Mild+ | 0.5x / Mod+ / Original / 16 | Medium / LUT A | Off | Original | Off |

## 720p

| Profile | Dot Scale | Tone Mapping | Bloom | Halo | Decay | Color Space | Color Effect | Slot Mask |
|---|---:|---|---|---|---|---|---|---|
| A Touch of CRT | 2.5x | Bright | Tight / Mild+ | 0.25x / Moderate / Focus / 8 | Off / Off | Off | Original | Off |
| 80s Cruise Control | 3x | Bright | Tight / Mod+ | 0.25x / Mod+ / Focus / 16 | Short / Off | Off | Original | Off |
| 80s Overdrive | 3x | Bright | Soft / Mild+ | 0.33x / Moderate / Focus / 24 | Medium / Off | G08 -> 709 | Original | Off |
| Neon Fever Dream | 3x | Off | Normal / Mod+ | 0.5x / Mod+ / Original / 16 | Long / LUT C | Off | Original | Off |
| Mutara Nebula | 3x | Bright | Normal / Mod+ | 0.75x / Mod+ / Wide 2 / 16 | Medium / LUT A | Off | Original | Off |

## 1080p

| Profile | Dot Scale | Tone Mapping | Bloom | Halo | Decay | Color Space | Color Effect | Slot Mask |
|---|---:|---|---|---|---|---|---|---|
| A Touch of CRT | 3x | Bright | Tight / Moderate | 1.0x / Minimal / Focus / 8 | Off / Off | Off | Original | Off |
| 80s Cruise Control | 3x | Bright | Soft / Mild+ | 0.5x / Mild+ / Wide 2 / 16 | Short / Off | Off | Original | On |
| 80s Overdrive | 3x | Linear 2 | Normal / Mild+ | 0.5x / Mild+ / Wide 2 / 16 | Medium / Off | G08 -> 709 | Original | On |
| Neon Fever Dream | 3x | Off | Broad / Strong- | 1.0x / Mild+ / Wide 2 / 16 | Long / LUT C | Off | Original | On |
| Mutara Nebula | 3x | Bright | Broad / Moderate | 1.0x / Moderate / Wide 1 / 8 | Long / LUT A | Off | Original | Off |

Profile Off selects the hard bypass. Custom 1 and Custom 2 use their OSD values
directly and do not inherit fixed-profile settings.
