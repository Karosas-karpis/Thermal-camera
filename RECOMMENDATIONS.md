# Thermal Fusion – Recommendations

Target: Basys3 (XC7A35T), design in `fusion_v/`.

## Current resource use (Vivado report)

| Resource | Used | Available | % |
|---|---|---|---|
| LUT | 1,807 | 20,800 | 8.7 |
| FF | 1,704 | 41,600 | 4.1 |
| BRAM (36 Kb) | 31 | 50 | 62.0 |
| DSP | 5 | 90 | 5.6 |
| I/O | 88 | 106 | 83.0 |
| BUFG | 4 | 32 | 12.5 |
| MMCM | 1 | 5 | 20.0 |

BRAM breakdown (estimate from RTL, matches the report): optical frame ~24, thermal frame ~5,
uart_dump ~3, Sobel line buffers 0-1. ~19 BRAM36 (~684 Kb) free.

## Thermal filter (`thermal_filter.v`)

Already implements a recursive filter `y += (x-y)/4` (k=2), a motion threshold (2 K / 5 K via
`motion_wide`), and `seed` bypass. Values are deci-Kelvin (0.1 K/LSB), 16-bit.

Ranked improvements:
1. **Measure first.** Capture ~100 static frames via `uart_dump`, filter bypassed vs. on. If noise
   is fixed-pattern or already low (MI48 has its own temporal filter, `TEMPORAL_STRENGTH=50`),
   further averaging won't help.
2. **Motion-adaptive k per pixel** (best gain): k=4 when |d| small, k=3 medium, k=2 larger,
   bypass above threshold. Strong smoothing on static areas without ghosting.
3. **Widen stored word to 20 bits** (4 fractional bits) - required for k>=3, otherwise |d| < 4 (k=3)
   or < 8 (k=4) rounds to a zero step and the output stalls. Cost ~+1 BRAM36.
4. **Light 3x3 spatial blur** before upscale (switchable) - cuts noise, softens edges. ~1 BRAM18/LUTRAM.
5. **Per-pixel flat-field offset** - only if step 1 shows fixed-pattern noise. ~5 BRAM36.
6. Raising MI48 `TEMPORAL_STRENGTH` is a free test, but stacks with the FPGA filter (128 ghosted badly).

## OV7670 resolution

Sensor max is VGA 640x480, but a frame at 8 bpp is 2.46 Mb > 1.8 Mb total BRAM - not possible.

| Resolution | 8-bit size | Est. BRAM36 | Fits? |
|---|---|---|---|
| 320x240 (now) | 614 Kb | ~24 | yes |
| 352x288 (CIF) | 811 Kb | ~25-30 | yes |
| 400x300 | 960 Kb | ~30 | yes |
| 480x360 | 1,382 Kb | ~42 | too tight |
| 640x480 | 2,458 Kb | ~67 | no |

Gain is small (thermal is only 80x62). Going up also needs: OV7670 window/scaler regs
(`ov7670_reg.v`), `WIDTH`/`PIXELS`/addr width (`ov7670.v`, `optical_sobel.v`,
`optical_frame_ram.v`), read mapping in `fusion_view.v`, and recalibration of
`fusion_cal.v` (OFF_X/OFF_Y/SCALE) - fusion is only semi-aligned now. Not recommended unless needed.

## OV7670 color / format

Currently QVGA RGB565 (COM7=0x14, COM15=0xD0; RGB555 via switch). Only `{Y[7:2], E[1:0]}`
(8 bits/pixel) is stored; chroma is discarded.

Grayscale/YUV422 does **not** save memory (still 8 bpp) but would:
- drop the RGB-to-luma logic in `optical_sobel` (maybe free some DSPs/LUTs),
- give a true 8-bit sensor Y instead of an approximated luma from RGB565,
- simplify capture (take only the Y byte).

Change: COM7 -> YUV (0x10), TSLB bit 3 for byte order, keep Y byte only.

To actually save BRAM: store 6-bit Y and compute edges at display time (~-6 BRAM36), or 4-bit Y
(~12 BRAM36, visibly posterized). Not needed while ~19 BRAM36 are free.

## Suggested order
1. Noise measurement via `uart_dump`.
2. Adaptive k + 20-bit words in `thermal_filter.v` / `thermal_frame_ram.v`.
3. (Optional) YUV capture for cleaner luma.
4. (Optional) CIF 352x288 + recalibration.
