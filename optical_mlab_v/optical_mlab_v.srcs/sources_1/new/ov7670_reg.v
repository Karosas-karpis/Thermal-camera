`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 02:13:07 PM
// Design Name: 
// Module Name: ov7670_reg
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

`timescale 1ns / 1ps

module ov7670_registers (
    input clk,
    input [7:0] config_step,
    output reg [15:0] command
);

    always @(posedge clk) begin
        case(config_step)
            // Format: {8-bit Register Address, 8-bit Register Value}
            
            // 1. Reset Camera
            8'd0:  command <= 16'h12_80; // COM7: Reset all registers
            
            // 2. Delay step (Give camera time to reset)
            8'd1:  command <= 16'hFF_FF; // FF_FF is ignored by the sender but acts as a delay
            
            // 3. Base Configuration: RGB and Color Bar test
            8'd2:  command <= 16'h12_14; // COM7: QVGA, RGB
            8'd3:  command <= 16'h40_D0; // COM15: RGB565, Full output range
            8'd4:  command <= 16'hB0_84; // Color settings
            
            // 4. QQVGA (160x120) Scaling
            8'd5:  command <= 16'h0C_08; // COM3: Enable scaling
            8'd6:  command <= 16'h3E_1A; // COM14: Manual scaling, PCLK divided by 4
            8'd7:  command <= 16'h70_3A; // SCALING_XSC
            8'd8:  command <= 16'h71_35; // SCALING_YSC
            8'd9:  command <= 16'h72_11; // SCALING_DCWCTR
            8'd10: command <= 16'h73_F0; // SCALING_PCLK_DIV
            8'd11: command <= 16'hA2_02; // SCALING_PCLK_DELAY

            // 5. Hardware timing fixes
            8'd12: command <= 16'h11_01; // CLKRC: Internal clock pre-scaler
            8'd13: command <= 16'h1E_37; // MVFP: Mirror / VFlip (Adjust if image is upside down)
            
            // End of configuration
            default: command <= 16'hFF_FF; 
        endcase
    end

endmodule
