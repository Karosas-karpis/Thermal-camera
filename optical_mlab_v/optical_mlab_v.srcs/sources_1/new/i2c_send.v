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

    // SCCB/I2C data is open drain: drive zero or release the line.
    reg siod_drive_low = 0;
    assign siod = siod_drive_low ? 1'b0 : 1'bz;

    // One state step per microsecond from the 100 MHz board clock.
    // Four states per data bit produce a 250 kHz SIOC.
    reg [6:0] clk_div = 0;
    wire state_tick = (clk_div == 7'd99);

    localparam [7:0] CAMERA_ID = 8'h42;
    localparam [3:0]
        IDLE         = 4'd0,
        START_HOLD   = 4'd1,
        START_LOW    = 4'd2,
        BIT_SETUP    = 4'd3,
        BIT_HIGH     = 4'd4,
        BIT_HOLD     = 4'd5,
        BIT_FALL     = 4'd6,
        DC_SETUP     = 4'd7,
        DC_HIGH      = 4'd8,
        DC_HOLD      = 4'd9,
        DC_FALL      = 4'd10,
        STOP_LOW     = 4'd11,
        STOP_HIGH    = 4'd12,
        STOP_RELEASE = 4'd13,
        DC_NEXT      = 4'd14,
        DC_STOP      = 4'd15;

    reg [3:0] state = IDLE;
    reg [1:0] byte_index = 0;
    reg [2:0] bit_index = 7;
    reg [17:0] delay_cnt = 0;

    wire [7:0] tx_byte = (byte_index == 0) ? CAMERA_ID :
                         (byte_index == 1) ? command[15:8] :
                                             command[7:0];
    wire tx_bit = tx_byte[bit_index];

    always @(posedge clk) begin
        if (reset) begin
            clk_div <= 0;
            state <= IDLE;
            byte_index <= 0;
            bit_index <= 7;
            delay_cnt <= 0;
            config_step <= 0;
            done <= 0;
            sioc <= 1;
            siod_drive_low <= 0;
        end else if (!done) begin
            if (state_tick)
                clk_div <= 0;
            else
                clk_div <= clk_div + 1'b1;

            if (state_tick) begin
                case (state)
                    IDLE: begin
                        sioc <= 1'b1;
                        siod_drive_low <= 1'b0;
                        if (command == 16'hFFFF) begin
                            done <= 1'b1;
                        end else if (command == 16'hFFFE) begin
                            // OV7670 requires a delay after its software reset.
                            if (delay_cnt == 18'd199999) begin
                                delay_cnt <= 0;
                                config_step <= config_step + 1'b1;
                            end else begin
                                delay_cnt <= delay_cnt + 1'b1;
                            end
                        end else begin
                            delay_cnt <= 0;
                            byte_index <= 0;
                            bit_index <= 7;
                            siod_drive_low <= 1'b1; // START: SDA falls while SCL high
                            state <= START_HOLD;
                        end
                    end

                    START_HOLD: state <= START_LOW;

                    START_LOW: begin
                        sioc <= 1'b0;
                        state <= BIT_SETUP;
                    end

                    BIT_SETUP: begin
                        siod_drive_low <= ~tx_bit;
                        state <= BIT_HIGH;
                    end

                    BIT_HIGH: begin
                        sioc <= 1'b1;
                        state <= BIT_HOLD;
                    end

                    BIT_HOLD: state <= BIT_FALL;

                    BIT_FALL: begin
                        sioc <= 1'b0;
                        if (bit_index == 0) begin
                            siod_drive_low <= 1'b0;
                            state <= DC_SETUP;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            state <= BIT_SETUP;
                        end
                    end

                    // SCCB defines the ninth clock as "don't care", not as
                    // a guaranteed I2C acknowledge. Release SIOD and continue.
                    DC_SETUP: begin
                        siod_drive_low <= 1'b0;
                        state <= DC_HIGH;
                    end

                    DC_HIGH: begin
                        sioc <= 1'b1;
                        state <= DC_HOLD;
                    end

                    DC_HOLD: state <= DC_FALL;

                    DC_FALL: begin
                        sioc <= 1'b0;
                        if (byte_index == 2) begin
                            state <= DC_STOP;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                            bit_index <= 7;
                            state <= DC_NEXT;
                        end
                    end

                    // Keep SIOD released long enough after the ninth clock
                    // before either sending the next byte or issuing STOP.
                    DC_NEXT: state <= BIT_SETUP;
                    DC_STOP: state <= STOP_LOW;

                    STOP_LOW: begin
                        siod_drive_low <= 1'b1;
                        state <= STOP_HIGH;
                    end

                    STOP_HIGH: begin
                        sioc <= 1'b1;
                        state <= STOP_RELEASE;
                    end

                    STOP_RELEASE: begin
                        siod_drive_low <= 1'b0; // STOP: SDA rises while SCL high
                        config_step <= config_step + 1'b1;
                        state <= IDLE;
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end

endmodule
