`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 01:49:42 PM
// Design Name: 
// Module Name: ov7670
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


module ov7670(
    input pclk,           
    input vsync,          
    input href,           
    input [7:0] d,        
    
    // Outputs sending formatted data deeper into the FPGA (to Block RAM)
    output reg [11:0] pixel_data, 
    output reg pixel_valid
    
    
    
    );
endmodule
