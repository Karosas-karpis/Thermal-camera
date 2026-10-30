`timescale 1ns / 1ps

// OV7670 three-phase SCCB write controller.
// Adapted from the supplied 2018 I2C_Controller write path:
// one 24-bit packet {0x42, register, value}, with three released ACK slots.
// The bus runs at 100 kHz and uses open-drain SIOC/SIOD.
// 16'hFFFE = wait then skip to next step
// 16'hFFFF = end of list

module i2c_sender #(
    parameter integer QUARTER_TICKS = 250,
    parameter integer POWERUP_QUARTERS = 240000,
    parameter integer RESET_WAIT_QUARTERS = 80000,
    parameter integer BUS_GAP_QUARTERS = 8
) (
    input clk,
    input reset,
    input [15:0] command,   // {reg addr, reg data}
    output reg [7:0] config_step = 0,
    inout sioc,
    inout siod,
    output reg done = 0,
    output reg ack_error = 0
);

    reg sioc_drive_low = 1'b0;
    reg siod_drive_low = 1'b0;
    assign sioc = sioc_drive_low ? 1'b0 : 1'bz;
    assign siod = siod_drive_low ? 1'b0 : 1'bz;

    localparam [7:0] CAMERA_ID = 8'h42;
    localparam [4:0]
        POWERUP      = 5'd0,
        IDLE         = 5'd1,
        START_HOLD   = 5'd2,
        BIT_LOW      = 5'd3,
        BIT_SETUP    = 5'd4,
        BIT_HIGH     = 5'd5,
        BIT_HOLD     = 5'd6,
        BIT_FALL     = 5'd7,
        STOP_DATA    = 5'd8,
        STOP_CLOCK   = 5'd9,
        STOP_RELEASE = 5'd10,
        BUS_GAP      = 5'd11,
        RESET_WAIT   = 5'd12;

    reg [4:0]  state = POWERUP;
    reg [8:0]  tick_count = 9'd0;
    reg [17:0] delay_count = 18'd0;
    reg [3:0]  gap_count = 4'd0;
    reg [4:0]  transfer_bit = 5'd0; // 24 data bits + three ACK slots
    reg [23:0] write_packet = 24'd0;

    wire state_tick = (tick_count == QUARTER_TICKS - 1);
    wire ack_slot = (transfer_bit == 5'd8) ||
                    (transfer_bit == 5'd17) ||
                    (transfer_bit == 5'd26);

    always @(posedge clk) begin
        if (reset) begin
            state           <= POWERUP;
            tick_count      <= 9'd0;
            delay_count     <= 18'd0;
            gap_count       <= 4'd0;
            transfer_bit    <= 5'd0;
            write_packet    <= 24'd0;
            config_step     <= 8'd0;
            done            <= 1'b0;
            ack_error       <= 1'b0;
            sioc_drive_low  <= 1'b0;
            siod_drive_low  <= 1'b0;
        end else if (!done) begin
            if (state_tick)
                tick_count <= 9'd0;
            else
                tick_count <= tick_count + 1'b1;

            if (state_tick) begin
                case (state)
                    // Known-working examples wait about 0.6 s before SCCB.
                    POWERUP: begin
                        sioc_drive_low <= 1'b0;
                        siod_drive_low <= 1'b0;
                        if (delay_count == POWERUP_QUARTERS - 1) begin
                            delay_count <= 18'd0;
                            state <= IDLE;
                        end else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    IDLE: begin
                        sioc_drive_low <= 1'b0;
                        siod_drive_low <= 1'b0;
                        if (command == 16'hFFFF) begin
                            done <= 1'b1;
                        end else if (command == 16'hFFFE) begin
                            delay_count <= 18'd0;
                            state <= RESET_WAIT;
                        end else begin
                            // Same packet layout as I2C_WDATA in the supplied
                            // controller: slave address, sub-address, data.
                            write_packet <= {CAMERA_ID, command};
                            transfer_bit <= 5'd0;
                            // START: SIOD falls while SIOC remains high.
                            siod_drive_low <= 1'b1;
                            state <= START_HOLD;
                        end
                    end

                    START_HOLD: begin
                        state <= BIT_LOW;
                    end

                    BIT_LOW: begin
                        sioc_drive_low <= 1'b1;
                        state <= BIT_SETUP;
                    end

                    BIT_SETUP: begin
                        // MSB first. ACK slots are inputs (high impedance).
                        if (ack_slot)
                            siod_drive_low <= 1'b0;
                        else
                            siod_drive_low <= ~write_packet[23];
                        state <= BIT_HIGH;
                    end

                    BIT_HIGH: begin
                        sioc_drive_low <= 1'b0;
                        state <= BIT_HOLD;
                    end

                    BIT_HOLD: begin
                        // Match the supplied controller's ACKW1/2/3 behavior.
                        // Keep running after NACK, but expose a sticky error.
                        if (ack_slot && siod)
                            ack_error <= 1'b1;
                        state <= BIT_FALL;
                    end

                    BIT_FALL: begin
                        sioc_drive_low <= 1'b1;
                        if (transfer_bit == 5'd26) begin
                            state <= STOP_DATA;
                        end else begin
                            if (!ack_slot)
                                write_packet <= {write_packet[22:0], 1'b0};
                            transfer_bit <= transfer_bit + 1'b1;
                            state <= BIT_LOW;
                        end
                    end

                    // STOP: SIOD rises while SIOC is high.
                    STOP_DATA: begin
                        siod_drive_low <= 1'b1;
                        state <= STOP_CLOCK;
                    end

                    STOP_CLOCK: begin
                        sioc_drive_low <= 1'b0;
                        state <= STOP_RELEASE;
                    end

                    STOP_RELEASE: begin
                        siod_drive_low <= 1'b0;
                        gap_count <= 4'd0;
                        state <= BUS_GAP;
                    end

                    // 20 us idle between register writes.
                    BUS_GAP: begin
                        if (gap_count == BUS_GAP_QUARTERS - 1) begin
                            config_step <= config_step + 1'b1;
                            state <= IDLE;
                        end else begin
                            gap_count <= gap_count + 1'b1;
                        end
                    end

                    // 200 ms after the OV7670 software-reset command.
                    RESET_WAIT: begin
                        if (delay_count == RESET_WAIT_QUARTERS - 1) begin
                            delay_count <= 18'd0;
                            config_step <= config_step + 1'b1;
                            state <= IDLE;
                        end else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    default: state <= POWERUP;
                endcase
            end
        end
    end

endmodule
