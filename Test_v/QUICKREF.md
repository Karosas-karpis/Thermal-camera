# Fusion quick reference

Sources were copied from `thermal_v` and `optical_mlab_v`. `ov7670.v` gained `wr_col` / `wr_row` outputs for the Sobel line buffers. `top_fusion.v` replaces both old tops, and `fusion_view.v` replaces `thermal_view.v`.

`Test_v` is a copy of `clean_v` (the tidied `fusion_v`) with three changes:

- `thermal_filter.v` has one more register stage (the RAM output is registered before the blend), for timing margin.
- A new thermal frame and its colour range are swapped in at the start of VGA vertical blanking instead of mid-screen.
- btnC keeps the alignment unless sw[15] is on.
- sw[3] turns on a 2x2 ordered dither in `fusion_view.v`.
- A box marks the hottest thermal pixel, with its temperature next to it (`thermal_hotspot.v`, `marker_text.v`).
- The reader's header CRC check is removed, with LEDs 8-9. It could never pass (see LEDs).

## Features

Thermal camera (Thermal-44 / MI48, 80x62):

- Automatic bring-up over I2C: reset, boot wait, frame rate, stream mode. A NACK or timeout restarts it.
- SPI readout at 8.33 MHz, about 12.5 frames per second.
- Detects a misaligned read (DATA_READY falling early or late) and drops that frame.
- Sensor's own filters selectable on switches: temporal, rolling average, median 3x3 or 5x5.
- FPGA temporal filter: each pixel moves 1/4 of the way to the new sample; a change above 2 K (or 5 K) is taken at once so moving objects leave no trail. Can be bypassed.
- Two frame buffers; a new frame is swapped in during VGA vertical blanking, so the picture never tears.
- Bilinear upscale to the 640x480 screen, with zoom, offset, mirror and flip.
- Colour range: automatic from the frame's min/max (smoothed, 0.6 K hysteresis, at least 5 K wide) or fixed 15.0 to 40.5 C.
- 64-level heat palette or grayscale.

Optical camera (OV7670, 320x240):

- Automatic register setup over SCCB (RGB565, QVGA).
- Brightness (luma) and Sobel edge detection done as pixels arrive; edges in three strengths with an adjustable threshold.
- One 8-bit frame buffer (6-bit luma + 2-bit edge strength), shown at 2x.

Fusion and display:

- Four views: thermal, optical grayscale, thermal with optical edges on top, optical with palette colour on hot areas.
- Edge overlay is bright on cold areas and dark on hot areas, so it stays visible.
- Alignment of the thermal image onto the optical one with the buttons (move, zoom), shown on the 7-segment display. btnC keeps it unless sw[15] is on.
- Hot-spot marker: a box around the hottest thermal pixel with its temperature in Celsius (see Marker). Not shown in view 1.
- VGA 640x480 at 60 Hz, 12-bit colour, with optional 2x2 dither (sw[3]).

Debug:

- 16 status LEDs for both cameras.
- Raw thermal frames to the PC over the USB-UART at 921600 baud (`tools/dump_frames.py`).
- MI48 firmware version on the 7-segment display (sw[13]).
- Testbenches for thermal capture, the hot-spot tracker and the fused views.

Not included:

- No CRC check on thermal frames in the FPGA (`dump_frames.py` checks it on the PC).
- The optical image has a single buffer and can tear on fast movement.
- Alignment settings are not saved; they go back to the defaults in `fusion_cal.v` when the FPGA is reprogrammed.
- btnC does not restart the OV7670 setup.

## Build

```bash
~/vivado/Vivado/2024.2/bin/vivado -mode batch -nojournal -nolog -source Test_v/scripts/create_project.tcl -tclargs build
```

The project goes in `Test_v/vivado/` (not tracked by git). The bitstream is `Test_v/vivado/Test_v.runs/impl_1/top_fusion.bit`.

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
| sw[3] | Dither to the 4-bit VGA output: smoother optical and thermal shading (compare on and off on your monitor) |
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
| sw[15] | btnC also resets the alignment (off: btnC keeps it) |

sw[9]-sw[12] are only read during MI48 bring-up: set them, then press btnC (the alignment is kept while sw[15] is off). With all four off, no filter registers are written and the MI48 setup is the same as before filter support. The register layout is from the MI48Dx datasheet v4.0.5 and matches the board's firmware 3.2.13 (sw[13] shows 320D). With the temporal filter on, streaming starts 100 ms later while the sensor initialises the filter. If LED 1, 6 or 7 comes on with a filter enabled, switch it off and press btnC. With the sensor's temporal filter on, also turn on sw[4] to bypass the FPGA's own temporal filter, so the two don't add lag on top of each other.

## Buttons

| Button | sw[8] = 0 | sw[8] = 1 |
|---|---|---|
| U / D | Move thermal up / down | Zoom thermal in / out |
| L / R | Move thermal left / right | Lower / raise edge threshold |
| C | Restart MI48 and clear errors; with sw[15] on also reset the alignment | Same |

The OV7670 is mounted turned 90° clockwise, so its frame is shown flipped vertically (read address in `fusion_view.v`). The optical image always fills the screen (320x240 at 2x); the thermal image is zoomed and moved onto it, with black outside the thermal frame. The thermal image is turned 180° in `top_fusion.v`; sw[0] / sw[1] mirror or flip it from there.

Held buttons repeat at about 12 Hz. The 7-segment shows `off_x off_y` with sw[8] = 0 and `scale thr` with sw[8] = 1, all in hex. Defaults: thermal offsets 0 / 0 (in 1/8 thermal pixel), thermal zoom `90` (144, 128 = 8x, larger = smaller image, zooms around the screen centre) and threshold `2D` (45). The display shows only the low 8 bits of each offset.

## LEDs

| LED | Meaning |
|---|---|
| 0-9 | Thermal: see the LED list at the top of `top_fusion.v` |
| 10 | OV7670 configured |
| 11 | SCCB NACK seen (sticky) |
| 12 | PCLK heartbeat |
| 13 | Toggles on camera VSYNC edges |
| 14 | Toggles on camera HREF edges |
| 15 | Toggles on optical pixel writes |

LEDs 8 and 9 are unused and stay off. The reader no longer checks the header CRC: the CRC covers a frame's own pixels, and its last 8 only arrive with the next read, so a check inside one read can't pass. `tools/dump_frames.py` checks it across two reads; a UART dump showed the link is clean.

## Marker

A black and white box, 3 thermal pixels across, sits on the hottest pixel of the filtered thermal image, with the temperature above it (below it near the top of the screen). It is shown in views 0, 2 and 3 and follows the thermal zoom, offset, mirror and flip.

- The box and the reading change once every 12 thermal frames, about once a second.
- The reading is that pixel averaged over the 12 frames, in Celsius with one decimal.
- The box only moves when another pixel is more than 1.0 K hotter than the box pixel in the last of the 12 frames. Right after a move the reading is that single frame's value; from the next update it is the average.
- After btnC the first complete frame places the box.
- There is no switch for it: all 16 are in use. `FRAMES` and `MARGIN` are parameters of `thermal_hotspot.v`.

The reading is the sensor's own value for one pixel. With sw[4] on (FPGA filter bypassed) the hottest pixel is picked from unfiltered frames and the box moves more.

## Alignment

1. Set view 2 (sw[7:6] = 2) and point both cameras at something warm with a sharp outline.
2. Set sw[0] and sw[1] so the thermal image has the same orientation as the optical image.
3. With sw[8] = 1, use U/D to match the size. Then with sw[8] = 0, use the buttons to line up the edges.
4. With sw[8] = 1, use L/R to raise the threshold until the camera noise disappears from the edges.

The settings reset on btnC with sw[15] on, and when the FPGA is reprogrammed. Note the working values and set `OFF_X_INIT`, `OFF_Y_INIT`, `SCALE_INIT` and `THR_INIT` in `fusion_cal.v`.

## Simulation

`sim/tb_hotspot.v` checks the hot-spot tracker (first frame, 12-frame average, margin, move, negative temperatures). `sim/tb_fusion.v` runs a synthetic optical frame through capture and Sobel, loads a synthetic thermal frame, and writes one VGA frame per view to `view_<mode>.hex`. Its `DITHER` and `MARKER` parameters turn those on for the written views. It does not cover the camera bring-up, `top_fusion` or `fusion_cal`.
