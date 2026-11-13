`timescale 1ns / 1ps

// OV7670 setup: ov7670_reg holds the register list, sccb_sender writes it one entry at a time.
// config_done goes high after the last register is written.

module sccb_init (
    input  clk,
    input  reset,
    input  color_bar,
    input  rgb555,
    inout  sioc,
    inout  siod,
    output config_done,
    output ack_error
);

    wire [7:0]  config_step;
    wire [15:0] command;

    ov7670_reg registers (
        .clk(clk),
        .config_step(config_step),
        .color_bar(color_bar),
        .rgb555(rgb555),
        .command(command)
    );

    sccb_sender sender (
        .clk(clk),
        .reset(reset),
        .command(command),
        .config_step(config_step),
        .sioc(sioc),
        .siod(siod),
        .done(config_done),
        .ack_error(ack_error)
    );

endmodule
