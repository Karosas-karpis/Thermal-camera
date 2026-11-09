`timescale 1ns / 1ps

// Bilinear upscale of the 80x62 thermal frame onto the 640x480 screen. Thermal coordinates
// are in 1/8 pixel, zoomed around the screen centre: tc = ((screen - centre) * zoom >> 7)
// + centre + offset. Zoom 128 with offset 0 is 8x in both directions and shows 60 of the
// 62 rows (one row cropped top and bottom). A larger zoom shrinks the image; screen pixels
// outside the frame come out with valid = 0.
// One VGA pixel is 4 clocks, so the single RAM read port gives all 4 neighbours per pixel.
// Interpolating the raw 0.1 K values keeps the range scaling after this stage smooth.
//
// sel follows the pixel clock, 2 clocks late to match the zoom stages: the coordinates
// below are stable for sel 0..3 one pixel later. Reads are issued on sel 0..3 and return
// 2 clocks later. Latency from x / y to t and valid is 15 clocks; both then hold for 4 clocks.

module thermal_upscale (
    input             clk,
    input             tick,
    input      [9:0]  x,
    input      [9:0]  y,
    input             mirror_x,
    input             flip_y,
    input      [7:0]  zoom,
    input  signed [9:0] off_x,
    input  signed [9:0] off_y,
    output reg [12:0] rd_addr = 13'd0,
    input      [15:0] rd_data,
    output reg [15:0] t = 16'd0,
    output            valid
);

    localparam [9:0] X_LAST = 10'd639;   // last 1/8 column of the frame (80 * 8 - 1)
    localparam [9:0] Y_LAST = 10'd495;   // last 1/8 row of the frame (62 * 8 - 1)
    localparam signed [12:0] Y_CROP = 13'sd8;
    localparam [9:0] HALF   = 10'd4;   // thermal pixel centres are half a pixel in

    reg [1:0] tick_d = 2'b00;
    reg [1:0] sel    = 2'd0;
    always @(posedge clk) begin
        tick_d <= {tick_d[0], tick};
        sel    <= tick_d[1] ? 2'd1 : sel + 1'b1;
    end

    // Zoom and offset in screen space, then mirror / flip inside the frame
    reg signed [19:0] zx = 20'sd0;
    reg signed [19:0] zy = 20'sd0;
    reg signed [12:0] tcx = 13'sd0;
    reg signed [12:0] tcy = 13'sd0;

    wire signed [10:0] dx = $signed({1'b0, x}) - 11'sd320;
    wire signed [10:0] dy = $signed({1'b0, y}) - 11'sd240;

    always @(posedge clk) begin
        zx  <= dx * $signed({1'b0, zoom});
        zy  <= dy * $signed({1'b0, zoom});
        tcx <= (zx >>> 7) + 13'sd320 + off_x;
        tcy <= (zy >>> 7) + 13'sd240 + off_y + Y_CROP;
    end

    wire in_x = (tcx >= 13'sd0) && (tcx <= $signed({3'b000, X_LAST}));
    wire in_y = (tcy >= 13'sd0) && (tcy <= $signed({3'b000, Y_LAST}));
    wire [9:0] cx = (tcx < 13'sd0) ? 10'd0 : in_x ? tcx[9:0] : X_LAST;
    wire [9:0] cy = (tcy < 13'sd0) ? 10'd0 : in_y ? tcy[9:0] : Y_LAST;

    // valid_d[0] is registered with xm / ym, which are 12 clocks before t
    reg [12:0] valid_d = 13'd0;
    assign valid = valid_d[12];

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
        xm <= mirror_x ? X_LAST - cx : cx;
        ym <= flip_y   ? Y_LAST - cy : cy;
        valid_d <= {valid_d[11:0], in_x && in_y};

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
