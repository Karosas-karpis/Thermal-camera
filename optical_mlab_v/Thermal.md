# Waveshare 80x62 Thermal Camera Integration

## Target architecture

```text
OV7670
  -> sccb_init
  -> ov7670 capture @ pclk
  -> 320x240x16 RGB565 BRAM
                           \
                            -> video_compositor -> RGB444 -> VGA
                           /
Thermal-44
  -> thermal_camera @ 100 MHz
       -> i2c_master
       -> spi_master_16
  -> double-buffered 80x62x16 BRAM
  -> thermal_renderer

vga_controller
  -> VGA coordinates and active-video timing
  -> visible and thermal read-address generation
```

Both cameras capture continuously. The view switch changes only the compositor output.

## Source structure

Keep the existing OV7670 modules:

- `top_module.v`
- `ov7670.v`
- `ov7670_reg.v`
- `sccb_init.v`
- `i2c_send.v`
- `vga_controler.v`

Add:

- `thermal_camera.v`
  - Reset and boot sequence
  - MI48 register initialization
  - `DATA_READY` synchronization
  - SPI frame acquisition and parsing
  - Pixel write address and completed-frame signal
- `i2c_master.v`
  - 7-bit addressing
  - Register reads and writes
  - ACK checking
  - Repeated START
  - Open-drain SDA
- `spi_master_16.v`
  - SPI mode 0
  - MSB first
  - 16-bit words
  - Transmit `16'h0000` for every received word
- `thermal_framebuffer.v`
  - Two 4,960-word banks
  - Atomic read/write bank swap
- `thermal_renderer.v`
  - VGA-to-thermal coordinate mapping
  - Temperature normalization
  - Grayscale and colour palette generation
  - Optional X/Y flip
- `video_compositor.v`
  - View selection
  - Optical/thermal alignment
  - Fusion pipeline

Do not reuse `i2c_send.v` for the thermal camera. It is an OV7670 SCCB writer, ignores ACK and cannot read registers.

## Clock domains

| Domain | Logic |
| --- | --- |
| `pclk` | OV7670 capture and visible-BRAM write port |
| `clk` 100 MHz | Thermal control, SPI, thermal writes, VGA reads, rendering and composition |
| `xclk` | Clock output to OV7670 |

- Keep the visible framebuffer dual-port: write on `pclk`, read on `clk`.
- Synchronize `DATA_READY` through two flip-flops before edge detection.
- Thermal SPI and both thermal BRAM ports can remain in the 100 MHz domain.
- Swap thermal banks only after the complete frame has been received.
- Keep the existing asynchronous clock-group constraint between `pclk` and `clk`.

## Proposed JA wiring

JB and JC remain dedicated to the OV7670.

| Thermal signal | Top-level port | JA pin | FPGA pin | Direction |
| --- | --- | --- | --- | --- |
| nRESET | `thermal_reset_n` | JA1 | J1 | Output |
| DATA_READY | `thermal_ready` | JA2 | L2 | Input |
| SDA | `thermal_sda` | JA3 | J2 | Inout |
| SCL | `thermal_scl` | JA4 | G2 | Output/open-drain |
| SS | `thermal_ss_n` | JA7 | H1 | Output |
| CLK | `thermal_sclk` | JA8 | K2 | Output |
| MISO | `thermal_miso` | JA9 | H2 | Input |
| MOSI | `thermal_mosi` | JA10 | G3 | Output |

Use JA5/JA11 for ground and JA6/JA12 for 3.3 V. Verify the breakout connector order before wiring. All constrained FPGA signals use `LVCMOS33`.

Safe FPGA startup levels:

- `thermal_reset_n = 0`
- `thermal_ss_n = 1`
- `thermal_sclk = 0`
- `thermal_mosi = 0`
- SDA and SCL released

## MI48 startup and configuration

- Default 7-bit I2C address: `0x40`.
- Use an I2C rate no faster than standard mode, nominally 100 kHz.
- Hold nRESET low for at least 32 us.
- After releasing reset, poll `STATUS` (`0xB6`) bit 5 until `BOOTING_UP = 0`.
- Normal startup can take 0.5 s; first startup with a newly detected sensor can take 2 s.
- Read and retain for debugging:
  - `FW_VERSION_1` (`0xB2`)
  - `FW_VERSION_2` (`0xB3`)
  - `STATUS` (`0xB6`)
  - `SENXOR_TYPE` (`0xBA`)
- Write `FRAME_RATE` (`0xB4`) = `0x00` for maximum frame rate.
- Write `FRAME_MODE` (`0xB1`) = `0x02` for continuous full-frame capture with the header enabled.
- Leave sleep disabled.
- Check `STATUS` bits 1 through 3 after failures:
  - Readout too slow
  - Sensor-interface error
  - Capture error

Retain the header during bring-up. It provides a frame counter, measured supply, die temperature, timestamp, frame minimum/maximum and CRC. Header-free continuous operation can later use `FRAME_MODE = 0x22`.

## SPI acquisition

- Mode 0, 16-bit words, MSB first.
- Start with a 5 MHz SPI clock; 10 MHz is a later option.
- At 25 FPS, a header-enabled frame requires about 2.016 Mbit/s before transaction overhead.
- `DATA_READY` remains high until the complete thermal frame is read.
- Keep SS low for the complete frame initially.

Header-enabled frame:

```text
Words 0..79       80-word header
Words 80..5039    4,960 temperature pixels
```

Relevant header words:

```text
0        frame counter
1        sensor VDD, 0.0001 V units
2        sensor die temperature, 0.01 K units
3..4     timestamp
5        maximum pixel value, 0.1 K units
6        minimum pixel value, 0.1 K units
7        CRC-16/CCITT-FALSE
```

Pixel data is unsigned 16-bit temperature in 0.1 K units. For example, `3009` means `300.9 K`.

CRC parameters:

```text
width   = 16
poly    = 0x1021
init    = 0xFFFF
refin   = false
refout  = false
xorout  = 0x0000
```

Calculate CRC over the 4,960 pixel words only. Allow CRC checking to be disabled during initial SPI bring-up, but retain frame-length and frame-counter checks.

## Thermal framebuffer

Logical organization:

```text
bank 0: addresses 0..4959
bank 1: addresses 4960..9919
```

Capture sequence:

1. Wait for synchronized rising `DATA_READY`.
2. Read 80 header words.
3. Read 4,960 pixel words into `write_bank`.
4. Verify word count and optionally CRC.
5. Publish `write_bank` as `read_bank`.
6. Toggle `write_bank`.

Do not change `read_bank` during active frame capture. Prefer swapping at the next VGA frame boundary to prevent the displayed thermal image changing partway through a VGA frame.

## VGA and rendering

Current VGA output is 640x480 at approximately 60 Hz. Camera frame rates remain independent; VGA repeatedly displays the latest complete camera frames.

Basic source coordinates:

```text
visible_x = vga_x >> 1
visible_y = vga_y >> 1

thermal_x = vga_x >> 3
thermal_y = floor(vga_y * 62 / 480)
thermal_address = thermal_y * 80 + thermal_x
```

Implement `thermal_y` with a 480-entry ROM or a line accumulator. Avoid a general runtime divider.

Initial fixed display range:

```text
20 C = approximately 2932
40 C = approximately 3132
delta = clamp(pixel - 2932, 0, 200)
intensity = delta * 255 / 200
```

Use fixed-point multiplication or a lookup table. Keep a fixed range initially; per-frame min/max causes visible palette pumping. A slowly filtered range can be added later.

Renderer outputs:

- `thermal_gray_rgb`
- `thermal_palette_rgb`
- `thermal_valid`

Pipeline BRAM read, normalization and palette lookup. Delay VGA coordinates, `video_on`, `hsync` and `vsync` by the identical pipeline latency.

## View selection and fusion

Use:

```text
sw[4:3]
00 = OV7670
01 = thermal grayscale
10 = thermal colour
11 = fused
```

For fused mode, use the thermal field of view as the output reference. Map each output position to:

- One interpolated thermal coordinate
- One calibrated OV7670 coordinate

Start with configurable optical scale and X/Y offsets. Replace with an affine mapping after calibration.

First fusion implementation:

```text
fused = 75% thermal + 25% optical luminance
```

Preferred later implementation:

```text
optical_detail = optical_luma - low_pass_optical_luma
fused_luma = clamp(thermal_luma + detail_gain * optical_detail)
```

For colour thermal, apply optical detail as a brightness adjustment to the palette result instead of replacing the thermal colour.

## Changes to existing modules

### `top_module.v`

- Add the eight thermal ports.
- Instantiate thermal acquisition, framebuffer, renderer and compositor.
- Keep OV7670 and thermal capture enabled in every display mode.
- Route only the compositor output to VGA.
- Add thermal status LEDs.

### `vga_controler.v`

Replace the generated `w_25MHz` clock usage with a clock-enable inside `always @(posedge clk_100MHz)`. Keep all VGA and rendering logic in the 100 MHz domain and advance VGA counters only when `pixel_ce` is asserted.

### Visible framebuffer

Retain the existing 320x240x16 framebuffer initially. Its single-buffer tearing remains independent of the thermal path. Do not combine visible and thermal data into one BRAM.

## Suggested status LEDs

```text
led[0]   OV7670 configuration complete
led[7]   thermal boot complete
led[8]   synchronized DATA_READY
led[9]   thermal SPI busy
led[10]  toggles after each valid thermal frame
led[11]  thermal I2C/SPI/status error
led[12]  thermal CRC error
```

## Bring-up order

1. Refactor VGA timing to use a clock-enable and verify the existing OV7670 display.
2. Add JA constraints and safe thermal output defaults.
3. Verify reset timing and read `STATUS`, firmware version and sensor type over I2C.
4. Enable continuous capture and observe `DATA_READY`.
5. Read the 80-word header only; verify that the frame counter increments.
6. Read all 5,040 words and verify `DATA_READY` returns low.
7. Store and display one thermal bank in fixed-range grayscale.
8. Enable double buffering and VGA-boundary bank swaps.
9. Add the colour palette and view selector.
10. Add optical alignment and fusion.

## Verification targets

- I2C ACK received for every address/register/data byte.
- `STATUS.BOOTING_UP` clears before configuration writes.
- SPI receives exactly 5,040 words per header-enabled frame.
- Header frame counter increments by one.
- `DATA_READY` clears only after the final SPI word.
- No thermal writes target the displayed bank.
- VGA reads stay within `0..4959`.
- Thermal output updates near 25 FPS while VGA remains 60 Hz.
- Vivado timing passes for `clk`, `pclk` and the SPI-generated output timing.
- Final BRAM utilization remains within the Basys 3 device capacity.

## References

- Waveshare Thermal Camera HAT documentation: https://www.waveshare.com/wiki/Thermal_Camera_HAT
- MI48x3 datasheet: https://files.waveshare.com/wiki/Thermal_Camera_Module/MI48x3--Datasheet--v3.1.3..pdf
