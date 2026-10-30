`timescale 1ns / 1ps

// Bilinear upscale of the 80x62 thermal frame to 640x480: 8x in both directions, so the
// screen shows 60 of the 62 rows (one row cropped top and bottom).
// One VGA pixel is 4 clocks, so the single RAM read port gives all 4 neighbours per pixel.
// Interpolating the raw 0.1 K values keeps the range scaling after this stage smooth.
//
// sel follows the pixel clock: x changes on sel 1 and the coordinates below are stable for
// sel 0..3 one pixel later. Reads are issued on sel 0..3 and return 2 clocks later.
// Latency from x / y to t is 13 clocks; t then holds for 4 clocks.

module thermal_upscale (
    input             clk,
    input             tick,
    input      [9:0]  x,
    input      [9:0]  y,
    input             mirror_x,
    input             flip_y,
    output reg [12:0] rd_addr = 13'd0,
    input      [15:0] rd_data,
    output reg [15:0] t = 16'd0
);

    localparam [9:0] X_LAST = 10'd639;
    localparam [9:0] Y_LAST = 10'd479;
    localparam [9:0] Y_CROP = 10'd8;
    localparam [9:0] HALF   = 10'd4;   // thermal pixel centres are half a pixel in

    reg [1:0] sel = 2'd0;
    always @(posedge clk)
        sel <= tick ? 2'd1 : sel + 1'b1;

    reg [9:0] xm = 10'd0;
    reg [9:0] ym = 10'd0;
    reg [9:0] ux = 10'd0;
    reg [9:0] uy = 10'd0;

    wire [6:0] tx_w = ux[9:3];
    wire [5:0] ty_w = uy[8:3];
    wire [5:0] ty_n = (ty_w == 6'd61) ? 6'd61 : ty_w + 1'b1;

    reg [6:0]  tx0 = 7'd0;
    reg [6:0]  tx1 = 7'd0;
    reg [12:0] row0 = 13'd0;
    reg [12:0] row1 = 13'd0;
    reg [2:0]  fx = 3'd0;
    reg [2:0]  fy = 3'd0;

    always @(posedge clk) begin
        xm <= mirror_x ? X_LAST - x : x;
        ym <= (flip_y ? Y_LAST - y : y) + Y_CROP;

        ux <= (xm > HALF) ? xm - HALF : 10'd0;
        uy <= (ym > HALF) ? ym - HALF : 10'd0;

        tx0  <= tx_w;
        tx1  <= (tx_w == 7'd79) ? 7'd79 : tx_w + 1'b1;
        row0 <= {1'b0, ty_w, 6'd0} + {3'b000, ty_w, 4'd0};
        row1 <= {1'b0, ty_n, 6'd0} + {3'b000, ty_n, 4'd0};
        fx   <= ux[2:0];
        fy   <= uy[2:0];

        case (sel)
            2'd0:    rd_addr <= row0 + tx0;
            2'd1:    rd_addr <= row0 + tx1;
            2'd2:    rd_addr <= row1 + tx0;
            default: rd_addr <= row1 + tx1;
        endcase
    end

    reg [15:0] a = 16'd0, b = 16'd0, c = 16'd0;
    reg [15:0] a1 = 16'd0, b1 = 16'd0, c1 = 16'd0, d1 = 16'd0;
    reg [2:0]  fx_h = 3'd0, fy_h = 3'd0;
    reg [2:0]  fx1 = 3'd0, fy1 = 3'd0;

    // The last sample comes back after the coordinates moved on, so the fractions are held.
    always @(posedge clk) begin
        if (sel == 2'd3) begin
            fx_h <= fx;
            fy_h <= fy;
        end
        case (sel)
            2'd2: a <= rd_data;
            2'd3: b <= rd_data;
            2'd0: c <= rd_data;
            default: begin
                a1  <= a;
                b1  <= b;
                c1  <= c;
                d1  <= rd_data;
                fx1 <= fx_h;
                fy1 <= fy_h;
            end
        endcase
    end

    wire [3:0] fx_inv = 4'd8 - fx1;
    wire [3:0] fy_inv = 4'd8 - fy1;

    reg [18:0] ma = 19'd0, mb = 19'd0, mc = 19'd0, md = 19'd0;
    reg [18:0] top = 19'd0, bot = 19'd0;
    reg [21:0] mt = 22'd0, mu = 22'd0;
    reg [2:0]  fy2 = 3'd0, fy3 = 3'd0;
    reg [3:0]  fy_inv2 = 4'd0, fy_inv3 = 4'd0;

    wire [21:0] sum = mt + mu + 22'd32;

    always @(posedge clk) begin
        ma <= a1 * fx_inv;
        mb <= b1 * fx1;
        mc <= c1 * fx_inv;
        md <= d1 * fx1;
        fy2 <= fy1;
        fy_inv2 <= fy_inv;

        top <= ma + mb;
        bot <= mc + md;
        fy3 <= fy2;
        fy_inv3 <= fy_inv2;

        mt <= top * fy_inv3;
        mu <= bot * fy3;

        t <= sum[21:6];
    end

endmodule
