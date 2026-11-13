`timescale 1ns / 1ps

// thermal_hotspot: first frame sets the box, the reading is the 12-frame average, the box
// stays put inside the margin and moves only at the end of a 12-frame window.

module tb_hotspot;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg         reset = 1'b1;
    reg         rd_start = 1'b0, frame_done = 1'b0, we = 1'b0;
    reg  [12:0] addr = 13'd0;
    reg  [15:0] data = 16'd0;
    wire        valid;
    wire [6:0]  col;
    wire [5:0]  row;
    wire [15:0] text;

    thermal_hotspot dut (
        .clk(clk), .reset(reset), .rd_start(rd_start), .frame_done(frame_done),
        .we(we), .addr(addr), .data(data), .valid(valid), .col(col), .row(row), .text(text)
    );

    integer errors = 0;

    task check(input [8*24-1:0] what, input integer got, input integer expected);
        if (got !== expected) begin
            errors = errors + 1;
            $display("FAIL %0s: got %0d (0x%0h), expected %0d (0x%0h)", what, got, got, expected, expected);
        end
    endtask

    // One frame: base everywhere, pixel a1 = v1, pixel a2 = v2
    task frame(input integer base, input integer a1, input integer v1, input integer a2, input integer v2);
        integer i;
        begin
            @(negedge clk) rd_start = 1'b1;
            @(negedge clk) rd_start = 1'b0;
            for (i = 0; i < 4960; i = i + 1) begin
                we   = 1'b1;
                addr = i;
                data = (i == a1) ? v1 : (i == a2) ? v2 : base;
                @(negedge clk);
            end
            we = 1'b0;
            repeat (4) @(negedge clk);
            frame_done = 1'b1;
            @(negedge clk) frame_done = 1'b0;
            repeat (200) @(negedge clk);
        end
    endtask

    localparam integer A = 31 * 80 + 60;   // col 60, row 31
    localparam integer B = 10 * 80 + 5;    // col 5, row 10
    integer n;

    initial begin
        repeat (4) @(negedge clk);
        reset = 1'b0;

        // first frame sets the box: 310.0 K = 36.8 C
        frame(2950, A, 3100, -1, 0);
        check("valid", valid, 1);
        check("col", col, 60);
        check("row", row, 31);
        check("text 36.8", text, {4'd10, 4'd3, 4'd6, 4'd8});

        // 12 frames: box pixel alternates 309.0 / 311.2 (mean 310.1), another pixel is
        // hotter but inside the 1 K margin -> box stays, reading is the average 36.9
        for (n = 0; n < 11; n = n + 1) begin
            frame(2950, A, (n % 2) ? 3112 : 3090, B, 3120);
            check("no change mid-window", {col, row, text}, {7'd60, 6'd31, 4'd10, 4'd3, 4'd6, 4'd8});
        end
        frame(2950, A, 3112, B, 3120);
        check("col stays", col, 60);
        check("row stays", row, 31);
        check("text avg 36.9", text, {4'd10, 4'd3, 4'd6, 4'd9});

        // another pixel well above the box pixel: moves only when the window ends
        for (n = 0; n < 11; n = n + 1)
            frame(2950, A, 3100, B, 4000);
        check("col before window end", col, 60);
        frame(2950, A, 3100, B, 4000);
        check("col moved", col, 5);
        check("row moved", row, 10);
        check("text 126.8", text, {4'd1, 4'd2, 4'd6, 4'd8});

        // below zero, after a reset: 265.0 K = -8.2 C
        @(negedge clk) reset = 1'b1;
        @(negedge clk) reset = 1'b0;
        check("valid cleared", valid, 0);
        frame(2600, B, 2650, -1, 0);
        check("text -8.2", text, {4'd10, 4'd11, 4'd8, 4'd2});
        check("col", col, 5);

        if (errors == 0)
            $display("PASS");
        else
            $display("FAILED with %0d errors", errors);
        $finish;
    end

endmodule
