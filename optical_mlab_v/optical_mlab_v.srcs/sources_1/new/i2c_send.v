`timescale 1ns / 1ps

module i2c_sender (
    input clk,
    input reset,
    input [15:0] command,     // {Reg Addr, Reg Data} from ROM
    output reg [7:0] config_step = 0,
    output reg sioc = 1,
    inout siod,
    output reg done = 0
);

    // I2C Tri-state logic for SIOD
    reg siod_out = 1;
    reg siod_drive = 1; 
    assign siod = (siod_drive) ? siod_out : 1'bz;

    // Clock divider: 100MHz / 400 = 250kHz for state transitions
    reg [8:0] clk_div = 0;
    wire step_tick = (clk_div == 399);

    always @(posedge clk) begin
        if (reset) clk_div <= 0;
        else if (step_tick) clk_div <= 0;
        else clk_div <= clk_div + 1;
    end

    // Standard OV7670 I2C Write Address
    localparam CAMERA_ID = 8'h42; 

    // State Machine
    reg [7:0] state = 0;
    reg [7:0] data_byte;
    
    always @(posedge clk) begin
        if (reset) begin
            state <= 0;
            config_step <= 0;
            done <= 0;
            sioc <= 1;
            siod_out <= 1;
            siod_drive <= 1;
        end else if (step_tick && !done) begin
            
            // Check if we hit the end of the ROM list
            if (command == 16'hFFFF) begin
                done <= 1;
            end else begin
            
                case (state)
                    // START CONDITION
                    0: begin siod_out <= 0; state <= 1; end // SDA goes low
                    1: begin sioc <= 0; state <= 2; end     // SCL goes low
                    
                    // SEND CAMERA ID (0x42)
                    2,3,4,5,6,7,8,9: begin
                        siod_out <= CAMERA_ID[9 - state];
                        if (state == 9) state <= 10;
                        else state <= state + 1;
                    end
                    
                    // ACK 1 (Don't care for SCCB)
                    10: begin siod_drive <= 0; state <= 11; end 
                    
                    // SEND REGISTER ADDRESS (Top 8 bits of command)
                    11,12,13,14,15,16,17,18: begin
                        siod_drive <= 1;
                        siod_out <= command[18 - state + 8];
                        if (state == 18) state <= 19;
                        else state <= state + 1;
                    end
                    
                    // ACK 2
                    19: begin siod_drive <= 0; state <= 20; end
                    
                    // SEND REGISTER DATA (Bottom 8 bits of command)
                    20,21,22,23,24,25,26,27: begin
                        siod_drive <= 1;
                        siod_out <= command[27 - state];
                        if (state == 27) state <= 28;
                        else state <= state + 1;
                    end
                    
                    // ACK 3
                    28: begin siod_drive <= 0; state <= 29; end
                    
                    // STOP CONDITION
                    29: begin siod_drive <= 1; siod_out <= 0; sioc <= 0; state <= 30; end
                    30: begin sioc <= 1; state <= 31; end // SCL goes high
                    31: begin siod_out <= 1; state <= 32; end // SDA goes high
                    
                    // DELAY & NEXT STEP
                    32: begin
                        state <= 0;
                        config_step <= config_step + 1; // Move to next register in ROM
                    end
                endcase
                
                // Clock toggling logic for middle of data transmission
                if (state >= 2 && state <= 28) begin
                    // Toggle SIOC (Clock) up and down while data is steady
                    if (clk_div == 99)  sioc <= 1;
                    if (clk_div == 299) sioc <= 0;
                end
            end
        end
    end

endmodule