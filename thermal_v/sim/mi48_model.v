`timescale 1ns / 1ps

// Behavioural MI48Ax model for simulation only.
//   I2C slave: register read/write, STATUS.BOOTING_UP for BOOT_NS after reset
//   SPI slave (mode 0): 80 header words + 4960 pixels per frame
//   DATA_READY: rises when a frame is ready, falls after the full frame is read
// Pixel i of frame f = 2900 + (i % 80) + 2 * (i / 80) + f

module mi48_model #(
    parameter [6:0]   I2C_ADDR     = 7'h40,
    parameter [7:0]   SENXOR_TYPE  = 8'h03,
    parameter integer BOOT_NS      = 50_000,
    parameter integer FRAME_GAP_NS = 100_000
) (
    input      rst_n,
    inout      scl,
    inout      sda,
    input      sclk,
    input      mosi,
    input      cs_n,
    output     miso,
    output reg data_ready = 1'b0
);

    localparam integer FRAME_BITS = 5040 * 16;

    reg [7:0] regs [0:255];
    reg       booting = 1'b1;

    task reset_regs;
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1)
                regs[i] = 8'h00;
            regs[8'hB1] = 8'h20;
            regs[8'hB4] = 8'h04;
            regs[8'hBA] = SENXOR_TYPE;
            booting = 1'b1;
        end
    endtask

    initial reset_regs;
    always @(negedge rst_n) reset_regs;
    always @(posedge rst_n) begin
        #(BOOT_NS);
        if (rst_n)
            booting = 1'b0;
    end

    function [7:0] read_reg(input [7:0] a);
        read_reg = (a == 8'hB6) ? {2'b00, booting, data_ready, 4'b0000} : regs[a];
    endfunction

    // ---------------- I2C slave ----------------
    localparam ST_IDLE = 0, ST_ADDR = 1, ST_REG = 2, ST_WDATA = 3, ST_TX = 4;

    reg       sda_low = 1'b0;
    assign sda = sda_low ? 1'b0 : 1'bz;

    integer   st = ST_IDLE;
    integer   bit_cnt = 0;
    reg [7:0] sh = 8'd0;
    reg [7:0] tx = 8'd0;
    reg [7:0] ptr = 8'd0;
    reg       tx_started = 1'b0;
    reg       scl_d = 1'b1;
    reg       sda_d = 1'b1;
    integer   writes = 0;
    integer   reads  = 0;

    always @(scl or sda) begin
        if (scl_d === 1'b1 && scl === 1'b1 && sda_d === 1'b1 && sda === 1'b0) begin
            st = ST_ADDR;       // START / repeated START
            bit_cnt = -1;       // the SCL fall that ends START is not a data bit
            sda_low = 1'b0;
        end else if (scl_d === 1'b1 && scl === 1'b1 && sda_d === 1'b0 && sda === 1'b1) begin
            st = ST_IDLE;       // STOP
            sda_low = 1'b0;
        end else if (scl_d === 1'b0 && scl === 1'b1) begin
            if (st != ST_IDLE && bit_cnt < 8)
                sh = {sh[6:0], (sda === 1'b0) ? 1'b0 : 1'b1};
            if (st == ST_TX && bit_cnt == 8 && sda !== 1'b0)
                st = ST_IDLE;   // master NACK ends the read
        end else if (scl_d === 1'b1 && scl === 1'b0 && st != ST_IDLE) begin
            if (bit_cnt < 7) begin
                bit_cnt = bit_cnt + 1;
                if (st == ST_TX)
                    sda_low = ~tx[7 - bit_cnt];
            end else if (bit_cnt == 7) begin
                bit_cnt = 8;
                case (st)
                    ST_ADDR: begin
                        if (sh[7:1] == I2C_ADDR && rst_n === 1'b1) begin
                            sda_low = 1'b1;
                            if (sh[0]) begin
                                st = ST_TX;
                                tx = read_reg(ptr);
                                tx_started = 1'b0;
                            end else begin
                                st = ST_REG;
                            end
                        end else begin
                            st = ST_IDLE;
                            sda_low = 1'b0;
                        end
                    end
                    ST_REG: begin
                        ptr = sh;
                        sda_low = 1'b1;
                        st = ST_WDATA;
                    end
                    ST_WDATA: begin
                        regs[ptr] = sh;
                        writes = writes + 1;
                        $display("[%0t] MI48 write reg 0x%02h = 0x%02h", $time, ptr, sh);
                        ptr = ptr + 1;
                        sda_low = 1'b1;
                    end
                    ST_TX: sda_low = 1'b0;   // release for master ACK/NACK
                endcase
            end else begin
                bit_cnt = 0;
                sda_low = 1'b0;
                if (st == ST_TX) begin
                    if (tx_started) begin
                        ptr = ptr + 1;
                        tx = read_reg(ptr);
                    end else begin
                        reads = reads + 1;
                        $display("[%0t] MI48 read  reg 0x%02h -> 0x%02h", $time, ptr, tx);
                    end
                    tx_started = 1'b1;
                    sda_low = ~tx[7];
                end
            end
        end
        scl_d = scl;
        sda_d = sda;
    end

    // ---------------- SPI frame source ----------------
    reg [15:0] frame [0:5039];
    integer    frame_no = 0;
    integer    bitpos   = 0;

    // Glitch injection (set from the testbench, cleared once applied):
    // extra_edges counts as additional SCLK edges, missed_edges as lost ones.
    integer extra_edges  = 0;
    integer missed_edges = 0;

    function [15:0] crc_step(input [15:0] crc, input [15:0] data);
        integer k;
        begin
            crc_step = crc;
            for (k = 15; k >= 0; k = k - 1)
                crc_step = {crc_step[14:0], 1'b0} ^ ((crc_step[15] ^ data[k]) ? 16'h1021 : 16'h0000);
        end
    endfunction

    task build_frame;
        integer i;
        reg [15:0] crc;
        begin
            for (i = 0; i < 80; i = i + 1)
                frame[i] = 16'd0;
            frame[0] = frame_no;
            crc = 16'hFFFF;
            for (i = 0; i < 4960; i = i + 1) begin
                frame[80 + i] = 2900 + (i % 80) + 2 * (i / 80) + frame_no;
                crc = crc_step(crc, frame[80 + i]);
            end
            frame[7] = crc;
        end
    endtask

    assign miso = (!cs_n && bitpos < FRAME_BITS) ? frame[bitpos / 16][15 - (bitpos % 16)] : 1'bz;

    always @(negedge sclk) begin
        if (!cs_n) begin
            if (bitpos == 1000 && extra_edges > 0) begin
                bitpos = bitpos + 1 + extra_edges;
                extra_edges = 0;
            end else if (bitpos == 1000 && missed_edges > 0) begin
                missed_edges = missed_edges - 1;
            end else begin
                bitpos = bitpos + 1;
            end
        end
    end

    initial begin
        forever begin
            wait (rst_n === 1'b1 && !booting && regs[8'hB1][1]);
            build_frame;
            bitpos = 0;
            data_ready = 1'b1;
            wait (bitpos >= FRAME_BITS || rst_n !== 1'b1);
            data_ready = 1'b0;
            frame_no = frame_no + 1;
            #(FRAME_GAP_NS);
        end
    end

endmodule
