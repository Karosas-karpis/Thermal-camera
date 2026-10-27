`timescale 1ns / 1ps

// Single-register I2C master for the MI48 (Thermal-44 module).
//   write: S addr+W A reg A data A P
//   read:  S addr+W A reg A Sr addr+R A data NA P
// Every state lasts one quarter. One bit = low, low (SDA changes), high (sample).
// QUARTER_TICKS = 500 at 100 MHz -> 5 us quarters, ~67 kHz SCL. Each quarter
// is longer than the MI48 minimum hold/setup times (4.7 us max requirement).
// SCL/SDA are open-drain; the slave may stretch the clock.

module i2c_master #(
    parameter integer QUARTER_TICKS = 500
) (
    input            clk,
    input            reset,
    input            start,
    input            read,
    input      [6:0] dev_addr,
    input      [7:0] reg_addr,
    input      [7:0] wr_data,
    output reg       busy    = 1'b0,
    output reg       done    = 1'b0,   // one-cycle pulse
    output reg [7:0] rd_data = 8'd0,
    output reg       nack    = 1'b0,   // valid with done
    inout            scl,
    inout            sda
);

    reg scl_drive_low = 1'b0;
    reg sda_drive_low = 1'b0;
    assign scl = scl_drive_low ? 1'b0 : 1'bz;
    assign sda = sda_drive_low ? 1'b0 : 1'bz;

    reg [1:0] scl_sync = 2'b11;
    reg [1:0] sda_sync = 2'b11;
    always @(posedge clk) begin
        scl_sync <= {scl_sync[0], scl};
        sda_sync <= {sda_sync[0], sda};
    end
    wire scl_in = scl_sync[1];
    wire sda_in = sda_sync[1];

    localparam [3:0]
        IDLE    = 4'd0,
        START_A = 4'd1,   // SCL high, SDA high (bus free / Sr setup)
        START_B = 4'd2,   // SCL high, SDA low
        BIT_A   = 4'd3,   // SCL low, SDA changes at end
        BIT_B   = 4'd4,   // SCL low, SDA stable
        BIT_C   = 4'd5,   // SCL high, sample at end
        RS_A    = 4'd6,   // SCL low, SDA released, then SCL rises for Sr
        STOP_A  = 4'd7,   // SCL low
        STOP_B  = 4'd8,   // SCL low, SDA low
        STOP_C  = 4'd9,   // SCL high, SDA low
        STOP_D  = 4'd10;  // SCL high, SDA high

    localparam [2:0]
        PH_ADDR_W = 3'd0,
        PH_REG    = 3'd1,
        PH_DATA   = 3'd2,
        PH_ADDR_R = 3'd3,
        PH_READ   = 3'd4;

    reg [3:0]  state   = IDLE;
    reg [2:0]  phase   = PH_ADDR_W;
    reg [15:0] tick    = 16'd0;
    reg [3:0]  bit_cnt = 4'd0;      // 0-7 data, 8 = ACK slot
    reg [7:0]  shift   = 8'd0;
    reg        is_read = 1'b0;
    reg [6:0]  addr_q  = 7'd0;
    reg [7:0]  reg_q   = 8'd0;
    reg [7:0]  data_q  = 8'd0;

    wire quarter_end = (tick == QUARTER_TICKS - 1);
    wire receiving   = (phase == PH_READ);

    always @(posedge clk) begin
        done <= 1'b0;

        if (reset) begin
            state         <= IDLE;
            busy          <= 1'b0;
            nack          <= 1'b0;
            tick          <= 16'd0;
            scl_drive_low <= 1'b0;
            sda_drive_low <= 1'b0;
        end else if (state == IDLE) begin
            scl_drive_low <= 1'b0;
            sda_drive_low <= 1'b0;
            tick          <= 16'd0;
            if (start) begin
                busy    <= 1'b1;
                nack    <= 1'b0;
                is_read <= read;
                addr_q  <= dev_addr;
                reg_q   <= reg_addr;
                data_q  <= wr_data;
                phase   <= PH_ADDR_W;
                state   <= START_A;
            end
        end else if (state == BIT_C && !scl_in) begin
            // Slave is stretching SCL; restart the high quarter once released.
            tick <= 16'd0;
        end else if (!quarter_end) begin
            tick <= tick + 1'b1;
        end else begin
            tick <= 16'd0;
            case (state)
                START_A: begin
                    sda_drive_low <= 1'b1;
                    state <= START_B;
                end

                START_B: begin
                    scl_drive_low <= 1'b1;
                    bit_cnt <= 4'd0;
                    shift <= {addr_q, (phase == PH_ADDR_R)};
                    state <= BIT_A;
                end

                BIT_A: begin
                    // ACK slot: release for the slave's ACK, or send our NACK.
                    if (bit_cnt == 4'd8 || receiving)
                        sda_drive_low <= 1'b0;
                    else
                        sda_drive_low <= ~shift[7];
                    state <= BIT_B;
                end

                BIT_B: begin
                    scl_drive_low <= 1'b0;
                    state <= BIT_C;
                end

                BIT_C: begin
                    scl_drive_low <= 1'b1;
                    if (bit_cnt != 4'd8) begin
                        shift   <= {shift[6:0], sda_in};
                        bit_cnt <= bit_cnt + 1'b1;
                        state   <= BIT_A;
                    end else begin
                        bit_cnt <= 4'd0;
                        if (!receiving && sda_in) begin
                            nack  <= 1'b1;
                            state <= STOP_A;
                        end else begin
                            case (phase)
                                PH_ADDR_W: begin
                                    phase <= PH_REG;
                                    shift <= reg_q;
                                    state <= BIT_A;
                                end
                                PH_REG: begin
                                    if (is_read) begin
                                        state <= RS_A;
                                    end else begin
                                        phase <= PH_DATA;
                                        shift <= data_q;
                                        state <= BIT_A;
                                    end
                                end
                                PH_DATA: state <= STOP_A;
                                PH_ADDR_R: begin
                                    phase <= PH_READ;
                                    state <= BIT_A;
                                end
                                default: begin
                                    rd_data <= shift;
                                    state <= STOP_A;
                                end
                            endcase
                        end
                    end
                end

                RS_A: begin
                    sda_drive_low <= 1'b0;
                    scl_drive_low <= 1'b0;
                    phase <= PH_ADDR_R;
                    state <= START_A;
                end

                STOP_A: begin
                    sda_drive_low <= 1'b1;
                    state <= STOP_B;
                end

                STOP_B: begin
                    scl_drive_low <= 1'b0;
                    state <= STOP_C;
                end

                STOP_C: begin
                    sda_drive_low <= 1'b0;
                    state <= STOP_D;
                end

                STOP_D: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
