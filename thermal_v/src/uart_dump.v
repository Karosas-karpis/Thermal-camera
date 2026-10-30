`timescale 1ns / 1ps

// Debug: sends one raw SPI frame over the Basys 3 USB-UART after a frame_done.
//   packet = DE AD BE EF, flags, WORDS words as received (MSB first), 16-bit sum of the words
//   flags  = {5'd0, sync_late, sync_early, crc_ok}
// Capture is frozen while a packet is going out, so frames during the ~110 ms
// transfer (at 921600 baud) are skipped. 8N1.

module uart_dump #(
    parameter integer CLKS_PER_BIT = 108,     // 100 MHz / 921600
    parameter integer WORDS        = 5049
) (
    input         clk,
    input         frame_done,
    input         crc_ok,
    input         sync_early,
    input         sync_late,
    input         raw_we,
    input  [13:0] raw_idx,
    input  [15:0] raw_word,
    output        tx
);

    reg [15:0] mem [0:WORDS - 1];
    reg [15:0] rdata = 16'd0;
    reg [12:0] widx  = 13'd0;
    reg        sending = 1'b0;

    always @(posedge clk) begin
        if (raw_we && !sending && raw_idx < WORDS)
            mem[raw_idx[12:0]] <= raw_word;
        rdata <= mem[widx];
    end

    // byte transmitter
    reg [7:0]  tx_data  = 8'd0;
    reg        tx_valid = 1'b0;
    reg        busy     = 1'b0;
    reg [9:0]  shift    = 10'h3FF;
    reg [3:0]  nbits    = 4'd0;
    reg [15:0] baud_cnt = 16'd0;
    wire       tx_ready = !busy && !tx_valid;

    assign tx = shift[0];

    always @(posedge clk) begin
        if (!busy) begin
            if (tx_valid) begin
                shift    <= {1'b1, tx_data, 1'b0};
                nbits    <= 4'd10;
                baud_cnt <= 16'd0;
                busy     <= 1'b1;
            end
        end else if (baud_cnt == CLKS_PER_BIT - 1) begin
            baud_cnt <= 16'd0;
            shift    <= {1'b1, shift[9:1]};
            nbits    <= nbits - 1'b1;
            if (nbits == 4'd1)
                busy <= 1'b0;
        end else begin
            baud_cnt <= baud_cnt + 1'b1;
        end
    end

    // packet sequencer
    localparam [2:0]
        IDLE  = 3'd0,
        HDR   = 3'd1,
        FETCH = 3'd2,
        HI    = 3'd3,
        LO    = 3'd4,
        SUM_H = 3'd5,
        SUM_L = 3'd6;

    reg [2:0] st     = IDLE;
    reg [2:0] hcnt   = 3'd0;
    reg [2:0] flags  = 3'd0;
    reg [15:0] sum   = 16'd0;

    reg [7:0] hdr_byte;
    always @(*) begin
        case (hcnt)
            3'd0:    hdr_byte = 8'hDE;
            3'd1:    hdr_byte = 8'hAD;
            3'd2:    hdr_byte = 8'hBE;
            3'd3:    hdr_byte = 8'hEF;
            default: hdr_byte = {5'd0, flags};
        endcase
    end

    always @(posedge clk) begin
        tx_valid <= 1'b0;
        case (st)
            IDLE: begin
                if (frame_done) begin
                    flags   <= {sync_late, sync_early, crc_ok};
                    hcnt    <= 3'd0;
                    sum     <= 16'd0;
                    sending <= 1'b1;
                    st      <= HDR;
                end
            end

            HDR: if (tx_ready) begin
                tx_data  <= hdr_byte;
                tx_valid <= 1'b1;
                if (hcnt == 3'd4) begin
                    widx <= 13'd0;
                    st   <= FETCH;
                end else begin
                    hcnt <= hcnt + 1'b1;
                end
            end

            FETCH: st <= HI;

            HI: if (tx_ready) begin
                tx_data  <= rdata[15:8];
                tx_valid <= 1'b1;
                sum      <= sum + rdata;
                st       <= LO;
            end

            LO: if (tx_ready) begin
                tx_data  <= rdata[7:0];
                tx_valid <= 1'b1;
                if (widx == WORDS - 1) begin
                    st <= SUM_H;
                end else begin
                    widx <= widx + 1'b1;
                    st   <= FETCH;
                end
            end

            SUM_H: if (tx_ready) begin
                tx_data  <= sum[15:8];
                tx_valid <= 1'b1;
                st       <= SUM_L;
            end

            SUM_L: if (tx_ready) begin
                tx_data  <= sum[7:0];
                tx_valid <= 1'b1;
                sending  <= 1'b0;
                st       <= IDLE;
            end

            default: st <= IDLE;
        endcase
    end

endmodule
