# Thermal camera quick reference

Basys 3 + Thermal-44 (MI48 + MI0802, 80x62) on Pmod JA, VGA out. Image is shown 1:1 (80x62), centred on 640x480.

## Switches
| Switch | Function |
|---|---|
| sw[0] | Mirror image horizontally |
| sw[1] | Flip image vertically |
| sw[2] | Fixed range 15.0 to 40.5 C instead of auto range |
| sw[3] | Only show frames that pass the header CRC |
| sw[4] | Bypass the temporal filter (debug) |
| sw[5] | Grayscale instead of colour palette |
| sw[15:9] | Debug: raw SPI word number 0-127 (binary) shown in hex on the 7-segment display; 0-79 header, 80+ pixels |

Other switches are unused. **btnC** restarts MI48 bring-up and clears the sticky error LEDs.

## LEDs
| LED | Meaning |
|---|---|
| 0 | MI48 configured and streaming |
| 1 | I2C error seen (sticky, init retries automatically) |
| 2 | DATA_READY level |
| 3 | Toggles on every displayed frame |
| 4 | SPI frame read in progress (CS low) |
| 5 | MI48 nRESET level |
| 6 | Sync error: DATA_READY fell early (extra SCLK edges), sticky |
| 7 | Sync error: DATA_READY stayed high (missed SCLK edges), sticky |
| 8 | Last frame passed the header CRC |
| 9 | A CRC failure has been seen (sticky) |

## Settings (in `src/`)
| Setting | File | Now | Notes |
|---|---|---|---|
| `SPI_SCLK_HALF` | top_thermal.v | 25 | SCLK = 100 MHz / (2 x value): 25 = 2 MHz, 10 = 5 MHz, 6 = 8.33 MHz |
| `FRAME_RATE_DIV` | top_thermal.v | 4 | MI48 frame rate = max (~25 FPS) / value; 1 = ~25 FPS |
| `HYST` | thermal_view.v | 0.6 K | Auto-range only moves when it changes by more than this |
| `MIN_SPAN` | thermal_view.v | 5 K | Smallest temperature span mapped to the palette |
| `MOTION` | thermal_filter.v | 2 K | Pixel jumps bigger than this skip the temporal filter |

## Data path
MI48 -> `mi48_spi_reader` -> `thermal_filter` (1/4 temporal blend) -> `thermal_frame_ram` (2 banks) -> `thermal_view` (range, palette) -> VGA.
Pixel values are 0.1 K per LSB.

## Debug: raw frames over UART
`uart_dump.v` sends one raw SPI frame (80 header words + 4960 pixels) over the Basys 3 USB-UART (921600 baud, 8N1) about every 110 ms. On the PC:

    python3 tools/dump_frames.py --frames 3 --save frames

Port is `/dev/ttyUSB1` by default (use `--port` if different). It prints the header, pixel range check, CRC guesses for header word 7, and a seam detector that shows a pixel shift as a column number. `--file frames_0.bin` re-analyses a saved frame. `sw[15:9]` also shows a raw word on the 7-segment display.
