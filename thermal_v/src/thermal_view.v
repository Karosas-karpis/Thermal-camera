`timescale 1ns / 1ps

// Part 1 preview: nearest-neighbour 7x upscale (80x62 -> 560x434), centred on
// 640x480, auto-ranged. Colour (black-blue-purple-red-yellow-white, hot = white)
// or grayscale. Range is the frame min/max reduced to a power-of-two shift so no
// divider is needed.
// Pipeline: coords -> thermal x/y -> RAM address -> RAM data -> RGB (4 clk = 1 VGA pixel).

module thermal_view (
    input             clk,
    input      [9:0]  x,
    input      [9:0]  y,
    input             video_on,
    input             frame_valid,
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

    localparam integer X0 = 40;    // (640 - 80*7) / 2
    localparam integer Y0 = 23;    // (480 - 62*7) / 2
    localparam integer W  = 560;
    localparam integer H  = 434;
    // n / 7 == (n * 293) >> 11 exactly for n < 560
    localparam [8:0] DIV7_MUL = 9'd293;
    localparam [15:0] FIXED_MIN = 16'd2882;   // 15.0 C in 0.1 K; span 255 = 25.5 C

    wire       in_win = (x >= X0) && (x < X0 + W) && (y >= Y0) && (y < Y0 + H);
    wire [9:0] dx = x - X0;
    wire [9:0] dy = y - Y0;

    wire [18:0] tx_mul = dx * DIV7_MUL;
    wire [18:0] ty_mul = dy * DIV7_MUL;
    wire [6:0]  tx_raw = tx_mul[17:11];
    wire [5:0]  ty_raw = ty_mul[16:11];

    reg [6:0] tx1 = 7'd0;
    reg [5:0] ty1 = 6'd0;
    reg [2:0] win_d = 3'd0;
    reg [2:0] von_d = 3'd0;

    reg [15:0] min_q   = 16'd0;
    reg [3:0]  shift_q = 4'd0;
    reg        left_q  = 1'b0;

    // Shift (t_max - t_min) so its top bit lands on bit 5. The coldest pixel
    // is level 0 and the hottest is level 32..63 of 64.
    reg  [15:0] range;
    reg  [3:0]  msb_n;
    integer b;
    always @(*) begin
        if (t_max > t_min)
            range = t_max - t_min;
        else
            range = 16'd1;

        msb_n = 4'd0;
        for (b = 0; b < 16; b = b + 1)
            if (range[b])
                msb_n = b;
    end

    reg [15:0] diff;
    reg [21:0] scaled;
    reg [5:0]  level;
    always @(*) begin
        if (rd_data > min_q)
            diff = rd_data - min_q;
        else
            diff = 16'd0;

        if (left_q)
            scaled = {6'd0, diff} << shift_q;
        else
            scaled = {6'd0, diff} >> shift_q;

        if (scaled > 22'd63)
            level = 6'd63;
        else
            level = scaled[5:0];
    end

    // Heat palette: 4 linear segments of 16 levels
    wire [3:0] f = level[3:0];
    reg  [11:0] heat;
    always @(*) begin
        case (level[5:4])
            2'd0:    heat = {1'b0, f[3:1], 4'd0, f};
            2'd1:    heat = {1'b1, f[3:1], 4'd0, ~f};
            2'd2:    heat = {4'hF, f, 4'd0};
            default: heat = {4'hF, 4'hF, f};
        endcase
    end

    reg [11:0] pixel;
    always @(*) begin
        if (gray)
            pixel = {3{level[5:2]}};
        else
            pixel = heat;
    end

    always @(posedge clk) begin
        if (fixed_range) begin
            min_q   <= FIXED_MIN;
            left_q  <= 1'b0;
            shift_q <= 4'd2;
        end else begin
            min_q   <= t_min;
            left_q  <= (msb_n < 4'd5);
            if (msb_n < 4'd5)
                shift_q <= 4'd5 - msb_n;
            else
                shift_q <= msb_n - 4'd5;
        end

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
        win_d <= {win_d[1:0], in_win};
        von_d <= {von_d[1:0], video_on};

        // stage 4: colour
        if (!von_d[2] || !win_d[2])
            rgb <= 12'h000;
        else if (!frame_valid)
            rgb <= 12'h222;
        else
            rgb <= pixel;
    end

endmodule
