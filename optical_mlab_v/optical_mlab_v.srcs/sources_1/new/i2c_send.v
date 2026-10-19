`timescale 1ns / 1ps

// Bit bang SCCB write to the OV7670.
// Walks through the register list from ov7670_reg, one write at a time.
// SIOD is open drain style (driven low or released).
// 16'hFFFE = wait then skip to next step
// 16'hFFFF = end of list

module i2c_sender (
    input clk,
    input reset,
    input [15:0] command,   // {reg addr, reg data}
    output reg [7:0] config_step = 0,
    output reg sioc = 1,
    inout siod,
    output reg done = 0
);

    reg siod_out = 1;
    reg siod_drive = 1;
    assign siod = (siod_drive) ? siod_out : 1'bz;

    // ~250 kHz bit timing from 100 MHz
    reg [8:0] clk_div = 0;
    wire step_tick = (clk_div == 399);

    localparam CAMERA_ID = 8'h42;

    reg [7:0] state = 0;
    reg [15:0] delay_cnt = 0;

    always @(posedge clk) begin
        if (reset) begin
            clk_div <= 0;
            state <= 0;
            config_step <= 0;
            done <= 0;
            sioc <= 1;
            siod_out <= 1;
            siod_drive <= 1;
            delay_cnt <= 0;
        end else if (!done) begin
            if (step_tick)
                clk_div <= 0;
            else
                clk_div <= clk_div + 1;

            // Toggle SIOC in the middle of each bit period
            if (state >= 2 && state <= 28) begin
                if (clk_div == 99)  sioc <= 1;
                if (clk_div == 299) sioc <= 0;
            end

            if (step_tick) begin
                if (command == 16'hFFFF) begin
                    done <= 1;
                end else if (command == 16'hFFFE) begin
                    // wait after soft reset (~a few ms)
                    // longer pause after soft reset (~200 ms)
                    if (delay_cnt == 16'd50000) begin
                        delay_cnt <= 0;
                        config_step <= config_step + 1;
                    end else begin
                        delay_cnt <= delay_cnt + 1;
                    end
                end else begin
                    case (state)
                        0: begin siod_out <= 0; state <= 1; end
                        1: begin sioc <= 0; state <= 2; end

                        2,3,4,5,6,7,8,9: begin
                            siod_out <= CAMERA_ID[9 - state];
                            if (state == 9) state <= 10;
                            else state <= state + 1;
                        end

                        10: begin siod_drive <= 0; state <= 11; end

                        11,12,13,14,15,16,17,18: begin
                            siod_drive <= 1;
                            siod_out <= command[18 - state + 8];
                            if (state == 18) state <= 19;
                            else state <= state + 1;
                        end

                        19: begin siod_drive <= 0; state <= 20; end

                        20,21,22,23,24,25,26,27: begin
                            siod_drive <= 1;
                            siod_out <= command[27 - state];
                            if (state == 27) state <= 28;
                            else state <= state + 1;
                        end

                        28: begin siod_drive <= 0; state <= 29; end

                        29: begin siod_drive <= 1; siod_out <= 0; sioc <= 0; state <= 30; end
                        30: begin sioc <= 1; state <= 31; end
                        31: begin siod_out <= 1; state <= 32; end

                        32: begin
                            state <= 0;
                            config_step <= config_step + 1;
                        end
                    endcase
                end
            end
        end
    end

endmodule
