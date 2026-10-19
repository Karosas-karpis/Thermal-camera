`timescale 1ns / 1ps

// RGB565 capture for one 320x240 active frame.
// HREF gates active bytes, while the address advances once per complete pixel.
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

    localparam integer WIDTH        = 320;
    localparam integer HEIGHT       = 240;
    localparam integer FRAME_PIXELS = WIDTH * HEIGHT;

    reg enable_d1 = 1'b0, enable_d2 = 1'b0;
    reg vsync_d   = 1'b0;

    reg        byte_flag = 1'b0;
    reg  [7:0] first_byte = 8'd0;
    reg [16:0] pixel_count = 17'd0;

    wire vsync_now = cam_vsync ^ invert_vsync;
    wire vsync_rise = vsync_now & ~vsync_d;

    always @(posedge pclk) begin
        enable_d1 <= enable;
        enable_d2 <= enable_d1;
        vsync_d   <= vsync_now;
        wr_en     <= 1'b0;

        if (!enable_d2) begin
            byte_flag <= 1'b0;
            pixel_count <= 17'd0;
            wr_addr   <= 17'd0;
        end else if (vsync_rise) begin
            byte_flag <= 1'b0;
            pixel_count <= 17'd0;
            wr_addr   <= 17'd0;
        end else if (href) begin
            if (!byte_flag) begin
                first_byte <= d;
                byte_flag  <= 1'b1;
            end else begin
                byte_flag <= 1'b0;
                wr_data   <= swap_bytes ? {d, first_byte} : {first_byte, d};
                if (pixel_count < FRAME_PIXELS) begin
                    wr_addr <= pixel_count;
                    wr_en   <= 1'b1;
                    pixel_count <= pixel_count + 1'b1;
                end
            end
        end else begin
            byte_flag <= 1'b0;
        end
    end

endmodule
