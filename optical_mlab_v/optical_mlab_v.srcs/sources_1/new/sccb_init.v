`timescale 1ns / 1ps

// Ties the register table to the SCCB sender.
// config_done goes high after the last register is written.

module sccb_init (
    input clk,
    input reset,
    input color_bar,
    output sioc,
    inout siod,
    output config_done
);

    wire [7:0] config_step;
    wire [15:0] command;

    ov7670_reg registers_inst (
        .clk(clk),
        .config_step(config_step),
        .color_bar(color_bar),
        .command(command)
    );

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
