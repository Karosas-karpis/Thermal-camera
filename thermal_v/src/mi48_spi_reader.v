`timescale 1ns / 1ps

// Reads one MI48 thermal frame per DATA_READY over SPI mode 0.
// Frame = optional 80-word header + 4960 pixel words, 16-bit, MSB first, MOSI held 0.
// Pixels are 0.1 K units, row-major 80x62, written to the frame RAM as they arrive.
//
// DATA_READY falls only after the MI48 has clocked out the whole frame, so it is
// used to check word alignment:
//   - falls before our last word  -> the sensor saw extra SCLK edges (ringing):
//     frame dropped, sync_early set
//   - still high 2 ms after CS is released -> the sensor did not see a full
//     frame: frame dropped, sync_late set
// CS is released as soon as the expected word count is done. The MI48 drops
// DATA_READY after that release, so waiting for it while CS is still low stalls.
// frame_done only pulses for frames that ended exactly on the expected word.
// Small slips (a few bits) still look aligned, so the pixel data is also checked
// against the header CRC-16/CCITT-FALSE (word 7). The datasheet does not state the
// byte order, so both word byte orders are accepted; crc_ok comes with frame_done.

module mi48_spi_reader #(
    parameter integer SCLK_HALF    = 25,      // 100 MHz / 50 = 2 MHz SCLK
    parameter integer CS_SETUP     = 1_000,   // 10 us from CS low to first SCLK
    parameter integer DONE_TIMEOUT = 200_000  // 2 ms for DATA_READY to fall
) (
    input             clk,
    input             reset,
    input             enable,
    input             has_header,     // FRAME_MODE.NO_HEADER == 0
    input             data_ready,
    input             miso,
    output reg        sclk = 1'b0,
    output reg        cs_n = 1'b1,
    output            mosi,

    output reg        pix_we   = 1'b0,
    output reg [12:0] pix_addr = 13'd0,
    output reg [15:0] pix_data = 16'd0,

    output reg        frame_done   = 1'b0,   // one-cycle pulse after an aligned frame
    output reg        crc_ok       = 1'b0,   // valid with frame_done
    output reg [15:0] frame_count  = 16'd0,  // header word 0
    output reg [15:0] frame_min    = 16'd0,
    output reg [15:0] frame_max    = 16'd0,
    output reg [15:0] frame_center = 16'd0,  // pixel (40, 31)
    output reg        sync_early   = 1'b0,   // sticky
    output reg        sync_late    = 1'b0    // sticky
);

    localparam integer PIXELS       = 4960;
    localparam integer CENTER_PIXEL = 31 * 80 + 40;

    assign mosi = 1'b0;

    reg [1:0] drdy_sync = 2'b00;
    reg       miso_q    = 1'b0;
    always @(posedge clk) begin
        drdy_sync <= {drdy_sync[0], data_ready};
        miso_q    <= miso;
    end
    wire drdy = drdy_sync[1];

    localparam [2:0]
        IDLE     = 3'd0,
        SETUP    = 3'd1,
        CLK_LOW  = 3'd2,
        CLK_HIGH = 3'd3,
        CHECK    = 3'd4,
        FINISH   = 3'd5,
        ABORT    = 3'd6;

    reg [2:0]  state    = IDLE;
    reg [17:0] count    = 18'd0;
    reg [3:0]  bit_cnt  = 4'd0;
    reg [13:0] word_cnt = 14'd0;
    reg [15:0] shift    = 16'd0;
    reg [6:0]  header_words = 7'd80;
    reg [15:0] hdr_count  = 16'd0;
    reg [15:0] run_min    = 16'd0;
    reg [15:0] run_max    = 16'd0;
    reg        scale_seen = 1'b0;
    reg [15:0] run_center = 16'd0;

    wire [13:0] frame_words = header_words + PIXELS;
    wire [13:0] pixel_idx   = word_cnt - header_words;
    wire        in_pixels   = (word_cnt >= header_words) && (word_cnt < frame_words);

    // miso_q was registered >= SCLK_HALF-1 cycles after the falling edge,
    // so it is stable when sampled at the rising edge.
    wire [15:0] word = {shift[14:0], miso_q};

    // Bit-serial CRC over each pixel word, 16 clocks per word in the background.
    localparam [15:0] CRC_POLY = 16'h1021;
    reg [15:0] crc_be     = 16'hFFFF;   // bytes high, low (wire order)
    reg [15:0] crc_le     = 16'hFFFF;   // bytes low, high
    reg [15:0] crc_in_be  = 16'd0;
    reg [15:0] crc_in_le  = 16'd0;
    reg [4:0]  crc_bits   = 5'd0;
    reg [15:0] hdr_crc    = 16'd0;
    wire       crc_idle   = (crc_bits == 5'd0);
    wire       crc_start  = (state == CLK_LOW) && (count == SCLK_HALF - 1) &&
                            (bit_cnt == 4'd15) && in_pixels;

    always @(posedge clk) begin
        if (state == SETUP) begin
            crc_be   <= 16'hFFFF;
            crc_le   <= 16'hFFFF;
            crc_bits <= 5'd0;
        end else if (crc_start) begin
            crc_in_be <= word;
            crc_in_le <= {word[7:0], word[15:8]};
            crc_bits  <= 5'd16;
        end else if (!crc_idle) begin
            if (crc_be[15] ^ crc_in_be[15])
                crc_be <= {crc_be[14:0], 1'b0} ^ CRC_POLY;
            else
                crc_be <= {crc_be[14:0], 1'b0};
            if (crc_le[15] ^ crc_in_le[15])
                crc_le <= {crc_le[14:0], 1'b0} ^ CRC_POLY;
            else
                crc_le <= {crc_le[14:0], 1'b0};
            crc_in_be <= {crc_in_be[14:0], 1'b0};
            crc_in_le <= {crc_in_le[14:0], 1'b0};
            crc_bits  <= crc_bits - 1'b1;
        end
    end

    always @(posedge clk) begin
        pix_we       <= 1'b0;
        frame_done   <= 1'b0;

        if (reset) begin
            state      <= IDLE;
            cs_n       <= 1'b1;
            sclk       <= 1'b0;
            count      <= 18'd0;
            sync_early <= 1'b0;
            sync_late  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    cs_n  <= 1'b1;
                    sclk  <= 1'b0;
                    count <= 18'd0;
                    if (enable && drdy) begin
                        if (has_header)
                            header_words <= 7'd80;
                        else
                            header_words <= 7'd0;
                        cs_n  <= 1'b0;
                        state <= SETUP;
                    end
                end

                SETUP: begin
                    if (count == CS_SETUP - 1) begin
                        count    <= 18'd0;
                        bit_cnt    <= 4'd0;
                        word_cnt   <= 14'd0;
                        scale_seen <= 1'b0;
                        state      <= CLK_LOW;
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                CLK_LOW: begin
                    if (count == SCLK_HALF - 1) begin
                        count <= 18'd0;
                        sclk  <= 1'b1;
                        shift <= word;
                        if (bit_cnt == 4'd15) begin
                            if (word_cnt == 14'd0) begin
                                if (has_header)
                                    hdr_count <= word;
                                else
                                    hdr_count <= hdr_count + 1'b1;
                            end
                            if (word_cnt == 14'd7)
                                hdr_crc <= word;
                            if (in_pixels) begin
                                pix_we   <= 1'b1;
                                pix_addr <= pixel_idx[12:0];
                                pix_data <= word;
                                // 0 and other impossible readings (a dead pixel, or a
                                // shifted word) must not set the scale. Otherwise the
                                // picture is one flat colour and a warm object is one shade lighter.
                                if (word >= 16'd2300 && word <= 16'd8000) begin
                                    if (!scale_seen || word < run_min)
                                        run_min <= word;
                                    if (!scale_seen || word > run_max)
                                        run_max <= word;
                                    scale_seen <= 1'b1;
                                end
                                if (pixel_idx == CENTER_PIXEL)
                                    run_center <= word;
                            end
                        end
                        state <= CLK_HIGH;
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                CLK_HIGH: begin
                    if (count == SCLK_HALF - 1) begin
                        count <= 18'd0;
                        sclk  <= 1'b0;
                        if (bit_cnt != 4'd15) begin
                            bit_cnt <= bit_cnt + 1'b1;
                            state   <= CLK_LOW;
                        end else begin
                            bit_cnt <= 4'd0;
                            if (word_cnt == frame_words - 1) begin
                                state <= CHECK;
                            end else if (!drdy) begin
                                sync_early <= 1'b1;
                                state      <= ABORT;
                            end else begin
                                word_cnt <= word_cnt + 1'b1;
                                state    <= CLK_LOW;
                            end
                        end
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                CHECK: begin
                    cs_n <= 1'b1;
                    sclk <= 1'b0;
                    if (!drdy && crc_idle) begin
                        state <= FINISH;
                    end else if (count == DONE_TIMEOUT - 1) begin
                        sync_late <= 1'b1;
                        state     <= ABORT;
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                FINISH: begin
                    cs_n         <= 1'b1;
                    frame_done   <= 1'b1;
                    crc_ok       <= has_header && (crc_be == hdr_crc || crc_le == hdr_crc);
                    frame_count  <= hdr_count;
                    frame_min    <= run_min;
                    frame_max    <= run_max;
                    frame_center <= run_center;
                    state        <= IDLE;
                end

                ABORT: begin
                    cs_n  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
