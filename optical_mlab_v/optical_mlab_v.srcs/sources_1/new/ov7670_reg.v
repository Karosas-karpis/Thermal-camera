`timescale 1ns / 1ps

// QVGA RGB565 init (based on known-good MIT / community lists).
// 16'hFFFE = wait, 16'hFFFF = end

module ov7670_reg (
    input clk,
    input [7:0] config_step,
    output reg [15:0] command
);

    always @(posedge clk) begin
        case (config_step)
            8'd0:  command <= 16'h12_80; // reset
            8'd1:  command <= 16'hFF_FE; // wait

            8'd2:  command <= 16'h12_14; // COM7 QVGA RGB (live)
            8'd3:  command <= 16'h11_80; // CLKRC match input clock
            8'd4:  command <= 16'h0C_00; // COM3
            8'd5:  command <= 16'h3E_00; // COM14 normal pclk
            8'd6:  command <= 16'h04_00; // COM1
            8'd7:  command <= 16'h40_D0; // COM15 RGB565
            8'd8:  command <= 16'h3A_04; // TSLB byte order
            8'd9:  command <= 16'h14_18; // COM9 AGC
            8'd10: command <= 16'h4F_B3; // color matrix
            8'd11: command <= 16'h50_B3;
            8'd12: command <= 16'h51_00;
            8'd13: command <= 16'h52_3D;
            8'd14: command <= 16'h53_A7;
            8'd15: command <= 16'h54_E4;
            8'd16: command <= 16'h58_9E;
            8'd17: command <= 16'h3D_C0; // COM13
            8'd18: command <= 16'h17_14; // HSTART (fixes odd colored lines)
            8'd19: command <= 16'h18_02; // HSTOP
            8'd20: command <= 16'h32_80; // HREF
            8'd21: command <= 16'h19_03; // VSTART
            8'd22: command <= 16'h1A_7B; // VSTOP
            8'd23: command <= 16'h03_0A; // VREF
            8'd24: command <= 16'h0F_41; // COM6
            8'd25: command <= 16'h1E_00; // MVFP
            8'd26: command <= 16'h33_0B; // CHLF
            8'd27: command <= 16'h3C_78; // COM12 no HREF while VSYNC low
            8'd28: command <= 16'h69_00; // GFIX
            8'd29: command <= 16'h74_00;
            8'd30: command <= 16'hB0_84; // needed for sane colors
            8'd31: command <= 16'hB1_0C;
            8'd32: command <= 16'hB2_0E;
            8'd33: command <= 16'hB3_80;
            8'd34: command <= 16'h70_3A;
            8'd35: command <= 16'h71_35;
            8'd36: command <= 16'h72_11;
            8'd37: command <= 16'h73_F0;
            8'd38: command <= 16'hA2_02;
            8'd39: command <= 16'h15_20; // COM10 PCLK does not toggle during H blank
            8'd40: command <= 16'h12_14; // COM7 again

            default: command <= 16'hFF_FF;
        endcase
    end

endmodule
