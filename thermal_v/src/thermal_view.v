`timescale 1ns / 1ps

// Part 1 preview: native 80x62, 1:1 (no upscale), centred on 640x480, auto-ranged.
// Colour (black-blue-purple-red-yellow-white, hot = white)
// or grayscale. The range is the frame min/max, smoothed over frames (1/4 per frame),
// applied only when it moves more than HYST, and widened to at least MIN_SPAN. A serial
// divider turns it into a scale (63 * 65536 / span) once per change, so
// level = diff * scale >> 16 with no power-of-two rounding.
// Pipeline: coords -> thermal x/y -> RAM address -> RAM data -> diff -> level -> RGB (6 clk, slightly over 1 VGA pixel).

module thermal_view (
    input             clk,
    input      [9:0]  x,
    input      [9:0]  y,
    input             video_on,
    input             frame_valid,
    input             new_frame,      // one-cycle pulse: t_min / t_max hold the frame just accepted
    input      [15:0] t_min,
    input      [15:0] t_max,
    input             mirror_x,
    input             flip_y,
    input             fixed_range,    // 15.0 .. 40.5 C instead of frame min/max
    input             gray,           // grayscale instead of colour palette
    output reg [12:0] rd_addr = 13'd0,
    input      [15:0] rd_data,
    output reg [11:0] rgb = 12'd0
);

    localparam integer X0 = 280;   // (640 - 80) / 2
    localparam integer Y0 = 209;   // (480 - 62) / 2
    localparam integer W  = 80;
    localparam integer H  = 62;
    localparam [15:0] FIXED_MIN = 16'd2882;   // 15.0 C in 0.1 K; span 255 = 25.5 C

    wire       in_win = (x >= X0) && (x < X0 + W) && (y >= Y0) && (y < Y0 + H);
    wire [9:0] dx = x - X0;
    wire [9:0] dy = y - Y0;

    wire [6:0]  tx_raw = dx[6:0];
    wire [5:0]  ty_raw = dy[5:0];

    reg [6:0] tx1 = 7'd0;
    reg [5:0] ty1 = 6'd0;
    reg [4:0] win_d = 5'd0;
    reg [4:0] von_d = 5'd0;
    reg [5:0] level_q = 6'd0;
    reg [15:0] diff_q = 16'd0;

    // Range smoothing. min_f / max_f are the frame min/max averaged over frames, with
    // 4 fractional bits. min_a / max_a are what is applied; they follow only when the
    // average is more than HYST away, so a single warm pixel does not make it breathe.
    localparam [15:0] HYST     = 16'd6;    // 0.6 K
    localparam [15:0] MIN_SPAN = 16'd50;   // 5.0 K

    reg [19:0] min_f = 20'd0;
    reg [19:0] max_f = 20'd0;
    reg [15:0] min_a = 16'd0;
    reg [15:0] max_a = 16'd0;
    reg        primed = 1'b0;

    wire signed [20:0] min_err = $signed({1'b0, t_min, 4'd0}) - $signed({1'b0, min_f});
    wire signed [20:0] max_err = $signed({1'b0, t_max, 4'd0}) - $signed({1'b0, max_f});
    wire        [15:0] min_e   = min_f[19:4];
    wire        [15:0] max_e   = max_f[19:4];
    wire        [15:0] min_dif = (min_e > min_a) ? min_e - min_a : min_a - min_e;
    wire        [15:0] max_dif = (max_e > max_a) ? max_e - max_a : max_a - max_e;

    always @(posedge clk) begin
        if (!frame_valid) begin
            primed <= 1'b0;
        end else if (new_frame) begin
            primed <= 1'b1;
            if (!primed) begin
                min_f <= {t_min, 4'd0};
                max_f <= {t_max, 4'd0};
                min_a <= t_min;
                max_a <= t_max;
            end else begin
                min_f <= min_f + {{1{min_err[20]}}, min_err[20:2]};
                max_f <= max_f + {{1{max_err[20]}}, max_err[20:2]};
                if (min_dif > HYST || max_dif > HYST) begin
                    min_a <= min_e;
                    max_a <= max_e;
                end
            end
        end
    end

    // Target range for the scale: applied range widened to MIN_SPAN around its centre,
    // or the fixed 15 C .. 40.5 C.
    wire [15:0] span_a   = (max_a > min_a) ? max_a - min_a : 16'd0;
    wire [15:0] pad      = (MIN_SPAN - span_a) >> 1;
    wire        widen    = span_a < MIN_SPAN;
    wire [15:0] auto_lo  = widen ? ((min_a > pad) ? min_a - pad : 16'd0) : min_a;
    wire [15:0] auto_rng = widen ? MIN_SPAN : span_a;
    wire [15:0] tgt_lo   = fixed_range ? FIXED_MIN : auto_lo;
    wire [15:0] tgt_rng  = fixed_range ? 16'd255 : auto_rng;

    // Serial restoring divider: scale = (63 << 16) / tgt_rng, 22 clocks. min_q, rng_q
    // and scale switch together when it finishes.
    reg [15:0] min_q   = 16'd0;
    reg [15:0] rng_q   = 16'd0;
    reg [16:0] scale   = 17'd0;
    reg [15:0] lo_div  = 16'd0;
    reg [15:0] den     = 16'd1;
    reg [21:0] num     = 22'd0;
    reg [21:0] quo     = 22'd0;
    reg [16:0] rem     = 17'd0;
    reg [4:0]  div_cnt = 5'd0;
    reg        div_busy = 1'b0;

    wire [16:0] trial   = {rem[15:0], num[21]};
    wire        ge      = (trial >= {1'b0, den});
    wire [16:0] rem_n   = ge ? trial - {1'b0, den} : trial;
    wire [21:0] quo_n   = {quo[20:0], ge};

    always @(posedge clk) begin
        if (!div_busy) begin
            if (tgt_lo != min_q || tgt_rng != rng_q) begin
                lo_div   <= tgt_lo;
                den      <= tgt_rng;
                num      <= 22'd4128768;   // 63 << 16
                quo      <= 22'd0;
                rem      <= 17'd0;
                div_cnt  <= 5'd22;
                div_busy <= 1'b1;
            end
        end else begin
            rem     <= rem_n;
            quo     <= quo_n;
            num     <= {num[20:0], 1'b0};
            div_cnt <= div_cnt - 1'b1;
            if (div_cnt == 5'd1) begin
                min_q    <= lo_div;
                rng_q    <= den;
                scale    <= quo_n[16:0];
                div_busy <= 1'b0;
            end
        end
    end

    // diff clamped to the range, then * scale >> 16 (one DSP block)
    wire [15:0] diff_raw = (rd_data > min_q) ? rd_data - min_q : 16'd0;
    wire [15:0] diff     = (diff_raw > rng_q) ? rng_q : diff_raw;
    wire [32:0] prod     = diff_q * scale;
    wire [5:0]  level    = (prod[32:16] > 17'd63) ? 6'd63 : prod[21:16];

    // Heat palette: 4 linear segments of 16 levels
    wire [3:0] f = level_q[3:0];
    reg  [11:0] heat;
    always @(*) begin
        case (level_q[5:4])
            2'd0:    heat = {1'b0, f[3:1], 4'd0, f};
            2'd1:    heat = {1'b1, f[3:1], 4'd0, ~f};
            2'd2:    heat = {4'hF, f, 4'd0};
            default: heat = {4'hF, 4'hF, f};
        endcase
    end

    reg [11:0] pixel;
    always @(*) begin
        if (gray)
            pixel = {3{level_q[5:2]}};
        else
            pixel = heat;
    end

    always @(posedge clk) begin
        // stage 1: thermal pixel coordinates
        if (mirror_x)
            tx1 <= 7'd79 - tx_raw;
        else
            tx1 <= tx_raw;

        if (flip_y)
            ty1 <= 6'd61 - ty_raw;
        else
            ty1 <= ty_raw;

        // stage 2: RAM address (ty * 80 + tx)
        rd_addr <= {ty1, 6'd0} + {ty1, 4'd0} + tx1;

        // stage 3 is the RAM read; flags follow the pipeline
        win_d <= {win_d[3:0], in_win};
        von_d <= {von_d[3:0], video_on};

        // stage 4: offset from the range minimum
        diff_q <= diff;

        // stage 5: scale to a 6-bit level (split from the palette for timing)
        level_q <= level;

        // stage 6: colour
        if (!von_d[4] || !win_d[4])
            rgb <= 12'h000;
        else if (!frame_valid)
            rgb <= 12'h222;
        else
            rgb <= pixel;
    end

endmodule
