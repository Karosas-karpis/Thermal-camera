`timescale 1ns / 1ps

// Part 1: Thermal-44 (MI48 + MI0802, 80x62) -> double-buffered BRAM -> VGA grayscale preview.
// Thermal module on Pmod JA (3.3 V power from JA pins 6/12).
//
// LEDs:
//   0      = config_done (MI48 configured and streaming)
//   1      = I2C error seen (NACK/timeout, sticky; init retries automatically)
//   2      = DATA_READY level
//   3      = toggles on every displayed frame
//   4      = SPI frame read in progress (CS low)
//   5      = MI48 nRESET level
//   6      = SPI sync error: DATA_READY fell early (sensor saw extra SCLK edges), sticky
//   7      = SPI sync error: DATA_READY stayed high (sensor missed SCLK edges), sticky
//   8      = last aligned frame passed the header CRC
//   9      = a CRC failure has been seen (sticky)
//   10     = toggles at the end of every SPI read attempt (good or not)
//   with sw[15] on, LEDs 15:8 instead show sw[14] ? FRAME_MODE readback (expect 0x02) : SENXOR_TYPE
//
// Switches:
//   sw[0]     = mirror image horizontally
//   sw[1]     = flip image vertically
//   sw[2]     = fixed 15-40 C grayscale instead of auto range
//   sw[3]     = only display frames that pass the CRC
//   sw[4]     = read 4960 words (no header). Off = 80-word header + 4960 pixels
//   sw[11]    = 7-segment debug page (hex, last read attempt):
//               sw[13:12] 00 word 0 (frame counter), 01 word 1 (SenXor VDD),
//                         10 word 2 (die temperature, 0.1 K), 11 words clocked (13B0 = 5040 expected)
//   sw[13:12] = 7-segment: 00 centre pixel C, 01 frame min C, 10 frame max C, 11 displayed frame count
//   sw[15:14] = LED page select (see above)
//
// btnC = restart MI48 bring-up and clear errors

module top_thermal (
    input         clk,
    input         btnC,
    input  [15:0] sw,
    output [15:0] led,
    output [6:0]  seg,
    output        dp,
    output [3:0]  an,

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
    wire [7:0] sensor_type;
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
        .sensor_type(sensor_type),
        .frame_mode(frame_mode)
    );

    wire        pix_we;
    wire [12:0] pix_addr;
    wire [15:0] pix_data;
    wire        frame_done;
    wire        crc_ok;
    wire [15:0] frame_count;
    wire [15:0] frame_min;
    wire [15:0] frame_max;
    wire [15:0] frame_center;
    wire        sync_early;
    wire        sync_late;
    wire        attempt_done;
    wire [15:0] dbg_word0;
    wire [15:0] dbg_word1;
    wire [15:0] dbg_word2;
    wire [15:0] dbg_words;

    mi48_spi_reader #(
        .SCLK_HALF(SPI_SCLK_HALF)
    ) thermal_capture (
        .clk(clk),
        .reset(reset),
        .enable(config_done),
        .has_header(sw[4] ? 1'b0 : ~frame_mode[5]),
        .data_ready(thermal_drdy),
        .miso(thermal_miso),
        .sclk(thermal_sclk),
        .cs_n(thermal_cs_n),
        .mosi(thermal_mosi),
        .pix_we(pix_we),
        .pix_addr(pix_addr),
        .pix_data(pix_data),
        .frame_done(frame_done),
        .crc_ok(crc_ok),
        .frame_count(frame_count),
        .frame_min(frame_min),
        .frame_max(frame_max),
        .frame_center(frame_center),
        .sync_early(sync_early),
        .sync_late(sync_late),
        .attempt_done(attempt_done),
        .dbg_word0(dbg_word0),
        .dbg_word1(dbg_word1),
        .dbg_word2(dbg_word2),
        .dbg_words(dbg_words)
    );

    reg attempt_toggle = 1'b0;
    always @(posedge clk)
        if (attempt_done)
            attempt_toggle <= ~attempt_toggle;

    // The reader fills one bank while VGA shows the other; swap after each accepted frame.
    wire       frame_accept = frame_done && (crc_ok || !sw[3]);

    reg        frame_valid  = 1'b0;
    reg        frame_toggle = 1'b0;
    reg        disp_bank    = 1'b0;
    reg [15:0] good_frames  = 16'd0;
    reg        crc_ok_last  = 1'b0;
    reg        crc_fail     = 1'b0;
    always @(posedge clk) begin
        if (reset || !config_done) begin
            frame_valid <= 1'b0;
            good_frames <= 16'd0;
            crc_ok_last <= 1'b0;
            crc_fail    <= 1'b0;
        end else begin
            if (frame_done) begin
                crc_ok_last <= crc_ok;
                if (!crc_ok)
                    crc_fail <= 1'b1;
            end
            if (frame_accept) begin
                frame_valid  <= 1'b1;
                frame_toggle <= ~frame_toggle;
                disp_bank    <= ~disp_bank;
                good_frames  <= good_frames + 1'b1;
            end
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
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rgb(vga_rgb)
    );

    assign vgaRed   = vga_rgb[11:8];
    assign vgaGreen = vga_rgb[7:4];
    assign vgaBlue  = vga_rgb[3:0];

    reg [15:0] seg_value;
    always @(*) begin
        case ({sw[11], sw[13:12]})
            3'b000:  seg_value = frame_center;
            3'b001:  seg_value = frame_min;
            3'b010:  seg_value = frame_max;
            3'b011:  seg_value = good_frames;
            3'b100:  seg_value = dbg_word0;
            3'b101:  seg_value = dbg_word1;
            3'b110:  seg_value = dbg_word2;
            default: seg_value = dbg_words;
        endcase
    end

    seg7_display readout (
        .clk(clk),
        .value(seg_value),
        .is_temp(sw[13:12] != 2'd3),
        .is_hex(sw[11]),
        .seg(seg),
        .dp(dp),
        .an(an)
    );

    assign led[0]    = config_done;
    assign led[1]    = i2c_error;
    assign led[2]    = thermal_drdy;
    assign led[3]    = frame_toggle;
    assign led[4]    = ~thermal_cs_n;
    assign led[5]    = thermal_rst_n;
    assign led[6]    = sync_early;
    assign led[7]    = sync_late;
    assign led[15:8] = !sw[15] ? {5'd0, attempt_toggle, crc_fail, crc_ok_last} :
                        sw[14]  ? frame_mode : sensor_type;

endmodule
