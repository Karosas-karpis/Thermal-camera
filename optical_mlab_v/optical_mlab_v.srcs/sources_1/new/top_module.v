`timescale 1ns / 1ps

// OV7670 -> BRAM -> VGA
//
// LEDs:
//   0 = config_done
//   1 = raw VSYNC level (should move / not stuck)
//   2 = raw HREF level (MUST change when you unplug camera HS)
//   3 = PCLK heartbeat (~1-2 Hz)
//   4 = write activity
//   5 = VSYNC edge activity
//   6 = HREF edge activity
//   7 = SCCB NACK/error (sticky)
//
// Switches:
//   sw[0] = invert camera VSYNC
//   sw[1] = swap captured pixel bytes (normally OFF)
//   sw[2] = camera color bars (set before programming the FPGA)
//   sw[3] = swap R/B on VGA (OFF = datasheet RGB565, ON = old colour-fix mapping)
//   sw[4] = RGB format (OFF = RGB565, ON = alternate RGB555; set before programming)

module top_module (
    input         clk,
    output [15:0] led,
    input  [11:0] sw,
    output        hsync,
    output        vsync,
    output [3:0]  vgaRed,
    output [3:0]  vgaGreen,
    output [3:0]  vgaBlue,

    output        xclk,
    input         pclk,
    input         cam_vsync,
    input         href,
    input  [7:0]  d,
    inout         sioc,
    inout         siod,
    output        cam_reset,
    output        pwdn
);

    wire config_done;
    wire sccb_ack_error;

    assign pwdn      = 1'b0;
    assign cam_reset = 1'b1;

    cam_xclk cam_clock (
        .clk_in1(clk),
        .clk_out1(xclk)
    );

    sccb_init camera_setup (
        .clk(clk),
        .reset(1'b0),
        .color_bar(sw[2]),
        .rgb555(sw[4]),
        .sioc(sioc),
        .siod(siod),
        .config_done(config_done),
        .ack_error(sccb_ack_error)
    );

    wire [16:0] wr_addr;
    wire [15:0] wr_data;
    wire        wr_en;

    ov7670 camera_capture (
        .pclk(pclk),
        .cam_vsync(cam_vsync),
        .href(href),
        .d(d),
        .enable(config_done),
        .invert_vsync(sw[0]),
        .swap_bytes(sw[1]),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .wr_en(wr_en)
    );

    // sync async camera bits into clk domain for LEDs
    reg v_meta1 = 1'b0, v_meta2 = 1'b0, v_meta3 = 1'b0;
    reg h_meta1 = 1'b0, h_meta2 = 1'b0, h_meta3 = 1'b0;
    reg w_meta1 = 1'b0, w_meta2 = 1'b0, w_meta3 = 1'b0;
    reg v_edge_led = 1'b0, h_edge_led = 1'b0, w_edge_led = 1'b0;

    always @(posedge clk) begin
        v_meta1 <= cam_vsync;
        v_meta2 <= v_meta1;
        v_meta3 <= v_meta2;
        if (v_meta2 ^ v_meta3)
            v_edge_led <= ~v_edge_led;

        h_meta1 <= href;
        h_meta2 <= h_meta1;
        h_meta3 <= h_meta2;
        if (h_meta2 ^ h_meta3)
            h_edge_led <= ~h_edge_led;

        w_meta1 <= wr_en;
        w_meta2 <= w_meta1;
        w_meta3 <= w_meta2;
        if (w_meta2 & ~w_meta3)
            w_edge_led <= ~w_edge_led;
    end

    reg [23:0] pclk_div = 24'd0;
    always @(posedge pclk) pclk_div <= pclk_div + 1'b1;

    assign led[0] = config_done;
    assign led[1] = v_meta2;       // raw VSYNC
    assign led[2] = h_meta2;       // raw HREF
    assign led[3] = pclk_div[23];  // PCLK alive
    assign led[4] = w_edge_led;    // writes
    assign led[5] = v_edge_led;    // VSYNC edges
    assign led[6] = h_edge_led;    // HREF edges
    assign led[7] = sccb_ack_error; // at least one SCCB NACK
    assign led[15:8] = 8'd0;

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

    wire [8:0]  frame_x = vga_x[9:1];
    wire [8:0]  frame_y = vga_y[9:1];
    wire [16:0] rd_addr = (frame_y * 17'd320) + frame_x;
    wire [15:0] rd_data;

    blk_mem_gen_0 frame_buf (
        .clka(pclk),
        .wea(wr_en),
        .addra(wr_addr),
        .dina(wr_data),
        .clkb(clk),
        .addrb(rd_addr),
        .doutb(rd_data)
    );

    reg [11:0] vga_rgb = 12'd0;

    always @(posedge clk) begin
        if (!config_done) begin
            if (video_on)
                vga_rgb <= sw;
            else
                vga_rgb <= 12'd0;
        end else if (video_on) begin
            // Convert selected camera format to RGB444. sw[3] swaps R/B.
            if (sw[4]) begin
                if (sw[3])
                    vga_rgb <= {rd_data[4:1], rd_data[9:6], rd_data[14:11]};
                else
                    vga_rgb <= {rd_data[14:11], rd_data[9:6], rd_data[4:1]};
            end else begin
                if (sw[3])
                    vga_rgb <= {rd_data[4:1], rd_data[10:7], rd_data[15:12]};
                else
                    vga_rgb <= {rd_data[15:12], rd_data[10:7], rd_data[4:1]};
            end
        end else begin
            vga_rgb <= 12'd0;
        end
    end

    assign vgaRed   = vga_rgb[11:8];
    assign vgaGreen = vga_rgb[7:4];
    assign vgaBlue  = vga_rgb[3:0];

endmodule
