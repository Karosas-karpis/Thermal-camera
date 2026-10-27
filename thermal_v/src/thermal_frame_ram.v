`timescale 1ns / 1ps

// Two 80x62 x 16-bit thermal frames (0.1 K per LSB), simple dual-port block RAM.
// Port A: SPI reader writes into bank wr_bank. Port B: display reads bank rd_bank,
// 1-cycle latency. Banks are swapped only after a complete, aligned frame.

//Convert this to a IP block ram:)

module thermal_frame_ram (
    input             clk_a,
    input             we_a,
    input             wr_bank,
    input      [12:0] addr_a,
    input      [15:0] din_a,
    input             clk_b,
    input             rd_bank,
    input      [12:0] addr_b,
    output reg [15:0] dout_b = 16'd0
);

    localparam integer PIXELS = 4960;
    localparam integer DEPTH  = 2 * PIXELS;

    (* ram_style = "block" *) reg [15:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 16'd0;
    end

    wire [13:0] full_addr_a = wr_bank ? (addr_a + PIXELS) : {1'b0, addr_a};
    wire [13:0] full_addr_b = rd_bank ? (addr_b + PIXELS) : {1'b0, addr_b};

    always @(posedge clk_a) begin
        if (we_a)
            mem[full_addr_a] <= din_a;
    end

    always @(posedge clk_b) begin
        dout_b <= mem[full_addr_b];
    end

endmodule
