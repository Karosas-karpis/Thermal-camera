`timescale 1ns / 1ps

// Hottest-spot tracker for the marker box and its temperature reading.
// Watches the filtered pixels on their way into the frame RAM. Every frame it finds the
// hottest pixel (230..800 K only) and notes the value at the current box position.
// The outputs change once per FRAMES thermal frames (12 frames ~ 1 s at 12.5 FPS):
//   - the reading is the box pixel averaged over those frames
//   - the box only moves if, in the last frame, the hottest pixel is more than MARGIN
//     above the box pixel; the reading is then that pixel's value in that frame
// Until there is a box, the first complete frame sets it.
// col / row / text / valid all change together. text is four glyph codes
// {c0, c1, c2, tenths} for "c0 c1 c2 . tenths C" in Celsius:
//   0..9 digits, 10 blank, 11 minus (marker_text adds '.' and 'C').

module thermal_hotspot #(
    parameter integer FRAMES = 12,    // 2..16
    parameter integer MARGIN = 10     // 1.0 K
) (
    input             clk,
    input             reset,
    input             rd_start,     // one-cycle pulse: a new SPI frame read begins
    input             frame_done,   // one-cycle pulse: the frame was complete and aligned
    input             we,
    input      [12:0] addr,
    input      [15:0] data,

    output reg        valid = 1'b0,
    output reg [6:0]  col   = 7'd0,
    output reg [5:0]  row   = 6'd0,
    output reg [15:0] text  = {4{4'd10}}
);

    localparam [15:0] TEMP_MIN  = 16'd2300;   // 230 K, as in thermal_filter
    localparam [15:0] TEMP_MAX  = 16'd8000;   // 800 K
    localparam [15:0] ZERO_C    = 16'd2732;   // 0 C in 0.1 K
    localparam [14:0] RECIP     = (262144 + FRAMES / 2) / FRAMES;   // 2^18 / FRAMES
    localparam [3:0]  G_BLANK   = 4'd10;
    localparam [3:0]  G_MINUS   = 4'd11;

    // ---- per frame: hottest pixel, and the value at the box ----
    reg        seen     = 1'b0;
    reg [15:0] max_val  = 16'd0;
    reg [12:0] max_addr = 13'd0;
    reg        cur_seen = 1'b0;
    reg [15:0] cur_val  = 16'd0;
    reg [12:0] box_addr = 13'd0;

    wire in_rng = (data >= TEMP_MIN) && (data <= TEMP_MAX);

    always @(posedge clk) begin
        if (reset || rd_start) begin
            seen     <= 1'b0;
            cur_seen <= 1'b0;
        end else if (we) begin
            if (in_rng && (!seen || data > max_val)) begin
                seen     <= 1'b1;
                max_val  <= data;
                max_addr <= addr;
            end
            if (addr == box_addr) begin
                cur_seen <= 1'b1;
                cur_val  <= data;
            end
        end
    end

    // ---- once per FRAMES frames: decide, convert, publish ----
    localparam [2:0]
        IDLE = 3'd0,
        AVG1 = 3'd1,
        AVG2 = 3'd2,
        CONV = 3'd3,
        DIV  = 3'd4,
        BCD  = 3'd5,
        PUB  = 3'd6;

    reg [2:0]  state    = IDLE;
    reg        have     = 1'b0;      // a box position exists
    reg [3:0]  win      = 4'd0;
    reg [19:0] sum      = 20'd0;
    reg [19:0] sum_full = 20'd0;
    reg [34:0] prod     = 35'd0;
    reg [15:0] reading  = 16'd0;     // 0.1 K

    reg [12:0] rem_a = 13'd0;        // box_addr -> row, col
    reg [5:0]  row_c = 6'd0;
    reg        neg   = 1'b0;
    reg [13:0] mag   = 14'd0;        // |tenths of a degree C|, at most 9999
    reg [3:0]  d3 = 4'd0, d2 = 4'd0, d1 = 4'd0;

    wire [19:0] sum_n  = sum + {4'd0, cur_val};
    wire        hotter = {1'b0, max_val} > ({1'b0, cur_val} + MARGIN);
    wire [34:0] prod_r = prod + 35'd131072;
    wire [15:0] mag_w  = (reading < ZERO_C) ? ZERO_C - reading : reading - ZERO_C;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            have  <= 1'b0;
            valid <= 1'b0;
            win   <= 4'd0;
            sum   <= 20'd0;
        end else begin
            case (state)
                IDLE: if (frame_done) begin
                    if (!have) begin
                        if (seen) begin
                            have     <= 1'b1;
                            box_addr <= max_addr;
                            reading  <= max_val;
                            win      <= 4'd0;
                            sum      <= 20'd0;
                            state    <= CONV;
                        end
                    end else if (win == FRAMES - 1) begin
                        win      <= 4'd0;
                        sum      <= 20'd0;
                        sum_full <= sum_n;
                        if (seen && (!cur_seen || hotter)) begin
                            box_addr <= max_addr;
                            reading  <= max_val;
                            state    <= CONV;
                        end else begin
                            state <= AVG1;
                        end
                    end else begin
                        win <= win + 1'b1;
                        sum <= sum_n;
                    end
                end

                AVG1: begin
                    prod  <= sum_full * RECIP;
                    state <= AVG2;
                end

                AVG2: begin
                    reading <= prod_r[33:18];
                    state   <= CONV;
                end

                CONV: begin
                    rem_a <= box_addr;
                    row_c <= 6'd0;
                    neg   <= (reading < ZERO_C);
                    mag   <= (mag_w > 16'd9999) ? 14'd9999 : mag_w[13:0];
                    d3    <= 4'd0;
                    d2    <= 4'd0;
                    d1    <= 4'd0;
                    state <= DIV;
                end

                DIV: begin
                    if (rem_a >= 13'd80) begin
                        rem_a <= rem_a - 13'd80;
                        row_c <= row_c + 1'b1;
                    end else begin
                        state <= BCD;
                    end
                end

                BCD: begin
                    if (mag >= 14'd1000) begin
                        mag <= mag - 14'd1000;
                        d3  <= d3 + 1'b1;
                    end else if (mag >= 14'd100) begin
                        mag <= mag - 14'd100;
                        d2  <= d2 + 1'b1;
                    end else if (mag >= 14'd10) begin
                        mag <= mag - 14'd10;
                        d1  <= d1 + 1'b1;
                    end else begin
                        state <= PUB;
                    end
                end

                PUB: begin
                    valid <= 1'b1;
                    col   <= rem_a[6:0];
                    row   <= row_c;
                    if (d3 != 4'd0)
                        text <= {d3, d2, d1, mag[3:0]};
                    else if (d2 != 4'd0)
                        text <= {neg ? G_MINUS : G_BLANK, d2, d1, mag[3:0]};
                    else
                        text <= {G_BLANK, neg ? G_MINUS : G_BLANK, d1, mag[3:0]};
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
