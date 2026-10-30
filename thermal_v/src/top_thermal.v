`timescale 1ns / 1ps

// Part 1: Thermal-44 (MI48 + MI0802, 80x62) -> temporal filter -> double-buffered BRAM -> VGA colour preview.
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
//   8 = last frame passed the header CRC
//   9 = a CRC failure has been seen (sticky)
//
// Switches:
//   sw[0] = mirror image horizontally
//   sw[1] = flip image vertically
//   sw[2] = fixed 15-40 C range instead of auto range
//   sw[3] = only display frames that pass the header CRC
//   sw[5] = grayscale instead of colour palette
//   sw[15:9] = word number 0-127 of the raw SPI frame shown in hex on the 7-segment display
//              (0-79 header, 80+ pixels; values ~2800-3200 are room temperature)
//   sw[4] = bypass the temporal filter (debug: raw frames straight to the RAM)
//
// btnC = restart MI48 bring-up and clear errors

module top_thermal (
    input         clk,
    input         btnC,
    input  [15:0] sw,
    output [9:0]  led,
    output [6:0]  seg,
    output        dp,
    output [3:0]  an,
    output        uart_tx,

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
    // Faster: SPI_SCLK_HALF 6 (8.33 MHz) with FRAME_RATE_DIV 1 (~25 FPS).
    // The MI48 frame is still 5040 words, but starts with 9 pixel-like words before the
    // 80-word header (seen with tools/dump_frames.py); the reader stores them as the last 9 pixels.
    localparam integer SPI_LEAD_WORDS = 9;
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

    wire        raw_we;
    wire [13:0] raw_idx;
    wire [15:0] raw_word;
    wire        pix_we;
    wire [12:0] pix_addr;
    wire [15:0] pix_data;
    wire        frame_done;
    wire        crc_ok;
    wire        sync_early;
    wire        sync_late;

    mi48_spi_reader #(
        .SCLK_HALF(SPI_SCLK_HALF),
        .LEAD_WORDS(SPI_LEAD_WORDS)
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
        .crc_ok(crc_ok),
        .frame_count(),
        .frame_min(),
        .frame_max(),
        .frame_center(),
        .raw_we(raw_we),
        .raw_idx(raw_idx),
        .raw_word(raw_word),
        .sync_early(sync_early),
        .sync_late(sync_late)
    );

    // The reader fills one bank while VGA shows the other; swap after each
    // accepted frame. With sw[3] on, a frame that fails the CRC is not shown.
    wire       frame_accept = frame_done && (crc_ok || !sw[3]);

    reg        frame_valid  = 1'b0;
    reg        frame_toggle = 1'b0;
    reg        disp_bank    = 1'b0;
    reg        crc_ok_last  = 1'b0;
    reg        crc_fail     = 1'b0;
    always @(posedge clk) begin
        if (reset || !config_done) begin
            frame_valid <= 1'b0;
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

    // Temporal filter on RAM port A: reads the displayed bank, writes the fill bank.
    wire        ram_we;
    wire        ram_bank;
    wire [12:0] ram_addr;
    wire [15:0] ram_din;
    wire [15:0] ram_dout;
    wire [15:0] frame_min;
    wire [15:0] frame_max;

    thermal_filter filt (
        .clk(clk),
        .seed(~frame_valid || sw[4]),
        .disp_bank(disp_bank),
        .wr_bank(~disp_bank),
        .frame_done(frame_done),
        .pix_we(pix_we),
        .pix_addr(pix_addr),
        .pix_data(pix_data),
        .a_we(ram_we),
        .a_bank(ram_bank),
        .a_addr(ram_addr),
        .a_din(ram_din),
        .a_dout(ram_dout),
        .frame_min(frame_min),
        .frame_max(frame_max)
    );

    thermal_frame_ram thermal_buf (
        .clk(clk),
        .we_a(ram_we),
        .bank_a(ram_bank),
        .addr_a(ram_addr),
        .din_a(ram_din),
        .dout_a(ram_dout),
        .rd_bank(disp_bank),
        .addr_b(rd_addr),
        .dout_b(rd_data)
    );

    // frame_min / frame_max are latched on frame_done, so the view takes them a cycle later
    reg new_frame = 1'b0;
    always @(posedge clk)
        new_frame <= frame_accept;

    wire [11:0] vga_rgb;

    thermal_view preview (
        .clk(clk),
        .x(vga_x),
        .y(vga_y),
        .video_on(video_on),
        .frame_valid(frame_valid),
        .new_frame(new_frame),
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

    // Debug: raw frames to the PC over the USB-UART (tools/dump_frames.py)
    uart_dump #(
        .WORDS(80 + 4960)
    ) uart (
        .clk(clk),
        .frame_done(frame_done),
        .crc_ok(crc_ok),
        .sync_early(sync_early),
        .sync_late(sync_late),
        .raw_we(raw_we),
        .raw_idx(raw_idx),
        .raw_word(raw_word),
        .tx(uart_tx)
    );

    // Debug: first 128 raw SPI words of the latest frame on the 7-segment display
    reg [15:0] dbg_mem [0:127];
    reg [15:0] dbg_word = 16'd0;
    always @(posedge clk) begin
        if (raw_we && raw_idx < 14'd128)
            dbg_mem[raw_idx[6:0]] <= raw_word;
        dbg_word <= dbg_mem[sw[15:9]];
    end

    reg [17:0] seg_cnt = 18'd0;
    always @(posedge clk) seg_cnt <= seg_cnt + 1'b1;

    reg [3:0] nibble;
    always @(*) begin
        case (seg_cnt[17:16])
            2'd0:    nibble = dbg_word[3:0];
            2'd1:    nibble = dbg_word[7:4];
            2'd2:    nibble = dbg_word[11:8];
            default: nibble = dbg_word[15:12];
        endcase
    end

    reg [6:0] seg_n;   // active low: {g f e d c b a}
    always @(*) begin
        case (nibble)
            4'h0: seg_n = 7'b1000000;
            4'h1: seg_n = 7'b1111001;
            4'h2: seg_n = 7'b0100100;
            4'h3: seg_n = 7'b0110000;
            4'h4: seg_n = 7'b0011001;
            4'h5: seg_n = 7'b0010010;
            4'h6: seg_n = 7'b0000010;
            4'h7: seg_n = 7'b1111000;
            4'h8: seg_n = 7'b0000000;
            4'h9: seg_n = 7'b0010000;
            4'hA: seg_n = 7'b0001000;
            4'hB: seg_n = 7'b0000011;
            4'hC: seg_n = 7'b1000110;
            4'hD: seg_n = 7'b0100001;
            4'hE: seg_n = 7'b0000110;
            default: seg_n = 7'b0001110;
        endcase
    end

    assign seg = seg_n;
    assign dp  = 1'b1;
    assign an  = ~(4'b0001 << seg_cnt[17:16]);

    assign led[0] = config_done;
    assign led[1] = i2c_error;
    assign led[2] = thermal_drdy;
    assign led[3] = frame_toggle;
    assign led[4] = ~thermal_cs_n;
    assign led[5] = thermal_rst_n;
    assign led[6] = sync_early;
    assign led[7] = sync_late;
    assign led[8] = crc_ok_last;
    assign led[9] = crc_fail;

endmodule
