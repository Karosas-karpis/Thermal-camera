# Fusion quick reference

Sources were copied from `thermal_v` and `optical_mlab_v`. `ov7670.v` gained `wr_col` / `wr_row` outputs for the Sobel line buffers. `top_fusion.v` replaces both old tops, and `fusion_view.v` replaces `thermal_view.v`.

## Build

```bash
~/vivado/Vivado/2024.2/bin/vivado -mode batch -nojournal -nolog -source fusion_v/scripts/create_project.tcl -tclargs build
```

The project goes in `fusion_v/vivado/` (not tracked by git). The bitstream is `fusion_v/vivado/fusion_v.runs/impl_1/top_fusion.bit`.

## Wiring

| Camera | Pmod |
|---|---|
| Thermal-44 | JA |
| OV7670 | JB + JC |

## Switches

| Switch | Function |
|---|---|
| sw[0] | Mirror thermal horizontally (default is turned 180°) |
| sw[1] | Flip thermal vertically |
| sw[2] | Fixed range 15.0 to 40.5 C instead of auto range |
| sw[3] | Only show frames that pass the header CRC (currently never: leave off, see LEDs) |
| sw[4] | Bypass the temporal filter (debug) |
| sw[5] | Thermal grayscale instead of colour palette |
| sw[7:6] | View: 0 thermal, 1 optical, 2 thermal + edges, 3 optical + hot colour |
| sw[8] | Buttons: 0 = move, 1 = zoom and edge threshold |
| sw[9] | MI48 temporal filter (built into the sensor, 0xD0 bits 0+1, strength 0xD1-0xD2) |
| sw[10] | MI48 rolling average, 4 frames (0xD0 bit 2) |
| sw[11] | MI48 median filter 3x3 (0xD0 bit 6) |
| sw[12] | MI48 median filter 5x5 (0xD0 bits 5+6) |
| sw[13] | 7-segment shows the MI48 firmware version |
| sw[14] | FPGA temporal filter: motion threshold 5 K instead of 2 K (less speckle, more trailing on small changes) |
| sw[15] | Unused |

sw[9]-sw[12] are only read during MI48 bring-up: set them, then press btnC. With all four off, no filter registers are written and the MI48 setup is the same as before filter support. The register layout is from the MI48Dx datasheet v4.0.5 and matches the board's firmware 3.2.13 (sw[13] shows 320D). With the temporal filter on, streaming starts 100 ms later while the sensor initialises the filter. If LED 1, 6 or 7 comes on with a filter enabled, switch it off and press btnC. With the sensor's temporal filter on, also turn on sw[4] to bypass the FPGA's own temporal filter, so the two don't add lag on top of each other.

## Buttons

| Button | sw[8] = 0 | sw[8] = 1 |
|---|---|---|
| U / D | Move thermal up / down | Zoom thermal in / out |
| L / R | Move thermal left / right | Lower / raise edge threshold |
| C | Restart MI48, clear errors, reset alignment | Same |

The OV7670 is mounted turned 90° clockwise, so its frame is shown flipped vertically (read address in `fusion_view.v`). The optical image always fills the screen (320x240 at 2x); the thermal image is zoomed and moved onto it, with black outside the thermal frame. The thermal image is turned 180° in `top_fusion.v`; sw[0] / sw[1] mirror or flip it from there.

Held buttons repeat at about 12 Hz. The 7-segment shows `off_x off_y` with sw[8] = 0 and `scale thr` with sw[8] = 1, all in hex. Defaults (board alignment from 2026-11-09, display `660A` / `732D`): thermal offsets -154 / 10 (in 1/8 thermal pixel), thermal zoom `73` (115, 128 = 8x, larger = smaller image, zooms around the screen centre) and threshold `2D` (45). The display shows only the low 8 bits of each offset, so -154 shows as `66`.

## LEDs

| LED | Meaning |
|---|---|
| 0-9 | Thermal, same as Part 1 |
| 10 | OV7670 configured |
| 11 | SCCB NACK seen (sticky) |
| 12 | PCLK heartbeat |
| 13 | Toggles on camera VSYNC edges |
| 14 | Toggles on camera HREF edges |
| 15 | Toggles on optical pixel writes |

LED 8 stays off and LED 9 comes on: the reader's CRC covers the 8 lead words, which belong to the previous frame. The frame's own last 8 pixels only arrive with the next read, so the check can't pass yet. A UART dump showed the link itself is clean (CRC matches when checked across two reads).

## Alignment

1. Set view 2 (sw[7:6] = 2) and point both cameras at something warm with a sharp outline.
2. Set sw[0] and sw[1] so the thermal image has the same orientation as the optical image.
3. With sw[8] = 1, use U/D to match the size. Then with sw[8] = 0, use the buttons to line up the edges.
4. With sw[8] = 1, use L/R to raise the threshold until the camera noise disappears from the edges.

The settings reset on btnC and when the FPGA is reprogrammed. Note the working values and set `OFF_X_INIT`, `OFF_Y_INIT`, `SCALE_INIT` and `THR_INIT` in `fusion_cal.v`.

## Simulation

`sim/tb_fusion.v` runs a synthetic optical frame through capture and Sobel, loads a synthetic thermal frame, and writes one VGA frame per view to `view_<mode>.hex`. It does not cover the camera bring-up, `top_fusion` or `fusion_cal`.
