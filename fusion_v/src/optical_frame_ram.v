`timescale 1ns / 1ps

// One 320x240 x 8-bit {Y[7:2], E[1:0]} optical frame in block RAM. Written at pclk, read at
// 100 MHz, 2-cycle read latency. Single buffer: a moving image can tear, like the optical design.

module optical_frame_ram (
    input             pclk,
    input             we,
    input      [16:0] wr_addr,
    input      [7:0]  wr_data,

    input             clk,
    input      [16:0] rd_addr,
    output reg [7:0]  rd_data = 8'd0
);

    localparam integer PIXELS = 76800;

    (* ram_style = "block" *) reg [7:0] mem [0:PIXELS - 1];

    reg [7:0] dout = 8'd0;

    // Block RAM powers up as 0; only the simulator needs telling
    // synthesis translate_off
    integer i;
    initial
        for (i = 0; i < PIXELS; i = i + 1)
            mem[i] = 8'd0;
    // synthesis translate_on

    always @(posedge pclk)
        if (we)
            mem[wr_addr] <= wr_data;

    always @(posedge clk) begin
        dout    <= mem[rd_addr];
        rd_data <= dout;
    end

endmodule
