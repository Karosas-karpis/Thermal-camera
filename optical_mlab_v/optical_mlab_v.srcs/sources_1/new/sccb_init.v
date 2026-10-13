`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 02:20:20 PM
// Design Name: 
// Module Name: sccb_init
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

module sccb_init (
    input clk,            // 100 MHz Basys 3 clock
    input reset,          // Optional reset button
    output sioc,          // I2C Clock
    inout siod,           // I2C Data
    output config_done    // Goes HIGH when all registers are written
);

    wire [7:0] config_step;
    wire [15:0] command;

    // The lookup table containing the camera settings
    ov7670_reg registers_inst (
        .clk(clk),
        .config_step(config_step),
        .command(command)
    );

    // The state machine that physically transmits the data
    i2c_sender sender_inst (
        .clk(clk),
        .reset(reset),
        .command(command),
        .config_step(config_step),
        .sioc(sioc),
        .siod(siod),
        .done(config_done)
    );

endmodule