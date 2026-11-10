`timescale 1ns / 1ps

// MI48 bring-up: hardware reset, wait for boot, then configure over I2C.
//   1. nRESET low for RESET_CYCLES, then wait BOOT_CYCLES
//   2. poll STATUS (0xB6) until BOOTING_UP (bit 5) clears
//   3. read SENXOR_TYPE (0xBA), checked by the testbench
//   4. FRAME_RATE (0xB4)  = FRAME_RATE_DIV
//   5. read FW_VERSION_1/2 (0xB2, 0xB3) for the 7-segment
//   6. on-chip filters, only if any bit of filters is set (MI48Dx datasheet v4.0.5,
//      FILTER_CONTROL; the board's firmware is 3.2.13):
//        0xD1/0xD2 = TEMPORAL_STRENGTH
//        0xD0 = bit0 temporal, bit1 temporal init, bit2 rolling average (depth 0xD3,
//               reset 4), bit5 median 5x5 instead of 3x3, bit6 median
//      then wait INIT_CYCLES: the temporal init takes ~40 ms
//   7. FRAME_MODE (0xB1)  = 0x02 (continuous stream, header included)
//   8. read FRAME_MODE back, then config_done
// filters = {median 5x5, median, rolling average, temporal}, latched when bring-up
// starts. filters[3] alone also turns the median on.
// Any NACK or I2C timeout sets i2c_error (sticky) and restarts from step 1.

module mi48_ctrl #(
    parameter [6:0]   I2C_ADDR          = 7'h40,
    parameter [7:0]   FRAME_RATE_DIV    = 8'd4,
    parameter [15:0]  TEMPORAL_STRENGTH = 16'd50,      // reset value; 128 ghosted badly; Meridian's GUI uses 125
    parameter integer QUARTER_TICKS     = 500,
    parameter integer RESET_CYCLES      = 100_000,     // 1 ms
    parameter integer BOOT_CYCLES       = 50_000_000,  // 500 ms
    parameter integer POLL_CYCLES       = 1_000_000,   // 10 ms
    parameter integer RETRY_CYCLES      = 20_000_000,  // 200 ms
    parameter integer INIT_CYCLES       = 10_000_000,  // 100 ms
    parameter integer I2C_TIMEOUT       = 5_000_000    // 50 ms
) (
    input             clk,
    input             reset,
    input      [3:0]  filters,
    output reg        thermal_rst_n = 1'b0,
    inout             scl,
    inout             sda,
    output reg        config_done   = 1'b0,
    output reg        i2c_error     = 1'b0,
    output reg [7:0]  sensor_type   = 8'd0,
    output reg [7:0]  frame_mode    = 8'd0,
    output reg [15:0] fw_version    = 16'd0   // {FW_VERSION_1, FW_VERSION_2}
);

    localparam [7:0]
        REG_FRAME_MODE  = 8'hB1,
        REG_FW_VERSION1 = 8'hB2,
        REG_FW_VERSION2 = 8'hB3,
        REG_FRAME_RATE  = 8'hB4,
        REG_STATUS      = 8'hB6,
        REG_SENXOR_TYPE = 8'hBA,
        REG_FILTER_CTRL = 8'hD0,
        REG_FILTER_LSB  = 8'hD1,
        REG_FILTER_MSB  = 8'hD2;

    localparam [7:0] FRAME_MODE_STREAM = 8'h02;

    // In bring-up order; S_I2C_WAIT and S_ERROR are shared
    localparam [4:0]
        S_RESET      = 5'd0,
        S_BOOT       = 5'd1,
        S_POLL       = 5'd2,
        S_POLL_CHECK = 5'd3,
        S_POLL_GAP   = 5'd4,
        S_TYPE       = 5'd5,
        S_TYPE_SAVE  = 5'd6,
        S_RATE       = 5'd7,
        S_FW1        = 5'd8,
        S_FW2        = 5'd9,
        S_FILT_LSB   = 5'd10,
        S_FILT_MSB   = 5'd11,
        S_FILT_CTRL  = 5'd12,
        S_FILT_WAIT  = 5'd13,
        S_MODE       = 5'd14,
        S_MODE_RB    = 5'd15,
        S_MODE_SAVE  = 5'd16,
        S_RUN        = 5'd17,
        S_I2C_WAIT   = 5'd18,
        S_ERROR      = 5'd19;

    reg [4:0]  state     = S_RESET;
    reg [4:0]  ret_state = S_RESET;
    reg [25:0] count     = 26'd0;
    reg [7:0]  last_rd   = 8'd0;
    reg [3:0]  filt      = 4'd0;

    reg        i2c_start = 1'b0;
    reg        i2c_read  = 1'b0;
    reg [7:0]  i2c_reg   = 8'd0;
    reg [7:0]  i2c_wdata = 8'd0;
    wire       i2c_busy;
    wire       i2c_done;
    wire       i2c_nack;
    wire [7:0] i2c_rdata;

    i2c_master #(
        .QUARTER_TICKS(QUARTER_TICKS)
    ) i2c (
        .clk(clk),
        .reset(reset || state == S_ERROR),
        .start(i2c_start),
        .read(i2c_read),
        .dev_addr(I2C_ADDR),
        .reg_addr(i2c_reg),
        .wr_data(i2c_wdata),
        .busy(i2c_busy),
        .done(i2c_done),
        .rd_data(i2c_rdata),
        .nack(i2c_nack),
        .scl(scl),
        .sda(sda)
    );

    task issue(input rd, input [7:0] register, input [7:0] value, input [4:0] next);
        begin
            i2c_start <= 1'b1;
            i2c_read  <= rd;
            i2c_reg   <= register;
            i2c_wdata <= value;
            ret_state <= next;
            count     <= 26'd0;
            state     <= S_I2C_WAIT;
        end
    endtask

    always @(posedge clk) begin
        i2c_start <= 1'b0;

        if (reset) begin
            state         <= S_RESET;
            count         <= 26'd0;
            thermal_rst_n <= 1'b0;
            config_done   <= 1'b0;
            i2c_error     <= 1'b0;
        end else begin
            case (state)
                S_RESET: begin
                    thermal_rst_n <= 1'b0;
                    config_done   <= 1'b0;
                    filt          <= filters;
                    if (count == RESET_CYCLES - 1) begin
                        count         <= 26'd0;
                        thermal_rst_n <= 1'b1;
                        state         <= S_BOOT;
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                S_BOOT: begin
                    if (count == BOOT_CYCLES - 1) begin
                        count <= 26'd0;
                        state <= S_POLL;
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                S_POLL: issue(1'b1, REG_STATUS, 8'h00, S_POLL_CHECK);

                S_POLL_CHECK: begin
                    count <= 26'd0;
                    if (last_rd[5])
                        state <= S_POLL_GAP;
                    else
                        state <= S_TYPE;
                end

                S_POLL_GAP: begin
                    if (count == POLL_CYCLES - 1) begin
                        count <= 26'd0;
                        state <= S_POLL;
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                S_TYPE: issue(1'b1, REG_SENXOR_TYPE, 8'h00, S_TYPE_SAVE);

                S_TYPE_SAVE: begin
                    sensor_type <= last_rd;
                    state       <= S_RATE;
                end

                S_RATE: issue(1'b0, REG_FRAME_RATE, FRAME_RATE_DIV, S_FW1);

                S_FW1: issue(1'b1, REG_FW_VERSION1, 8'h00, S_FW2);

                S_FW2: begin
                    fw_version[15:8] <= last_rd;
                    issue(1'b1, REG_FW_VERSION2, 8'h00, S_FILT_LSB);
                end

                // With no filter selected the sensor setup stays as before filter support
                S_FILT_LSB: begin
                    fw_version[7:0] <= last_rd;
                    if (filt == 4'd0)
                        state <= S_MODE;
                    else
                        issue(1'b0, REG_FILTER_LSB, TEMPORAL_STRENGTH[7:0], S_FILT_MSB);
                end

                S_FILT_MSB:  issue(1'b0, REG_FILTER_MSB, TEMPORAL_STRENGTH[15:8], S_FILT_CTRL);

                S_FILT_CTRL: issue(1'b0, REG_FILTER_CTRL,
                                   {1'b0, filt[2] | filt[3], filt[3], 2'b00, filt[1], filt[0], filt[0]},
                                   S_FILT_WAIT);

                S_FILT_WAIT: begin
                    if (count == INIT_CYCLES - 1) begin
                        count <= 26'd0;
                        state <= S_MODE;
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                S_MODE: issue(1'b0, REG_FRAME_MODE, FRAME_MODE_STREAM, S_MODE_RB);

                S_MODE_RB: issue(1'b1, REG_FRAME_MODE, 8'h00, S_MODE_SAVE);

                S_MODE_SAVE: begin
                    frame_mode  <= last_rd;
                    config_done <= 1'b1;
                    state       <= S_RUN;
                end

                S_RUN: ;

                S_I2C_WAIT: begin
                    if (i2c_done) begin
                        count <= 26'd0;
                        if (i2c_nack) begin
                            state <= S_ERROR;
                        end else begin
                            last_rd <= i2c_rdata;
                            state   <= ret_state;
                        end
                    end else if (count == I2C_TIMEOUT - 1) begin
                        count <= 26'd0;
                        state <= S_ERROR;
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                S_ERROR: begin
                    i2c_error     <= 1'b1;
                    thermal_rst_n <= 1'b0;
                    if (count == RETRY_CYCLES - 1) begin
                        count <= 26'd0;
                        state <= S_RESET;
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                default: state <= S_RESET;
            endcase
        end
    end

endmodule
