`timescale 1ns / 1ps

// MI48 bring-up + SPI capture against the behavioural model.
// Checks: register writes, FRAME_MODE readback, SENXOR_TYPE, full frames in the
// RAM bank, min/max/centre, header CRC, and recovery from SCLK glitches:
//   1 extra edge   -> frame still aligned but CRC fails
//   48 extra edges -> DATA_READY falls early, frame dropped (sync_early)
//   20 missed edges-> DATA_READY stays high, reader realigns (sync_late)

module tb_thermal_capture;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg reset = 1'b1;

    wire scl, sda;
    pullup (scl);
    pullup (sda);

    wire rst_n, sclk, mosi, miso, cs_n, drdy;
    wire config_done, i2c_error;
    wire [7:0] sensor_type, frame_mode;

    mi48_ctrl #(
        .FRAME_RATE_DIV(8'd4),
        .QUARTER_TICKS(10),
        .RESET_CYCLES(100),
        .BOOT_CYCLES(1_000),
        .POLL_CYCLES(2_000),
        .RETRY_CYCLES(2_000),
        .I2C_TIMEOUT(100_000)
    ) ctrl (
        .clk(clk),
        .reset(reset),
        .thermal_rst_n(rst_n),
        .scl(scl),
        .sda(sda),
        .config_done(config_done),
        .i2c_error(i2c_error),
        .sensor_type(sensor_type),
        .frame_mode(frame_mode)
    );

    wire        pix_we;
    wire [12:0] pix_addr;
    wire [15:0] pix_data;
    wire        frame_done, crc_ok;
    wire [15:0] frame_count, frame_min, frame_max, frame_center;
    wire        sync_early, sync_late;

    mi48_spi_reader #(
        .SCLK_HALF(3),
        .CS_SETUP(4),
        .DONE_TIMEOUT(1_000)
    ) reader (
        .clk(clk),
        .reset(reset),
        .enable(config_done),
        .has_header(~frame_mode[5]),
        .data_ready(drdy),
        .miso(miso),
        .sclk(sclk),
        .cs_n(cs_n),
        .mosi(mosi),
        .pix_we(pix_we),
        .pix_addr(pix_addr),
        .pix_data(pix_data),
        .frame_done(frame_done),
        .crc_ok(crc_ok),
        .frame_count(frame_count),
        .frame_min(frame_min),
        .frame_max(frame_max),
        .frame_center(frame_center),
        .sync_early(sync_early),
        .sync_late(sync_late)
    );

    reg wr_bank = 1'b0;
    always @(posedge clk)
        if (frame_done)
            wr_bank <= ~wr_bank;

    wire [15:0] unused_dout;

    thermal_frame_ram ram (
        .clk_a(clk),
        .we_a(pix_we),
        .wr_bank(wr_bank),
        .addr_a(pix_addr),
        .din_a(pix_data),
        .clk_b(clk),
        .rd_bank(~wr_bank),
        .addr_b(13'd0),
        .dout_b(unused_dout)
    );

    mi48_model #(
        .SENXOR_TYPE(8'h03),
        .BOOT_NS(50_000),
        .FRAME_GAP_NS(100_000)
    ) sensor (
        .rst_n(rst_n),
        .scl(scl),
        .sda(sda),
        .sclk(sclk),
        .mosi(mosi),
        .cs_n(cs_n),
        .miso(miso),
        .data_ready(drdy)
    );

    integer errors = 0;

    task check(input [255:0] what, input [31:0] got, input [31:0] expected);
        begin
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: got %0d (0x%0h), expected %0d (0x%0h)", what, got, got, expected, expected);
            end
        end
    endtask

    function [15:0] expected_pixel(input integer i, input integer f);
        expected_pixel = 2900 + (i % 80) + 2 * (i / 80) + f;
    endfunction

    task wait_frame;
        begin
            @(posedge frame_done);
            @(posedge clk);
            #1;
        end
    endtask

    // Frame just completed was written to the bank before the toggle.
    task check_frame;
        integer i, f, base;
        begin
            f = frame_count;
            base = wr_bank ? 0 : 4960;
            for (i = 0; i < 4960; i = i + 1)
                check("pixel", ram.mem[base + i], expected_pixel(i, f));
            check("frame_min", frame_min, expected_pixel(0, f));
            check("frame_max", frame_max, expected_pixel(4959, f));
            check("frame_center", frame_center, expected_pixel(31 * 80 + 40, f));
            check("crc_ok", crc_ok, 1'b1);
            $display("[%0t] frame %0d checked (min %0d, max %0d, centre %0d, crc ok)",
                     $time, f, frame_min, frame_max, frame_center);
        end
    endtask

    integer last;

    initial begin
        #200;
        reset = 1'b0;

        wait (config_done);
        $display("[%0t] config_done, SENXOR_TYPE=0x%02h FRAME_MODE=0x%02h", $time, sensor_type, frame_mode);
        check("frame_mode", frame_mode, 8'h02);
        check("sensor_type", sensor_type, 8'h03);
        check("frame_rate reg", sensor.regs[8'hB4], 8'h04);
        check("i2c_error", i2c_error, 1'b0);

        wait_frame;
        check_frame;
        check("frame 0 count", frame_count, 0);

        wait_frame;
        check_frame;
        check("frame 1 count", frame_count, 1);

        // One extra edge: still aligned by DATA_READY, but the data is shifted.
        sensor.extra_edges = 1;
        wait_frame;
        check("1-bit slip crc_ok", crc_ok, 1'b0);
        check("1-bit slip sync flags", {sync_early, sync_late}, 2'b00);
        $display("[%0t] 1-bit slip: frame %0d flagged by CRC", $time, frame_count);

        wait_frame;
        check_frame;
        last = frame_count;

        // Many extra edges: DATA_READY falls early, frame dropped.
        sensor.extra_edges = 48;
        wait_frame;
        check("sync_early", sync_early, 1'b1);
        check("frame after early drop", frame_count, last + 2);
        check_frame;
        $display("[%0t] early DATA_READY: frame dropped, recovered at frame %0d", $time, frame_count);
        last = frame_count;

        // Missed edges: DATA_READY stays high, reader drains and realigns.
        sensor.missed_edges = 20;
        wait_frame;
        check("sync_late", sync_late, 1'b1);
        check("frame after late drop", frame_count, last + 2);
        check_frame;
        $display("[%0t] late DATA_READY: frame dropped, recovered at frame %0d", $time, frame_count);

        repeat (50) @(posedge clk);
        check("drdy released", drdy, 1'b0);

        if (errors == 0)
            $display("PASS");
        else
            $display("FAILED with %0d errors", errors);
        $finish;
    end

    initial begin
        #60_000_000;
        $display("FAIL: timeout (config_done=%b i2c_error=%b)", config_done, i2c_error);
        $finish;
    end

endmodule
