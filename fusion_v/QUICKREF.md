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
| sw[0] | Mirror thermal horizontally |
| sw[1] | Flip thermal vertically |
| sw[2] | Fixed range 15.0 to 40.5 C instead of auto range |
| sw[3] | Only show frames that pass the header CRC |
| sw[4] | Bypass the temporal filter (debug) |
| sw[5] | Thermal grayscale instead of colour palette |
| sw[7:6] | View: 0 thermal, 1 optical, 2 thermal + edges, 3 optical + hot colour |
| sw[8] | Buttons: 0 = move, 1 = zoom and edge threshold |
| sw[15:9] | 0 = 7-segment shows alignment; otherwise the raw SPI word number, shown in hex |

## Buttons

| Button | sw[8] = 0 | sw[8] = 1 |
|---|---|---|
| U / D | Move optical up / down | Zoom optical in / out |
| L / R | Move optical left / right | Lower / raise edge threshold |
| C | Restart MI48, clear errors, reset alignment | Same |

Held buttons repeat at about 12 Hz. The 7-segment shows `off_x off_y` with sw[8] = 0 and `scale thr` with sw[8] = 1, all in hex. Defaults are offsets 0, scale `80` (128) and threshold `30` (48).

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

## Alignment

1. Set view 2 (sw[7:6] = 2) and point both cameras at something warm with a sharp outline.
2. Set sw[0] and sw[1] so the thermal image has the same orientation as the optical image.
3. With sw[8] = 1, use U/D to match the size. Then with sw[8] = 0, use the buttons to line up the edges.
4. With sw[8] = 1, use L/R to raise the threshold until the camera noise disappears from the edges.

The settings reset on btnC and when the FPGA is reprogrammed. Note the working values and set `SCALE_INIT` and `THR_INIT` in `fusion_cal.v`. The offsets have no init parameter yet.

## Simulation

`sim/tb_fusion.v` runs a synthetic optical frame through capture and Sobel, loads a synthetic thermal frame, and writes one VGA frame per view to `view_<mode>.hex`. It does not cover the camera bring-up, `top_fusion` or `fusion_cal`.
