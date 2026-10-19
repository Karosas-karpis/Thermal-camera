# OV7670 camera on Basys 3

This Vivado project connects an OV7670 camera to a Basys 3 FPGA and displays the image through the VGA port.

## Current image format

The camera is configured for:

- 320 by 240 pixels
- RGB565 color
- 16 bits per pixel

The frame is stored in dual-port block RAM containing 76800 words of 16 bits. VGA reads the same frame buffer and enlarges each camera pixel to 2 by 2 pixels, producing a 640 by 480 VGA image.

The design currently uses one frame buffer. The camera writes to it while VGA reads from it.

## Camera connections

The camera header is connected across Pmod JB and JC.

### Camera top row

- 3.3V to JC pin 6 or 12
- SCL to JC4
- VS to JC3
- PLK to JC2
- D7 to JC1
- D5 to JB4
- D3 to JB3
- D1 to JB2
- RET to JB1

### Camera bottom row

- GND to JC pin 5 or 11
- SDA to JC10
- HS to JC9
- XLK to JC8
- D6 to JC7
- D4 to JB10
- D2 to JB9
- D0 to JB8
- PWDN to JB7

Use 3.3V only. Pmod pins 5 and 11 are ground. Pins 6 and 12 are 3.3V.

## Main problems

### 1. Camera cable and signal quality

This is the first problem to solve.

The current jumper wires are about 20 cm long. This is too long for a loose parallel camera bus running near 25 MHz. The clock edges are much faster than the clock frequency suggests, so long jumper wires can cause ringing, crosstalk and unstable logic levels.

#### Online reports (OV7670 crosstalk / long wires)

This is a well-documented OV7670 failure mode:

- [01signal: OV7670 capture on Zynq](https://www.01signal.com/xillinux/ov7670-camera-capture/) — keep Dupont jumpers **10 cm or less**, ideally **~5 cm**. Longer wires impair digital signal quality through **crosstalk**. Excessive noise on horizontal sync causes a **jumping video image with green and purple stripes**.
- [01signal: OV7670 SCCB / drive current](https://www.01signal.com/xillinux/ov7670-sccb-control/) — if wires must stay longer, reduce the sensor I/O drive current: write **COM2 (`0x09`) = `0x00`** (1× drive). That can reduce crosstalk-related instability.
- [Circuit Digest: OV7670 with Arduino](https://circuitdigest.com/microcontroller-projects/how-to-use-ov7670-camera-module-with-arduino) — wire length and quality strongly affect picture quality and noise; scrambled/noisy images are often from loose or long jumpers, bad 3.3 V, or wrong registers.
- [ESP32 forum: OV7670 bad images](https://esp32.com/viewtopic.php?t=35883) — reports of garbage images with ~20 cm wiring; impedance mismatch and register setup both suspected.
- Other notes: lines over ~10 cm often worsen quality; twisted pairs or a buffer (e.g. 74HC245) are sometimes suggested; FPGA designs should sample on the correct PCLK edge and treat PCLK carefully as a source-synchronous input.

Typical signs are:

- colored lines and random pixels
- green/purple stripes and a jumping frame (HREF/HSYNC crosstalk)
- an image that changes when the wires are touched
- better or worse results when wires are bundled
- unstable rows or parts of the frame

Recommended fixes:

1. Shorten the wires to about 5 to 10 cm (target ~5 cm).
2. Use more than one ground connection.
3. Run PCLK next to a ground wire.
4. Run XCLK next to a ground wire.
5. Keep clock wires away from D0 through D7 where possible.
6. Add a 100 nF capacitor and a 10 uF capacitor near the camera power pins.
7. Test with a lower camera clock such as 12.5 MHz.
8. If length is unavoidable, set COM2 (`0x09`) to `0x00` for 1× drive current; optionally try small series resistors (~22–33 Ω) on fast lines.

Bundling all signal wires may change the picture, but it is not a reliable solution. It can reduce ringing by accident while also increasing crosstalk.

### 2. One frame buffer

The camera and VGA currently share one frame buffer. The camera may overwrite part of a frame while VGA is displaying it. This causes tearing, jumping and mixed frames.

A later improvement is double buffering:

- camera writes one buffer
- VGA reads the other buffer
- buffers swap only at frame boundaries

The Basys 3 does not have enough block RAM for two 320 by 240 RGB565 frames. Double buffering would require reducing the color depth to RGB332 or reducing the image resolution.

### 3. Camera configuration

The camera is configured through SCCB using SCL and SDA. SCCB defines the ninth clock after each byte as a don't-care bit, not a guaranteed I2C acknowledgement. `config_done` therefore means the complete list was sent; use the internal color bars to verify the camera accepted the configuration.

Set switch 2 before programming the FPGA to select the camera's internal color bars. If color bars are also corrupted, the likely problem is wiring, timing or capture. If color bars are stable but live video has incorrect colors, the sensor/color setup is the more likely problem. If live video only tears, the shared frame buffer is the likely cause.

### 4. Clock and synchronization

The camera pixel clock and the Basys 3 system clock are separate clock domains. Camera data is written using PCLK and VGA data is read using the board clock.

Clock-domain crossings, frame boundaries and BRAM read latency must be handled carefully. Incorrect VSYNC or HREF timing can shift rows or cause the write address to restart at the wrong time.

## Useful tests

1. Check that XCLK reaches the camera.
2. Check that PCLK comes back from the camera.
3. Enable camera color bars and look for stable vertical bars.
4. Unplug HS and confirm HREF activity stops.
5. Unplug VS and confirm VSYNC activity stops.
6. Try the byte-swap switch if the image shape is correct but colors are wrong.
7. Use Vivado ILA to count:
   - one VSYNC pulse per frame
   - 240 HREF pulses per frame
   - 640 camera bytes per active row
   - 76800 completed pixels per frame

## Debug controls

- Switch 0 inverts camera VSYNC interpretation.
- Switch 1 swaps the two RGB565 bytes and should normally remain off.
- Switch 2 selects camera color bars; set it before programming the FPGA.
- LED 0 indicates that the register list was sent.

## Project modules

- `top_module.v` connects the camera, SCCB setup, frame buffer and VGA.
- `ov7670.v` receives two RGB565 bytes per pixel and writes them to BRAM.
- `ov7670_reg.v` contains the camera register list.
- `sccb_init.v` connects the register list to the SCCB sender.
- `i2c_send.v` sends camera register writes.
- `vga_controler.v` generates VGA timing.
- `cam_xclk.xci` generates the camera clock.
- `blk_mem_gen_0.xci` is the 320 by 240 RGB565 frame buffer.
