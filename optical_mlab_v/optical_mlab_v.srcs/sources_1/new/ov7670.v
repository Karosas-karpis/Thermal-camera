`timescale 1ns / 1ps

// Line-based RGB565 capture for 320x240.
// Each HREF pulse starts a new row; addr = row*320 + col.
//
// Debug inputs (from switches):
//   invert_vsync - try if the frame still rolls
//   swap_bytes   - try if colors are psychedelic (green/red stripes)

module ov7670 (
    input        pclk,
    input        cam_vsync,
    input        href,
    input  [7:0] d,
    input        enable,
    input        invert_vsync,
    input        swap_bytes,

    output reg [16:0] wr_addr = 17'd0,
    output reg [15:0] wr_data = 16'd0,
    output reg        wr_en   = 1'b0
);

    localparam integer WIDTH  = 320;
    localparam integer HEIGHT = 240;

    reg enable_d1 = 1'b0, enable_d2 = 1'b0;
    reg vsync_d   = 1'b0;
    reg href_d    = 1'b0;

    reg        byte_flag = 1'b0;
    reg  [7:0] first_byte = 8'd0;
    reg  [8:0] col = 9'd0;
    reg  [7:0] row = 8'd0;

    wire vsync_now = cam_vsync ^ invert_vsync;
    wire vsync_rise = vsync_now & ~vsync_d;
    wire href_fall  = ~href & href_d;

    always @(posedge pclk) begin
        enable_d1 <= enable;
        enable_d2 <= enable_d1;
        vsync_d   <= vsync_now;
        href_d    <= href;
        wr_en     <= 1'b0;

        if (!enable_d2) begin
            byte_flag <= 1'b0;
            col       <= 9'd0;
            row       <= 8'd0;
            wr_addr   <= 17'd0;
        end else if (vsync_rise) begin
            byte_flag <= 1'b0;
            col       <= 9'd0;
            row       <= 8'd0;
        end else if (href) begin
            if (!byte_flag) begin
                first_byte <= d;
                byte_flag  <= 1'b1;
            end else begin
                byte_flag <= 1'b0;
                wr_data   <= swap_bytes ? {d, first_byte} : {first_byte, d};
                if (row < HEIGHT && col < WIDTH) begin
                    wr_addr <= (row * WIDTH) + col;
                    wr_en   <= 1'b1;
                    col     <= col + 1'b1;
                end
            end
        end else begin
            byte_flag <= 1'b0;
            if (href_fall) begin
                col <= 9'd0;
                if (row < HEIGHT)
                    row <= row + 1'b1;
            end
        end
    end

endmodule
