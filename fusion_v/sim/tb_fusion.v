`timescale 1ns / 1ps

// One optical frame through ov7670 + optical_sobel + RAM, one synthetic thermal frame in the
// RAM, then one VGA frame per view written to view_<mode>.hex (one 12-bit pixel per line).
//   optical: bright square, x 100..199, y 80..159 of 320x240
//   thermal: hot disc, radius 8, centred on thermal pixel (60, 31)

module tb_fusion;

    reg clk = 1'b0;
    reg pclk = 1'b0;
    always #5  clk  = ~clk;
    always #20 pclk = ~pclk;

    reg        vga_rst = 1'b1;
    wire       video_on, p_tick, hs_raw, vs_raw;
    wire [9:0] x, y;

    vga_controller vga_c (
        .clk_100MHz(clk), .reset(vga_rst), .hsync(hs_raw), .vsync(vs_raw),
        .video_on(video_on), .p_tick(p_tick), .x(x), .y(y)
    );

    reg        cam_vs = 1'b0;
    reg        href = 1'b0;
    reg  [7:0] d = 8'd0;
    wire [16:0] cam_addr;
    wire [15:0] cam_data;
    wire        cam_we;
    wire [8:0]  cam_col;
    wire [7:0]  cam_row;

    ov7670 cam (
        .pclk(pclk), .cam_vsync(cam_vs), .href(href), .d(d), .enable(1'b1),
        .invert_vsync(1'b0), .swap_bytes(1'b0),
        .wr_addr(cam_addr), .wr_data(cam_data), .wr_en(cam_we),
        .wr_col(cam_col), .wr_row(cam_row)
    );

    wire        opt_we;
    wire [16:0] opt_wa;
    wire [7:0]  opt_wd;

    optical_sobel sobel (
        .pclk(pclk), .in_we(cam_we), .in_addr(cam_addr), .in_col(cam_col), .in_row(cam_row),
        .in_rgb(cam_data), .thr(7'd48), .out_we(opt_we), .out_addr(opt_wa), .out_data(opt_wd)
    );

    wire [16:0] opt_ra;
    wire [7:0]  opt_rd;

    optical_frame_ram opt_buf (
        .pclk(pclk), .we(opt_we), .wr_addr(opt_wa), .wr_data(opt_wd),
        .clk(clk), .rd_addr(opt_ra), .rd_data(opt_rd)
    );

    wire [12:0] th_ra;
    wire [15:0] th_rd;

    thermal_frame_ram th_ram (
        .clk(clk), .we_a(1'b0), .bank_a(1'b0), .addr_a(13'd0), .din_a(16'd0), .dout_a(),
        .rd_bank(1'b0), .addr_b(th_ra), .dout_b(th_rd)
    );

    reg        frame_valid = 1'b0;
    reg        new_frame = 1'b0;
    reg  [1:0] mode = 2'd0;
    wire [11:0] rgb;
    wire        hs, vs;

    fusion_view view (
        .clk(clk), .tick(p_tick), .x(x), .y(y), .video_on(video_on),
        .hsync_in(hs_raw), .vsync_in(vs_raw), .frame_valid(frame_valid), .new_frame(new_frame),
        .t_min(16'd2950), .t_max(16'd3100), .mirror_x(1'b0), .flip_y(1'b0), .fixed_range(1'b0),
        .gray(1'b0), .mode(mode), .off_x(10'sd0), .off_y(10'sd0), .scale(8'd128),
        .rd_addr(th_ra), .rd_data(th_rd), .opt_addr(opt_ra), .opt_data(opt_rd),
        .rgb(rgb), .hsync(hs), .vsync(vs)
    );

    // Pixel n is on rgb for the 4 clocks ending 17 clocks after its last clock on x / y
    reg [16:0] tick_d = 17'd0;
    reg [16:0] von_d  = 17'd0;
    reg [9:0]  x_d [0:16];
    reg [9:0]  y_d [0:16];
    integer k;
    always @(posedge clk) begin
        tick_d <= {tick_d[15:0], p_tick};
        von_d  <= {von_d[15:0], video_on};
        x_d[0] <= x;
        y_d[0] <= y;
        for (k = 1; k < 17; k = k + 1) begin
            x_d[k] <= x_d[k - 1];
            y_d[k] <= y_d[k - 1];
        end
    end

    function [15:0] opt_pixel(input integer px, input integer py);
        begin
            if (px >= 100 && px < 200 && py >= 80 && py < 160)
                opt_pixel = 16'hFFFF;
            else
                opt_pixel = 16'h4208;
        end
    endfunction

    task camera_frame;
        integer r, c;
        reg [15:0] p;
        begin
            @(negedge pclk) cam_vs = 1'b1;
            repeat (20) @(negedge pclk);
            cam_vs = 1'b0;
            repeat (20) @(negedge pclk);
            for (r = 0; r < 240; r = r + 1) begin
                href = 1'b1;
                for (c = 0; c < 320; c = c + 1) begin
                    p = opt_pixel(c, r);
                    d = p[15:8];
                    @(negedge pclk);
                    d = p[7:0];
                    @(negedge pclk);
                end
                href = 1'b0;
                repeat (20) @(negedge pclk);
            end
        end
    endtask

    task capture(input [1:0] m);
        integer fd, count;
        reg [8*16-1:0] name;
        begin
            mode = m;
            name = "view_0.hex";
            name[39:32] = "0" + m;
            fd = $fopen(name, "w");
            count = 0;
            repeat (500000) @(posedge clk);   // let the new view reach the pipeline output
            while (count < 307200) begin
                @(posedge clk);
                if (tick_d[16] && von_d[16] && (count > 0 || (x_d[16] == 0 && y_d[16] == 0))) begin
                    $fdisplay(fd, "%03x", rgb);
                    count = count + 1;
                end
            end
            $fclose(fd);
        end
    endtask

    integer tx, ty, dx, dy;
    initial begin
        for (ty = 0; ty < 62; ty = ty + 1)
            for (tx = 0; tx < 80; tx = tx + 1) begin
                dx = tx - 60;
                dy = ty - 31;
                th_ram.mem[ty * 80 + tx] = (dx * dx + dy * dy <= 64) ? 16'd3100 : 16'd2950;
            end

        repeat (8) @(posedge clk);
        vga_rst = 1'b0;

        camera_frame;
        camera_frame;

        @(posedge clk);
        frame_valid <= 1'b1;
        new_frame   <= 1'b1;
        @(posedge clk);
        new_frame   <= 1'b0;
        repeat (100) @(posedge clk);

        capture(2'd0);
        capture(2'd1);
        capture(2'd2);
        capture(2'd3);
        $display("tb_fusion done");
        $finish;
    end

endmodule
