`timescale 1ns / 1ps


//
// VGA Mode
// 640x480 pixels VGA screen with 25MHz pixel rate based on 60 Hz refresh rate
// 800 pixels/line * 525 lines/screen * 60 screens/second = ~25.2M pixels/second
//
// Everything is clocked by clk_100MHz. The 25 MHz pixel rate is a clock
// enable (p_tick), never a derived clock, so the whole module stays in one
// timed clock domain.
//

module vga_controller(
    input clk_100MHz,   // from FPGA
    input reset,        // system reset
    output video_on,    // ON while pixel counts for x and y and within display area
    output hsync,       // horizontal sync
    output vsync,       // vertical sync
    output p_tick,      // the 25MHz pixel/second rate signal, pixel tick
    output [9:0] x,     // pixel count/position of pixel x, max 0-799
    output [9:0] y      // pixel count/position of pixel y, max 0-524
    );

    // Based on VGA standards found at vesa.org for 640x480 resolution
    // Total horizontal width of screen = 800 pixels, partitioned  into sections
    parameter HD = 640;             // horizontal display area width in pixels
    parameter HF = 48;              // horizontal front porch width in pixels
    parameter HB = 16;              // horizontal back porch width in pixels
    parameter HR = 96;              // horizontal retrace width in pixels
    parameter HMAX = HD+HF+HB+HR-1; // max value of horizontal counter = 799
    // Total vertical length of screen = 525 pixels, partitioned into sections
    parameter VD = 480;             // vertical display area length in pixels
    parameter VF = 10;              // vertical front porch length in pixels
    parameter VB = 33;              // vertical back porch length in pixels
    parameter VR = 2;               // vertical retrace length in pixels
    parameter VMAX = VD+VF+VB+VR-1; // max value of vertical counter = 524

    // *** Pixel tick: one clk_100MHz cycle in every four ***************************************
    reg  [1:0] tick_div;
    wire       pixel_tick;

    always @(posedge clk_100MHz or posedge reset) begin
        if (reset) begin
            tick_div <= 2'd0;
        end else begin
            tick_div <= tick_div + 2'd1;
        end
    end

    assign pixel_tick = (tick_div == 2'd0);
    // ****************************************************************************************

    // Pixel position counters
    reg [9:0] h_count;
    reg [9:0] v_count;

    // Registered sync outputs
    reg h_sync_reg;
    reg v_sync_reg;

    // Horizontal and vertical counters.
    // Both advance only when pixel_tick is high, so they are clocked by
    // clk_100MHz and enabled at the 25 MHz pixel rate.
    always @(posedge clk_100MHz or posedge reset) begin
        if (reset) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (pixel_tick) begin
                if (h_count == HMAX) begin          // end of horizontal scan
                    h_count <= 10'd0;
                    if (v_count == VMAX) begin      // end of vertical scan
                        v_count <= 10'd0;
                    end else begin
                        v_count <= v_count + 10'd1;
                    end
                end else begin
                    h_count <= h_count + 10'd1;
                end
            end
        end
    end

    // Sync pulses, registered to keep the outputs glitch free.
    // h_sync asserted within the horizontal retrace area.
    // v_sync asserted within the vertical retrace area.
    always @(posedge clk_100MHz or posedge reset) begin
        if (reset) begin
            h_sync_reg <= 1'b0;
            v_sync_reg <= 1'b0;
        end else begin
            if ((h_count >= (HD+HB)) && (h_count <= (HD+HB+HR-1))) begin
                h_sync_reg <= 1'b1;
            end else begin
                h_sync_reg <= 1'b0;
            end

            if ((v_count >= (VD+VB)) && (v_count <= (VD+VB+VR-1))) begin
                v_sync_reg <= 1'b1;
            end else begin
                v_sync_reg <= 1'b0;
            end
        end
    end

    // Video ON/OFF - only ON while pixel counts are within the display area
    assign video_on = (h_count < HD) && (v_count < VD); // 0-639 and 0-479 respectively

    // Outputs
    assign hsync  = h_sync_reg;
    assign vsync  = v_sync_reg;
    assign x      = h_count;
    assign y      = v_count;
    assign p_tick = pixel_tick;

endmodule
