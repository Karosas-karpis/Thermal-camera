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

Typical signs are:

- colored lines and random pixels
- an image that changes when the wires are touched
- better or worse results when wires are bundled
- unstable rows or parts of the frame

Recommended fixes:

1. Shorten the wires to about 5 to 10 cm.
2. Use more than one ground connection.
3. Run PCLK next to a ground wire.
4. Run XCLK next to a ground wire.
5. Keep clock wires away from D0 through D7 where possible.
6. Add a 100 nF capacitor and a 10 uF capacitor near the camera power pins.
7. Test with a lower camera clock such as 12.5 MHz.

Bundling all signal wires may change the picture, but it is not a reliable solution. It can reduce ringing by accident while also increasing crosstalk.

### 2. One frame buffer

The camera and VGA currently share one frame buffer. The camera may overwrite part of a frame while VGA is displaying it. This causes tearing, jumping and mixed frames.

A later improvement is double buffering:

- camera writes one buffer
- VGA reads the other buffer
- buffers swap only at frame boundaries

The Basys 3 does not have enough block RAM for two 320 by 240 RGB565 frames. Double buffering would require reducing the color depth to RGB332 or reducing the image resolution.

### 3. Camera configuration

The camera is configured through SCCB using SCL and SDA. The current sender does not properly report camera acknowledgement, so `config_done` only means that all commands were sent. It does not prove that the camera accepted them.

The camera color-bar mode is useful for testing. If color bars are also corrupted, the likely problem is wiring, timing or capture. If color bars are stable but live video tears, frame buffering is the more likely problem.

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

## Project modules

- `top_module.v` connects the camera, SCCB setup, frame buffer and VGA.
- `ov7670.v` receives two RGB565 bytes per pixel and writes them to BRAM.
- `ov7670_reg.v` contains the camera register list.
- `sccb_init.v` connects the register list to the SCCB sender.
- `i2c_send.v` sends camera register writes.
- `vga_controler.v` generates VGA timing.
- `cam_xclk.xci` generates the camera clock.
- `blk_mem_gen_0.xci` is the 320 by 240 RGB565 frame buffer.
