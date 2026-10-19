`timescale 1ns / 1ps

// Simple VGA test for boards with 12 bit RGB (4 bits per color).
// Shows a solid color from the switches.

module vga_test(
	input clk_100MHz,
	input reset,
	input [11:0] sw,       // color from switches
	output hsync,
	output vsync,
	output reg [11:0] rgb
);

	reg [11:0] rgb_reg;
	wire video_on;

    vga_controller vga_c(
        .clk_100MHz(clk_100MHz),
        .reset(reset),
        .hsync(hsync),
        .vsync(vsync),
        .video_on(video_on),
        .p_tick(),
        .x(),
        .y()
    );

    always @(posedge clk_100MHz or posedge reset)
    if (reset)
       rgb_reg <= 0;
    else
       rgb_reg <= sw;

    // only drive RGB inside the visible area
    always @(*) begin
        if (video_on)
            rgb = rgb_reg;
        else
            rgb = 12'b0;
    end

endmodule
