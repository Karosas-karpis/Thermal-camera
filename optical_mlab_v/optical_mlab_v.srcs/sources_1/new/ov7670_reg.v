`timescale 1ns / 1ps

// QVGA RGB565/RGB555 init (based on known-good MIT / community lists).
// 16'hFFFE = wait, 16'hFFFF = end

module ov7670_reg (
    input clk,
    input [7:0] config_step,
    input color_bar,
    input rgb555,
    output reg [15:0] command
);

    always @(posedge clk) begin
        case (config_step)
            8'd0:  command <= 16'h12_80; // reset
            8'd1:  command <= 16'hFF_FE; // wait

            8'd2:  command <= color_bar ? 16'h12_16 : 16'h12_14; // QVGA RGB, optional bars
            8'd3:  command <= 16'h11_80; // CLKRC match input clock
            8'd4:  command <= 16'h0C_00; // COM3
            8'd5:  command <= 16'h3E_00; // COM14 normal pclk
            8'd6:  command <= 16'h04_00; // COM1
            8'd7:  command <= 16'h8C_00; // disable RGB444
            8'd8:  command <= rgb555 ? 16'h40_F0 : 16'h40_D0; // COM15 RGB555/RGB565, full range
            8'd9:  command <= 16'h3A_04; // TSLB
            8'd10: command <= 16'h14_18; // COM9, 4x gain ceiling
            8'd11: command <= 16'h4F_B3; // RGB565 color matrix
            8'd12: command <= 16'h50_B3;
            8'd13: command <= 16'h51_00;
            8'd14: command <= 16'h52_3D;
            8'd15: command <= 16'h53_A7;
            8'd16: command <= 16'h54_E4;
            8'd17: command <= 16'h58_9E;
            8'd18: command <= 16'h3D_C0; // COM13 gamma + UV saturation
            8'd19: command <= 16'h17_14; // HSTART
            8'd20: command <= 16'h18_02; // HSTOP
            8'd21: command <= 16'h32_80; // HREF
            8'd22: command <= 16'h19_03; // VSTART
            8'd23: command <= 16'h1A_7B; // VSTOP
            8'd24: command <= 16'h03_0A; // VREF
            8'd25: command <= 16'h0F_41; // COM6
            8'd26: command <= 16'h1E_00; // no mirror/flip
            8'd27: command <= 16'h33_0B;
            8'd28: command <= 16'h3C_78; // no HREF during VSYNC
            8'd29: command <= 16'h69_00;
            8'd30: command <= 16'h74_00;
            8'd31: command <= 16'hB0_84; // required by common RGB565 sequences
            8'd32: command <= 16'hB1_0C;
            8'd33: command <= 16'hB2_0E;
            8'd34: command <= 16'hB3_80;
            8'd35: command <= 16'h70_3A; // scaling setup
            8'd36: command <= 16'h71_35;
            8'd37: command <= 16'h72_11;
            8'd38: command <= 16'h73_F0;
            8'd39: command <= 16'hA2_02;
            8'd40: command <= 16'h15_00; // free-running PCLK

            // Gamma curve from the OmniVision/Linux reference sequence.
            8'd41: command <= 16'h7A_20;
            8'd42: command <= 16'h7B_10;
            8'd43: command <= 16'h7C_1E;
            8'd44: command <= 16'h7D_35;
            8'd45: command <= 16'h7E_5A;
            8'd46: command <= 16'h7F_69;
            8'd47: command <= 16'h80_76;
            8'd48: command <= 16'h81_80;
            8'd49: command <= 16'h82_88;
            8'd50: command <= 16'h83_8F;
            8'd51: command <= 16'h84_96;
            8'd52: command <= 16'h85_A3;
            8'd53: command <= 16'h86_AF;
            8'd54: command <= 16'h87_C4;
            8'd55: command <= 16'h88_D7;
            8'd56: command <= 16'h89_E8;

            // Program exposure/gain limits with the automatic loops disabled.
            8'd57: command <= 16'h13_E0;
            8'd58: command <= 16'h00_00;
            8'd59: command <= 16'h10_00;
            8'd60: command <= 16'h0D_40;
            8'd61: command <= 16'h14_18;
            8'd62: command <= 16'hA5_05;
            8'd63: command <= 16'hAB_07;
            8'd64: command <= 16'h24_95;
            8'd65: command <= 16'h25_33;
            8'd66: command <= 16'h26_E3;
            8'd67: command <= 16'h9F_78;
            8'd68: command <= 16'hA0_68;
            8'd69: command <= 16'hA1_03;
            8'd70: command <= 16'hA6_D8;
            8'd71: command <= 16'hA7_D8;
            8'd72: command <= 16'hA8_F0;
            8'd73: command <= 16'hA9_90;
            8'd74: command <= 16'hAA_94;

            // White-balance tuning, then enable AGC, AWB and AEC.
            8'd75: command <= 16'h43_0A;
            8'd76: command <= 16'h44_F0;
            8'd77: command <= 16'h45_34;
            8'd78: command <= 16'h46_58;
            8'd79: command <= 16'h47_28;
            8'd80: command <= 16'h48_3A;
            8'd81: command <= 16'h59_88;
            8'd82: command <= 16'h5A_88;
            8'd83: command <= 16'h5B_44;
            8'd84: command <= 16'h5C_67;
            8'd85: command <= 16'h5D_49;
            8'd86: command <= 16'h5E_0E;
            8'd87: command <= 16'h6C_0A;
            8'd88: command <= 16'h6D_55;
            8'd89: command <= 16'h6E_11;
            8'd90: command <= 16'h6F_9F;
            8'd91: command <= 16'h6A_40;
            8'd92: command <= 16'h01_40;
            8'd93: command <= 16'h02_60;
            8'd94: command <= 16'h41_08; // automatic white-balance gain
            8'd95: command <= 16'h13_E7; // AGC + AWB + AEC

            // Reassert the selected format after all tuning writes.
            8'd96: command <= rgb555 ? 16'h40_F0 : 16'h40_D0;
            8'd97: command <= color_bar ? 16'h12_16 : 16'h12_14;

            // COM2: 1x output drive for ~10 cm jumpers (default is 2x).
            // Softens edges / reduces crosstalk on long parallel wiring.
            8'd98: command <= 16'h09_00;

            default: command <= 16'hFF_FF;
        endcase
    end

endmodule
