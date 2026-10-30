`timescale 1ns / 1ps

// Two 80x62 x 16-bit thermal frames (0.1 K per LSB) in one true dual-port block RAM
// (inferred, 16 x 9920, common clock, 1-cycle read latency on both ports).
// Port A (thermal_filter): reads the displayed bank (previous frame) and writes the
// bank being filled, one bank per access. Port B: display reads bank rd_bank.

module thermal_frame_ram (
    input             clk,
    // port A: read/write
    input             we_a,
    input             bank_a,
    input      [12:0] addr_a,
    input      [15:0] din_a,
    output reg [15:0] dout_a,
    // port B: read
    input             rd_bank,
    input      [12:0] addr_b,
    output reg [15:0] dout_b
);

    localparam integer PIXELS = 4960;

    reg [15:0] mem [0:2 * PIXELS - 1];

    wire [13:0] full_addr_a = bank_a  ? addr_a + PIXELS : {1'b0, addr_a};
    wire [13:0] full_addr_b = rd_bank ? addr_b + PIXELS : {1'b0, addr_b};

    always @(posedge clk) begin
        dout_a <= mem[full_addr_a];
        if (we_a)
            mem[full_addr_a] <= din_a;
    end

    always @(posedge clk)
        dout_b <= mem[full_addr_b];

endmodule
