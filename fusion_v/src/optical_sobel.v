`timescale 1ns / 1ps

// RGB565 stream from ov7670 -> 8-bit {Y[7:2], E[1:0]} for the optical frame buffer (pclk domain).
// Y = 2R + 2.5G + B on the raw 5/6/5-bit values (0..250), no multipliers.
// E is the Sobel magnitude |Gx| + |Gy| against thr, 2*thr and 4*thr:
//   0 = no edge (camera noise), 1..3 = weak..strong.
// Pixels arrive at least 2 pclk apart, so the line buffers are read and written in turn:
//   t0: in_we, read both line buffers at col
//   t1: write the line buffers, shift the 3x3 window
//   t2: magnitude, write {Y, E} of the window centre
// The centre is one row and one column behind the input, so the last row and the last
// column stay black, and the first two rows and columns have E = 0.

module optical_sobel #(
    parameter integer WIDTH = 320
) (
    input             pclk,
    input             in_we,
    input      [16:0] in_addr,
    input      [8:0]  in_col,
    input      [7:0]  in_row,
    input      [15:0] in_rgb,
    input      [6:0]  thr,

    output reg        out_we   = 1'b0,
    output reg [16:0] out_addr = 17'd0,
    output reg [7:0]  out_data = 8'd0
);

    wire [4:0] r = in_rgb[15:11];
    wire [5:0] g = in_rgb[10:5];
    wire [4:0] b = in_rgb[4:0];
    wire [7:0] g_part = ({2'b00, g, 2'b00} + {4'd0, g}) >> 1;   // 5G / 2
    wire [7:0] luma   = {2'b00, r, 1'b0} + g_part + {3'b000, b};

    reg [7:0] line1 [0:WIDTH - 1];
    reg [7:0] line2 [0:WIDTH - 1];
    reg [7:0] rd1 = 8'd0;
    reg [7:0] rd2 = 8'd0;

    integer i;
    initial
        for (i = 0; i < WIDTH; i = i + 1) begin
            line1[i] = 8'd0;
            line2[i] = 8'd0;
        end

    reg        v1 = 1'b0;
    reg        v2 = 1'b0;
    reg [7:0]  y1 = 8'd0;
    reg [8:0]  col1 = 9'd0;
    reg [7:0]  row1 = 8'd0;
    reg [16:0] addr1 = 17'd0;
    reg [8:0]  col2 = 9'd0;
    reg [7:0]  row2 = 8'd0;
    reg [16:0] addr2 = 17'd0;

    // window: wRC, row 0 = oldest line, column 2 = newest pixel
    reg [7:0] w00 = 8'd0, w01 = 8'd0, w02 = 8'd0;
    reg [7:0] w10 = 8'd0, w11 = 8'd0, w12 = 8'd0;
    reg [7:0] w20 = 8'd0, w21 = 8'd0, w22 = 8'd0;

    always @(posedge pclk) begin
        rd1 <= line1[in_col];
        rd2 <= line2[in_col];

        v1 <= in_we;
        v2 <= v1;

        if (in_we) begin
            y1    <= luma;
            col1  <= in_col;
            row1  <= in_row;
            addr1 <= in_addr;
        end

        if (v1) begin
            line1[col1] <= y1;
            line2[col1] <= rd1;

            w00 <= w01; w01 <= w02; w02 <= rd2;
            w10 <= w11; w11 <= w12; w12 <= rd1;
            w20 <= w21; w21 <= w22; w22 <= y1;

            col2  <= col1;
            row2  <= row1;
            addr2 <= addr1;
        end
    end

    wire [9:0]  gx_p = {2'b00, w02} + {1'b0, w12, 1'b0} + {2'b00, w22};
    wire [9:0]  gx_n = {2'b00, w00} + {1'b0, w10, 1'b0} + {2'b00, w20};
    wire [9:0]  gy_p = {2'b00, w20} + {1'b0, w21, 1'b0} + {2'b00, w22};
    wire [9:0]  gy_n = {2'b00, w00} + {1'b0, w01, 1'b0} + {2'b00, w02};
    wire [9:0]  gx   = (gx_p > gx_n) ? gx_p - gx_n : gx_n - gx_p;
    wire [9:0]  gy   = (gy_p > gy_n) ? gy_p - gy_n : gy_n - gy_p;
    wire [10:0] mag  = {1'b0, gx} + {1'b0, gy};

    wire [1:0] strength = (mag >= {2'b00, thr, 2'b00}) ? 2'd3 :
                          (mag >= {3'b000, thr, 1'b0}) ? 2'd2 :
                          (mag >= {4'b0000, thr})      ? 2'd1 : 2'd0;

    wire window_full = (col2 >= 9'd2) && (row2 >= 8'd2);
    wire center_ok   = (col2 >= 9'd1) && (row2 >= 8'd1);

    always @(posedge pclk) begin
        out_we <= v2 && center_ok;
        if (v2) begin
            out_addr <= addr2 - 17'd321;
            out_data <= {w11[7:2], window_full ? strength : 2'd0};
        end
    end

endmodule
