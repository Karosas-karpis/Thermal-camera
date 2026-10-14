`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 11:46:13 AM
// Design Name: 
// Module Name: top_module
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module top_module (
    input clk,           // 100 MHz onboard clock
    output reg [15:0] led, // 16 onboard LEDs
    // Switches for VGA Color Test
    input [11:0] sw,
    // VGA Monitor Outputs
    output hsync,
    output vsync,
    output [3:0] vgaRed,
    output [3:0] vgaGreen,
    output [3:0] vgaBlue
    
    // Camera Configuration Pins (Pmod) — commented out for VGA-only test
    // (unconstrained I/O can block bitstream / place on wrong pins)
    // output sioc,
    // inout  siod
);

    reg [26:0] count = 0; 

    initial begin
        led = 16'b0; 
    end
    always @(posedge clk) begin
        if (count == 49_999_999) begin
            count <= 0;      
            led <= ~led;     
        end else begin
            count <= count + 1; 
        end
    end
    
    //// camera sccb — commented out for VGA-only test
    // wire camera_config_done;
    // sccb_init camera_setup (
    //     .clk(clk),
    //     .reset(1'b0),
    //     .sioc(sioc),
    //     .siod(siod),
    //     .config_done(camera_config_done)
    // );
    
    //VGA test
    wire [11:0] vga_rgb; // Internal wire to catch the 12-bit color output
    
    vga_test vga_display (
        .clk_100MHz(clk),        // Changed to match top_module's 'clk'
        .reset(1'b0),            // Tied to 0
        .sw(sw),                 // Connect physical switches to VGA module
        .hsync(hsync),           // Connect to physical pin
        .vsync(vsync),           // Connect to physical pin
        .rgb(vga_rgb)            // Send output to internal wire
    );
    
    
    assign vgaRed   = vga_rgb[11:8];
    assign vgaGreen = vga_rgb[7:4];
    assign vgaBlue  = vga_rgb[3:0];  
    
    
    
endmodule


