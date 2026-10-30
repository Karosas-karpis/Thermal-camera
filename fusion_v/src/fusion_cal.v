`timescale 1ns / 1ps

// Alignment settings on the buttons. A held button repeats at ~12 Hz, which also takes
// care of contact bounce.
//   cal_alt = 0: U/D/L/R move the optical image up/down/left/right
//   cal_alt = 1: U/D zoom the optical image in/out, L/R lower/raise the edge threshold
// reset puts everything back to the defaults.

module fusion_cal #(
    parameter [7:0] SCALE_INIT = 8'd128,
    parameter [6:0] THR_INIT   = 7'd48
) (
    input                   clk,
    input                   reset,
    input                   btnU,
    input                   btnD,
    input                   btnL,
    input                   btnR,
    input                   cal_alt,
    output reg signed [9:0] off_x = 10'sd0,
    output reg signed [9:0] off_y = 10'sd0,
    output reg        [7:0] scale = SCALE_INIT,
    output reg        [6:0] thr   = THR_INIT
);

    localparam signed [9:0] OFF_LIMIT = 10'sd300;
    localparam [7:0]        SCALE_MIN = 8'd32;
    localparam [6:0]        THR_MIN   = 7'd4;

    reg [1:0] u_s = 2'd0, d_s = 2'd0, l_s = 2'd0, r_s = 2'd0;
    always @(posedge clk) begin
        u_s <= {u_s[0], btnU};
        d_s <= {d_s[0], btnD};
        l_s <= {l_s[0], btnL};
        r_s <= {r_s[0], btnR};
    end

    reg  [22:0] rep  = 23'd0;
    wire        step = &rep;

    always @(posedge clk) begin
        rep <= rep + 1'b1;

        if (reset) begin
            off_x <= 10'sd0;
            off_y <= 10'sd0;
            scale <= SCALE_INIT;
            thr   <= THR_INIT;
        end else if (step) begin
            if (!cal_alt) begin
                // The offset is added to the read address, so the image moves the other way
                if (u_s[1] && off_y < OFF_LIMIT)
                    off_y <= off_y + 1'b1;
                if (d_s[1] && off_y > -OFF_LIMIT)
                    off_y <= off_y - 1'b1;
                if (l_s[1] && off_x < OFF_LIMIT)
                    off_x <= off_x + 1'b1;
                if (r_s[1] && off_x > -OFF_LIMIT)
                    off_x <= off_x - 1'b1;
            end else begin
                if (u_s[1] && scale > SCALE_MIN)
                    scale <= scale - 1'b1;
                if (d_s[1] && scale != 8'hFF)
                    scale <= scale + 1'b1;
                if (l_s[1] && thr > THR_MIN)
                    thr <= thr - 1'b1;
                if (r_s[1] && thr != 7'h7F)
                    thr <= thr + 1'b1;
            end
        end
    end

endmodule
