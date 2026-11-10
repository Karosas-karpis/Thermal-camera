`timescale 1ns / 1ps

// Fused VGA output. The optical frame is the screen reference: the full 320x240 at 2x.
// The OV7670 is mounted turned 90 degrees clockwise, so its frame is shown flipped vertically
// (camera col = x / 2, row = 239 - y / 2).
// The thermal image is aligned onto it: thermal_upscale applies scale (zoom, 128 = 8x) and
// off_x / off_y. Outside the thermal frame the thermal colour is black.
//
// mode: 0 = thermal
//       1 = optical grayscale
//       2 = thermal + optical Sobel edges
//       3 = optical grayscale, palette colour where the level is HOT_LEVEL or more
//
// Range scaling, as in the thermal-only design: frame min/max smoothed over frames (1/4 per frame),
// applied only when it moves more than HYST, widened to at least MIN_SPAN, and a serial
// divider gives scale_t = 63 * 65536 / span, so level = diff * scale_t >> 16.
//
// Latency from x / y to rgb is 19 clocks, and hsync / vsync are delayed to match:
//   thermal: 15 upscale, 1 diff, 1 level
//   optical: 3 address, 2 RAM, delayed 12 so Y arrives with the level
//   then 1 base colour, 1 edge overlay

module fusion_view (
    input                    clk,
    input                    tick,
    input             [9:0]  x,
    input             [9:0]  y,
    input                    video_on,
    input                    hsync_in,
    input                    vsync_in,
    input                    frame_valid,
    input                    new_frame,      // one-cycle pulse: t_min / t_max hold the frame just accepted
    input             [15:0] t_min,
    input             [15:0] t_max,
    input                    mirror_x,
    input                    flip_y,
    input                    fixed_range,    // 15.0 .. 40.5 C instead of frame min/max
    input                    gray,           // grayscale instead of colour palette
    input             [1:0]  mode,
    input  signed     [9:0]  off_x,          // thermal offset, 1/8 thermal pixel
    input  signed     [9:0]  off_y,
    input             [7:0]  scale,          // thermal zoom, 128 = 8x; larger shrinks it
    output            [12:0] rd_addr,
    input             [15:0] rd_data,
    output reg        [16:0] opt_addr = 17'd0,
    input             [7:0]  opt_data,
    output reg        [11:0] rgb = 12'd0,
    output                   hsync,
    output                   vsync
);

    localparam [15:0] FIXED_MIN = 16'd2882;   // 15.0 C in 0.1 K; span 255 = 25.5 C
    localparam [15:0] HYST      = 16'd6;      // 0.6 K
    localparam [15:0] MIN_SPAN  = 16'd50;     // 5.0 K
    localparam [5:0]  HOT_LEVEL = 6'd40;

    localparam integer SYNC_DELAY = 18;       // the controller's sync is already 1 clock late
    localparam integer OPT_DELAY  = 12;

    wire [15:0] t;
    wire        t_valid;

    thermal_upscale upscale (
        .clk(clk),
        .tick(tick),
        .x(x),
        .y(y),
        .mirror_x(mirror_x),
        .flip_y(flip_y),
        .zoom(scale),
        .off_x(off_x),
        .off_y(off_y),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .t(t),
        .valid(t_valid)
    );

    // Range smoothing. min_f / max_f are the frame min/max averaged over frames, with
    // 4 fractional bits. min_a / max_a are what is applied.
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

    // Target range: applied range widened to MIN_SPAN around its centre, or the fixed range.
    wire [15:0] span_a   = (max_a > min_a) ? max_a - min_a : 16'd0;
    wire [15:0] pad      = (MIN_SPAN - span_a) >> 1;
    wire        widen    = span_a < MIN_SPAN;
    wire [15:0] auto_lo  = widen ? ((min_a > pad) ? min_a - pad : 16'd0) : min_a;
    wire [15:0] auto_rng = widen ? MIN_SPAN : span_a;

    // Registered for timing; these only change between frames
    reg [15:0] tgt_lo  = 16'd0;
    reg [15:0] tgt_rng = 16'd1;
    always @(posedge clk) begin
        tgt_lo  <= fixed_range ? FIXED_MIN : auto_lo;
        tgt_rng <= fixed_range ? 16'd255 : auto_rng;
    end

    // Serial restoring divider: scale_t = (63 << 16) / tgt_rng, 22 clocks. min_q, rng_q
    // and scale_t switch together when it finishes.
    reg [15:0] min_q    = 16'd0;
    reg [15:0] rng_q    = 16'd0;
    reg [16:0] scale_t  = 17'd0;
    reg [15:0] lo_div   = 16'd0;
    reg [15:0] den      = 16'd1;
    reg [21:0] num      = 22'd0;
    reg [21:0] quo      = 22'd0;
    reg [16:0] rem      = 17'd0;
    reg [4:0]  div_cnt  = 5'd0;
    reg        div_busy = 1'b0;

    wire [16:0] trial = {rem[15:0], num[21]};
    wire        ge    = (trial >= {1'b0, den});
    wire [16:0] rem_n = ge ? trial - {1'b0, den} : trial;
    wire [21:0] quo_n = {quo[20:0], ge};

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
                scale_t  <= quo_n[16:0];
                div_busy <= 1'b0;
            end
        end
    end

    // diff clamped to the range, then * scale_t >> 16 (one DSP block)
    reg [15:0] diff_q  = 16'd0;
    reg [5:0]  level_q = 6'd0;

    wire [15:0] diff_raw = (t > min_q) ? t - min_q : 16'd0;
    wire [15:0] diff     = (diff_raw > rng_q) ? rng_q : diff_raw;
    wire [32:0] prod     = diff_q * scale_t;
    wire [5:0]  level    = (prod[32:16] > 17'd63) ? 6'd63 : prod[21:16];

    reg [1:0] tv_d = 2'b00;

    always @(posedge clk) begin
        diff_q  <= diff;
        level_q <= level;
        tv_d    <= {tv_d[0], t_valid};
    end

    wire in_frame = tv_d[1];   // thermal valid, aligned with level_q

    // Optical address: screen / 2, flipped vertically to the camera's layout. The stages
    // match the thermal pipeline timing; opt_ok is kept for frames that don't fill the screen.
    reg        [9:0]  mx     = 10'd0;
    reg        [9:0]  my     = 10'd0;
    reg signed [11:0] ox     = 12'sd0;
    reg signed [11:0] oy     = 12'sd0;
    reg               opt_ok = 1'b0;

    // Flipped vertically: screen-side row v is camera row 239 - v
    wire [7:0] cam_row = 8'd239 - oy[7:0];

    always @(posedge clk) begin
        mx <= x;
        my <= y;
        ox <= $signed({3'b000, mx[9:1]});
        oy <= $signed({3'b000, my[9:1]});
        opt_ok   <= (ox >= 12'sd0) && (ox < 12'sd320) && (oy >= 12'sd0) && (oy < 12'sd240);
        opt_addr <= {1'b0, cam_row, 8'd0} + {3'b000, cam_row, 6'd0} + {8'd0, ox[8:0]};
    end

    // opt_ok is 2 clocks ahead of opt_data
    reg [8:0] opt_dly [0:OPT_DELAY - 1];
    reg [1:0] ok_d = 2'b00;
    integer i;
    initial
        for (i = 0; i < OPT_DELAY; i = i + 1)
            opt_dly[i] = 9'd0;

    always @(posedge clk) begin
        ok_d <= {ok_d[0], opt_ok};
        opt_dly[0] <= {ok_d[1], opt_data};
        for (i = 1; i < OPT_DELAY; i = i + 1)
            opt_dly[i] <= opt_dly[i - 1];
    end

    wire [8:0] opt_px    = opt_dly[OPT_DELAY - 1];
    wire       opt_valid = opt_px[8];
    wire [3:0] luma      = opt_valid ? opt_px[7:4] : 4'd0;
    wire [1:0] edge_e    = opt_valid ? opt_px[1:0] : 2'd0;

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

    wire [11:0] thermal_px = !frame_valid ? 12'h222 :
                             !in_frame    ? 12'h000 :
                             gray         ? {3{level_q[5:2]}} : heat;
    wire [11:0] gray_px    = {3{luma}};

    // stage: base colour for the mode, and how much edge goes on top of it
    reg  [11:0] base_q = 12'd0;
    reg  [3:0]  amt_q  = 4'd0;
    reg         dark_q = 1'b0;

    always @(posedge clk) begin
        case (mode)
            2'd0:    base_q <= thermal_px;
            2'd1:    base_q <= gray_px;
            2'd2:    base_q <= thermal_px;
            default: base_q <= (frame_valid && in_frame && level_q >= HOT_LEVEL) ? thermal_px : gray_px;
        endcase

        if (mode != 2'd2)
            amt_q <= 4'd0;
        else
            case (edge_e)
                2'd0:    amt_q <= 4'd0;
                2'd1:    amt_q <= 4'd5;
                2'd2:    amt_q <= 4'd10;
                default: amt_q <= 4'd15;
            endcase

        // Bright edges vanish on the white-hot end and dark ones on the cold end
        dark_q <= in_frame && level_q[5];
    end

    function [3:0] edge_mix(input [3:0] c, input [3:0] amt, input dark);
        reg [4:0] sum;
        begin
            sum = {1'b0, c} + {1'b0, amt};
            if (dark)
                edge_mix = (c > amt) ? c - amt : 4'd0;
            else
                edge_mix = sum[4] ? 4'hF : sum[3:0];
        end
    endfunction

    // Sync and blanking delayed to match the image
    reg [SYNC_DELAY - 1:0] hs_d  = {SYNC_DELAY{1'b0}};
    reg [SYNC_DELAY - 1:0] vs_d  = {SYNC_DELAY{1'b0}};
    reg [SYNC_DELAY - 1:0] von_d = {SYNC_DELAY{1'b0}};

    always @(posedge clk) begin
        hs_d  <= {hs_d[SYNC_DELAY - 2:0], hsync_in};
        vs_d  <= {vs_d[SYNC_DELAY - 2:0], vsync_in};
        von_d <= {von_d[SYNC_DELAY - 2:0], video_on};

        if (!von_d[SYNC_DELAY - 1])
            rgb <= 12'h000;
        else
            rgb <= {edge_mix(base_q[11:8], amt_q, dark_q),
                    edge_mix(base_q[7:4],  amt_q, dark_q),
                    edge_mix(base_q[3:0],  amt_q, dark_q)};
    end

    assign hsync = hs_d[SYNC_DELAY - 1];
    assign vsync = vs_d[SYNC_DELAY - 1];

endmodule
