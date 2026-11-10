`timescale 1ns / 1ps

// 640x480 at 60 Hz VGA timing from the 100 MHz clock.
// 800 pixels per line x 525 lines x 60 frames ~ 25.2 MHz pixel rate; p_tick is a
// one-in-four clock enable, not a separate clock. x / y count the whole line and
// frame (0..799, 0..524); video_on marks the visible 640x480 area.
// hsync / vsync are active high and registered, so they come one clock after x / y.

module vga_controller (
    input        clk_100MHz,
    input        reset,
    output       video_on,
    output       hsync,
    output       vsync,
    output       p_tick,
    output [9:0] x,
    output [9:0] y
);

    localparam integer HD   = 640;   // visible pixels
    localparam integer HF   = 16;    // front porch
    localparam integer HB   = 48;    // back porch
    localparam integer HR   = 96;    // sync pulse
    localparam integer HMAX = HD + HF + HB + HR - 1;

    // Vertical sync sits after 33 lines and the back porch is 10. VESA has these the other
    // way round, but the monitor locks to it and the alignment was set on it, so it stays.
    localparam integer VD   = 480;
    localparam integer VF   = 33;
    localparam integer VB   = 10;
    localparam integer VR   = 2;
    localparam integer VMAX = VD + VF + VB + VR - 1;

    reg [1:0] tick_cnt = 2'd0;
    always @(posedge clk_100MHz or posedge reset)
        if (reset)
            tick_cnt <= 2'd0;
        else
            tick_cnt <= tick_cnt + 1'b1;

    wire tick = (tick_cnt == 2'd0);

    reg [9:0] h_count = 10'd0;
    reg [9:0] v_count = 10'd0;
    reg       h_sync  = 1'b0;
    reg       v_sync  = 1'b0;

    wire h_sync_next = (h_count >= HD + HF) && (h_count < HD + HF + HR);
    wire v_sync_next = (v_count >= VD + VF) && (v_count < VD + VF + VR);

    always @(posedge clk_100MHz or posedge reset)
        if (reset) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
            h_sync  <= 1'b0;
            v_sync  <= 1'b0;
        end else begin
            h_sync <= h_sync_next;
            v_sync <= v_sync_next;

            if (tick) begin
                if (h_count == HMAX) begin
                    h_count <= 10'd0;
                    if (v_count == VMAX)
                        v_count <= 10'd0;
                    else
                        v_count <= v_count + 1'b1;
                end else begin
                    h_count <= h_count + 1'b1;
                end
            end
        end

    assign video_on = (h_count < HD) && (v_count < VD);
    assign hsync    = h_sync;
    assign vsync    = v_sync;
    assign x        = h_count;
    assign y        = v_count;
    assign p_tick   = tick;

endmodule
