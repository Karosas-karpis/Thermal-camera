`timescale 1ns / 1ps

// Temperature label for the hot-spot marker: "c0 c1 c2 . t C" in a 5x7 font drawn at 2x,
// white on a black 76x18 plate with its top-left corner at (tx, ty).
// chars = {c0, c1, c2, t}, glyph codes 0..9 digits, 10 blank, 11 minus.
// bg (plate) and fg (glyph pixel) come 2 clocks after x / y.

module marker_text (
    input             clk,
    input             on,
    input      [9:0]  x,
    input      [9:0]  y,
    input      [9:0]  tx,
    input      [9:0]  ty,
    input      [15:0] chars,
    output reg        bg = 1'b0,
    output reg        fg = 1'b0
);

    localparam [9:0] PLATE_W = 10'd76;   // 2 + 6 cells of 12 + 2
    localparam [9:0] PLATE_H = 10'd18;   // 2 + 14 + 2

    localparam [3:0] G_DOT = 4'd12;
    localparam [3:0] G_C   = 4'd13;

    // 7 rows of 5 pixels, top row first, left pixel first
    function [34:0] glyph(input [3:0] code);
        case (code)
            4'd0:    glyph = 35'b01110_10001_10011_10101_11001_10001_01110;
            4'd1:    glyph = 35'b00100_01100_00100_00100_00100_00100_01110;
            4'd2:    glyph = 35'b01110_10001_00001_00010_00100_01000_11111;
            4'd3:    glyph = 35'b11111_00010_00100_00010_00001_10001_01110;
            4'd4:    glyph = 35'b00010_00110_01010_10010_11111_00010_00010;
            4'd5:    glyph = 35'b11111_10000_11110_00001_00001_10001_01110;
            4'd6:    glyph = 35'b00110_01000_10000_11110_10001_10001_01110;
            4'd7:    glyph = 35'b11111_00001_00010_00100_01000_01000_01000;
            4'd8:    glyph = 35'b01110_10001_10001_01110_10001_10001_01110;
            4'd9:    glyph = 35'b01110_10001_10001_01111_00001_00010_01100;
            4'd11:   glyph = 35'b00000_00000_00000_11111_00000_00000_00000;
            4'd12:   glyph = 35'b00000_00000_00000_00000_00000_01100_01100;
            4'd13:   glyph = 35'b01110_10001_10000_10000_10000_10001_01110;
            default: glyph = 35'd0;
        endcase
    endfunction

    // stage 1: position inside the plate
    wire [9:0] rx = x - tx;
    wire [9:0] ry = y - ty;

    reg       in1 = 1'b0;
    reg [6:0] rx1 = 7'd0;
    reg [4:0] ry1 = 5'd0;

    always @(posedge clk) begin
        in1 <= on && (x >= tx) && (rx < PLATE_W) && (y >= ty) && (ry < PLATE_H);
        rx1 <= rx[6:0];
        ry1 <= ry[4:0];
    end

    // stage 2: character cell, glyph pixel
    wire [6:0] gx   = rx1 - 7'd2;
    wire [4:0] gy   = ry1 - 5'd2;
    wire       g_in = (rx1 >= 7'd2) && (rx1 < 7'd74) && (ry1 >= 5'd2) && (ry1 < 5'd16);

    wire [2:0] cidx = (gx < 7'd12) ? 3'd0 :
                      (gx < 7'd24) ? 3'd1 :
                      (gx < 7'd36) ? 3'd2 :
                      (gx < 7'd48) ? 3'd3 :
                      (gx < 7'd60) ? 3'd4 : 3'd5;
    wire [6:0] cx   = gx - {cidx, 3'b000} - {1'b0, cidx, 2'b00};   // gx - 12 * cidx
    wire [2:0] fcol = cx[3:1];    // 0..4 glyph, 5 gap
    wire [2:0] frow = gy[3:1];    // 0..6

    reg [3:0] code;
    always @(*) begin
        case (cidx)
            3'd0:    code = chars[15:12];
            3'd1:    code = chars[11:8];
            3'd2:    code = chars[7:4];
            3'd3:    code = G_DOT;
            3'd4:    code = chars[3:0];
            default: code = G_C;
        endcase
    end

    wire [34:0] bits = glyph(code);
    wire [5:0]  bidx = 6'd34 - ({3'b000, frow} + {1'b0, frow, 2'b00}) - {3'b000, fcol};   // 34 - 5 * row - col

    always @(posedge clk) begin
        bg <= in1;
        fg <= in1 && g_in && (fcol < 3'd5) && bits[bidx];
    end

endmodule
