`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 12:14:13 PM
// Design Name: 
// Module Name: led_blink
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
    output reg [15:0] led // 16 onboard LEDs
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
endmodule