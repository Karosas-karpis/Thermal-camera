`timescale 1ns / 1ps

// Temporal filter between the SPI reader and the frame RAM, plus frame min/max.
// Each pixel: new = old + (sample - old) / 4, where old is the same pixel of the
// frame being displayed (the previous accepted frame), read through RAM port A.
// A sample more than the motion threshold from old (2 K, or 5 K with motion_wide), or
// any pixel while seed is high (no previous frame), is stored unfiltered so moving
// objects leave no trail.
// Because the old frame is the displayed bank, a rejected frame (bank not swapped)
// never feeds the filter.
//
// Pixels arrive at least ~100 clocks apart, so port A time-shares:
//   t0   : read request (displayed bank)      pix_we
//   t0+1 : old value on a_dout, blend registered
//   t0+2 : write to the fill bank, min/max update
// frame_min / frame_max cover pixels in 230..800 K only, like the reader's.

module thermal_filter (
    input             clk,
    input             seed,
    input             motion_wide,   // motion threshold 5 K instead of 2 K
    input             disp_bank,
    input             wr_bank,
    input             frame_done,

    input             pix_we,
    input      [12:0] pix_addr,
    input      [15:0] pix_data,

    output            a_we,
    output            a_bank,
    output     [12:0] a_addr,
    output     [15:0] a_din,
    input      [15:0] a_dout,

    output reg [15:0] frame_min = 16'd0,
    output reg [15:0] frame_max = 16'd0
);

    localparam signed [16:0] MOTION_NARROW = 17'sd20;   // 2.0 K
    localparam signed [16:0] MOTION_WIDE   = 17'sd50;   // 5.0 K
    localparam        [15:0] TEMP_MIN      = 16'd2300;  // 230 K, as in mi48_spi_reader
    localparam        [15:0] TEMP_MAX      = 16'd8000;  // 800 K

    reg        we_q   = 1'b0;
    reg [12:0] addr_q = 13'd0;
    reg [15:0] data_q = 16'd0;

    reg        we_w   = 1'b0;
    reg [12:0] addr_w = 13'd0;
    reg [15:0] next_w = 16'd0;

    always @(posedge clk) begin
        we_q   <= pix_we;
        addr_q <= pix_addr;
        data_q <= pix_data;
    end

    wire signed [16:0] d      = $signed({1'b0, data_q}) - $signed({1'b0, a_dout});
    wire signed [16:0] motion = motion_wide ? MOTION_WIDE : MOTION_NARROW;
    wire               big    = (d > motion) || (d < -motion);
    wire signed [16:0] step   = (d + 17'sd2) >>> 2;
    wire        [15:0] blend  = a_dout + step[15:0];
    wire        [15:0] next   = (seed || big) ? data_q : blend;

    always @(posedge clk) begin
        we_w   <= we_q;
        addr_w <= addr_q;
        next_w <= next;
    end

    assign a_we   = we_w;
    assign a_bank = we_w ? wr_bank : disp_bank;
    assign a_addr = we_w ? addr_w : pix_addr;
    assign a_din  = next_w;

    reg [15:0] run_min = 16'd0;
    reg [15:0] run_max = 16'd0;
    reg        seen    = 1'b0;

    wire in_rng   = (next_w >= TEMP_MIN) && (next_w <= TEMP_MAX);
    wire seen_eff = seen && (addr_w != 13'd0);

    always @(posedge clk) begin
        if (we_w) begin
            if (in_rng) begin
                if (!seen_eff || next_w < run_min)
                    run_min <= next_w;
                if (!seen_eff || next_w > run_max)
                    run_max <= next_w;
                seen <= 1'b1;
            end else if (addr_w == 13'd0) begin
                seen <= 1'b0;
            end
        end

        if (frame_done) begin
            frame_min <= run_min;
            frame_max <= run_max;
        end
    end

endmodule
