`timescale 1ns / 1ps

// 4-digit 7-segment readout for the Basys 3 (segments and anodes active low).
//   is_temp = 1: value is 0.1 K, shown as degrees C with one decimal ("22.5", "-5.0")
//   is_temp = 0: value shown as a plain decimal number (lowest 4 digits)
//   is_hex  = 1: value shown as 4 hex digits (overrides is_temp)
// The value is converted to BCD (shift-add-3) every ~10 ms; digits scan at ~380 Hz.

module seg7_display (
    input            clk,
    input     [15:0] value,
    input            is_temp,
    input            is_hex,
    output reg [6:0] seg = 7'h7F,   // {g,f,e,d,c,b,a}
    output reg       dp  = 1'b1,
    output reg [3:0] an  = 4'hF
);

    localparam [15:0] ZERO_C = 16'd2732;   // 273.2 K

    wire        below_zero = is_temp && (value < ZERO_C);
    wire [15:0] c10        = below_zero ? (ZERO_C - value) : (value - ZERO_C);
    wire [15:0] magnitude  = !is_temp ? value : (c10 > 16'd9999) ? 16'd9999 : c10;

    function [3:0] add3(input [3:0] d);
        add3 = (d >= 4'd5) ? d + 4'd3 : d;
    endfunction

    reg [19:0] refresh  = 20'd0;
    reg [15:0] bin      = 16'd0;
    reg [19:0] bcd      = 20'd0;
    reg [4:0]  step     = 5'd0;
    reg        busy     = 1'b0;
    reg        neg_c    = 1'b0;
    reg        temp_c   = 1'b0;
    reg [15:0] digits   = 16'd0;
    reg        show_neg = 1'b0;
    reg        show_dp  = 1'b0;

    wire [19:0] bcd_adj = {add3(bcd[19:16]), add3(bcd[15:12]), add3(bcd[11:8]),
                           add3(bcd[7:4]),   add3(bcd[3:0])};

    always @(posedge clk) begin
        refresh <= refresh + 1'b1;

        if (is_hex) begin
            digits   <= value;
            show_neg <= 1'b0;
            show_dp  <= 1'b0;
            busy     <= 1'b0;
        end else if (!busy) begin
            if (refresh == 20'd0) begin
                bin    <= magnitude;
                bcd    <= 20'd0;
                step   <= 5'd0;
                neg_c  <= below_zero;
                temp_c <= is_temp;
                busy   <= 1'b1;
            end
        end else if (step == 5'd16) begin
            digits   <= bcd[15:0];
            show_neg <= neg_c;
            show_dp  <= temp_c;
            busy     <= 1'b0;
        end else begin
            {bcd, bin} <= {bcd_adj, bin} << 1;
            step <= step + 1'b1;
        end
    end

    function [6:0] glyph(input [3:0] d);
        case (d)
            4'd0: glyph = 7'b1000000;
            4'd1: glyph = 7'b1111001;
            4'd2: glyph = 7'b0100100;
            4'd3: glyph = 7'b0110000;
            4'd4: glyph = 7'b0011001;
            4'd5: glyph = 7'b0010010;
            4'd6: glyph = 7'b0000010;
            4'd7: glyph = 7'b1111000;
            4'd8: glyph = 7'b0000000;
            4'd9: glyph = 7'b0010000;
            4'hA: glyph = 7'b0001000;
            4'hB: glyph = 7'b0000011;
            4'hC: glyph = 7'b1000110;
            4'hD: glyph = 7'b0100001;
            4'hE: glyph = 7'b0000110;
            default: glyph = 7'b0001110;   // F
        endcase
    endfunction

    localparam [6:0] BLANK = 7'b1111111;
    localparam [6:0] MINUS = 7'b0111111;

    wire [1:0] pos = refresh[17:16];
    wire [3:0] d3 = digits[15:12];
    wire [3:0] d2 = digits[11:8];
    wire [3:0] d1 = digits[7:4];
    wire [3:0] d0 = digits[3:0];
    // 0 K is "no reading yet". Showing it as °C overflows four digits and
    // looks like -73.2 because the minus replaces the leading 2 of -273.2.
    wire no_reading = is_temp && !is_hex && (value == 16'd0);

    localparam [6:0] DASH = 7'b0111111;

    always @(posedge clk) begin
        if (no_reading) begin
            case (pos)
                2'd0: an <= 4'b1110;
                2'd1: an <= 4'b1101;
                2'd2: an <= 4'b1011;
                default: an <= 4'b0111;
            endcase
            seg <= DASH;
            dp  <= 1'b1;
        end else case (pos)
            2'd0: begin an <= 4'b1110; seg <= glyph(d0); dp <= 1'b1; end
            2'd1: begin an <= 4'b1101; seg <= glyph(d1); dp <= ~show_dp; end
            2'd2: begin
                an <= 4'b1011;
                if (show_dp && d3 == 4'd0 && d2 == 4'd0)
                    seg <= show_neg ? MINUS : BLANK;
                else
                    seg <= glyph(d2);
                dp <= 1'b1;
            end
            default: begin
                an <= 4'b0111;
                if (show_neg && !(d3 == 4'd0 && d2 == 4'd0))
                    seg <= MINUS;
                else if (show_dp && d3 == 4'd0)
                    seg <= BLANK;
                else
                    seg <= glyph(d3);
                dp <= 1'b1;
            end
        endcase
    end

endmodule
