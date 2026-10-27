`timescale 1ns / 1ps

// Part 1: Thermal-44 (MI48 + MI0802, 80x62) -> double-buffered BRAM -> VGA colour preview.
// Thermal module on Pmod JA (3.3 V power from JA pins 6/12).
//
// LEDs:
//   0 = config_done (MI48 configured and streaming)
//   1 = I2C error seen (NACK/timeout, sticky; init retries automatically)
//   2 = DATA_READY level
//   3 = toggles on every displayed frame
//   4 = SPI frame read in progress (CS low)
//   5 = MI48 nRESET level
//   6 = SPI sync error: DATA_READY fell early (sensor saw extra SCLK edges), sticky
//   7 = SPI sync error: DATA_READY stayed high (sensor missed SCLK edges), sticky
//
// Switches:
//   sw[0] = mirror image horizontally
//   sw[1] = flip image vertically
//   sw[2] = fixed 15-40 C range instead of auto range
//   sw[5] = grayscale instead of colour palette
//
// btnC = restart MI48 bring-up and clear errors

module top_thermal (
    input         clk,
    input         btnC,
    input  [15:0] sw,
    output [7:0]  led,

    output        hsync,
    output        vsync,
    output [3:0]  vgaRed,
    output [3:0]  vgaGreen,
    output [3:0]  vgaBlue,

    output        thermal_sclk,
    output        thermal_mosi,
    input         thermal_miso,
    output        thermal_cs_n,
    inout         thermal_scl,
    inout         thermal_sda,
    output        thermal_rst_n,
    input         thermal_drdy
);

    // 2 MHz SCLK: a frame (5040 words) takes ~40 ms, so the MI48 is slowed to
    // FPS_MAX / 4 (~6 FPS) to leave plenty of time between frames.
    localparam integer SPI_SCLK_HALF  = 25;
    localparam [7:0]   FRAME_RATE_DIV = 8'd4;

    reg [1:0] btn_sync = 2'b00;
    always @(posedge clk) btn_sync <= {btn_sync[0], btnC};
    wire reset = btn_sync[1];

    wire       config_done;
    wire       i2c_error;
    wire [7:0] frame_mode;

    mi48_ctrl #(
        .FRAME_RATE_DIV(FRAME_RATE_DIV)
    ) thermal_setup (
        .clk(clk),
        .reset(reset),
        .thermal_rst_n(thermal_rst_n),
        .scl(thermal_scl),
        .sda(thermal_sda),
        .config_done(config_done),
        .i2c_error(i2c_error),
        .frame_mode(frame_mode)
    );

    wire        pix_we;
    wire [12:0] pix_addr;
    wire [15:0] pix_data;
    wire        frame_done;
    wire [15:0] frame_min;
    wire [15:0] frame_max;
    wire        sync_early;
    wire        sync_late;

    mi48_spi_reader #(
        .SCLK_HALF(SPI_SCLK_HALF)
    ) thermal_capture (
        .clk(clk),
        .reset(reset),
        .enable(config_done),
        .has_header(~frame_mode[5]),
        .data_ready(thermal_drdy),
        .miso(thermal_miso),
        .sclk(thermal_sclk),
        .cs_n(thermal_cs_n),
        .mosi(thermal_mosi),
        .pix_we(pix_we),
        .pix_addr(pix_addr),
        .pix_data(pix_data),
        .frame_done(frame_done),
        .crc_ok(),
        .frame_count(),
        .frame_min(frame_min),
        .frame_max(frame_max),
        .frame_center(),
        .sync_early(sync_early),
        .sync_late(sync_late)
    );

    // The reader fills one bank while VGA shows the other; swap after each frame.
    reg        frame_valid  = 1'b0;
    reg        frame_toggle = 1'b0;
    reg        disp_bank    = 1'b0;
    always @(posedge clk) begin
        if (reset || !config_done)
            frame_valid <= 1'b0;
        else if (frame_done) begin
            frame_valid  <= 1'b1;
            frame_toggle <= ~frame_toggle;
            disp_bank    <= ~disp_bank;
        end
    end

    wire       video_on;
    wire [9:0] vga_x;
    wire [9:0] vga_y;

    vga_controller vga_c (
        .clk_100MHz(clk),
        .reset(1'b0),
        .hsync(hsync),
        .vsync(vsync),
        .video_on(video_on),
        .p_tick(),
        .x(vga_x),
        .y(vga_y)
    );

    wire [12:0] rd_addr;
    wire [15:0] rd_data;

    thermal_frame_ram thermal_buf (
        .clk_a(clk),
        .we_a(pix_we),
        .wr_bank(~disp_bank),
        .addr_a(pix_addr),
        .din_a(pix_data),
        .clk_b(clk),
        .rd_bank(disp_bank),
        .addr_b(rd_addr),
        .dout_b(rd_data)
    );

    wire [11:0] vga_rgb;

    thermal_view preview (
        .clk(clk),
        .x(vga_x),
        .y(vga_y),
        .video_on(video_on),
        .frame_valid(frame_valid),
        .t_min(frame_min),
        .t_max(frame_max),
        .mirror_x(sw[0]),
        .flip_y(sw[1]),
        .fixed_range(sw[2]),
        .gray(sw[5]),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rgb(vga_rgb)
    );

    assign vgaRed   = vga_rgb[11:8];
    assign vgaGreen = vga_rgb[7:4];
    assign vgaBlue  = vga_rgb[3:0];

    assign led[0] = config_done;
    assign led[1] = i2c_error;
    assign led[2] = thermal_drdy;
    assign led[3] = frame_toggle;
    assign led[4] = ~thermal_cs_n;
    assign led[5] = thermal_rst_n;
    assign led[6] = sync_early;
    assign led[7] = sync_late;

endmodule
