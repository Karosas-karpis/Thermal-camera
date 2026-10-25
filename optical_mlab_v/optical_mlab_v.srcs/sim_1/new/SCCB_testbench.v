`timescale 1ns / 1ps

// Self-checking testbench for i2c_sender.
// Verifies two OV7670 writes, START/STOP, ACK/NACK and completion.

module SCCB_testbench;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg [15:0] command;

    wire [7:0] config_step;
    wire done;
    wire ack_error;

    tri sioc;
    tri siod;
    pullup (sioc);
    pullup (siod);

    reg camera_siod_low = 1'b0;
    assign siod = camera_siod_low ? 1'b0 : 1'bz;

    i2c_sender #(
        .QUARTER_TICKS(2),
        .POWERUP_QUARTERS(4),
        .RESET_WAIT_QUARTERS(4),
        .BUS_GAP_QUARTERS(2)
    ) dut (
        .clk(clk),
        .reset(reset),
        .command(command),
        .config_step(config_step),
        .sioc(sioc),
        .siod(siod),
        .done(done),
        .ack_error(ack_error)
    );

    always #5 clk = ~clk;

    always @(*) begin
        case (config_step)
            8'd0: command = 16'h12_80;
            8'd1: command = 16'hFF_FE;
            8'd2: command = 16'h40_D0;
            default: command = 16'hFF_FF;
        endcase
    end

    integer errors = 0;
    integer transaction = 0;
    integer byte_number = 0;
    integer bit_number = 0;
    reg transaction_active = 1'b0;
    reg [7:0] received_byte = 8'd0;
    reg [23:0] received_packet = 24'd0;

    // START
    always @(negedge siod) begin
        if ((sioc === 1'b1) && !transaction_active) begin
            transaction_active = 1'b1;
            byte_number = 0;
            bit_number = 0;
            received_byte = 8'd0;
            received_packet = 24'd0;
        end
    end

    // Receive one data bit on each SIOC rising edge.
    always @(posedge sioc) begin
        if (transaction_active) begin
            if (bit_number < 8) begin
                received_byte = {received_byte[6:0], siod};
                bit_number = bit_number + 1;
            end else begin
                case (byte_number)
                    0: received_packet[23:16] = received_byte;
                    1: received_packet[15:8]  = received_byte;
                    2: received_packet[7:0]   = received_byte;
                endcase
                bit_number = 9;
            end
        end
    end

    // ACK every byte except byte 1 of the second transaction.
    always @(negedge sioc) begin
        if (transaction_active) begin
            if (bit_number == 8) begin
                if (!((transaction == 1) && (byte_number == 1)))
                    camera_siod_low = 1'b1;
            end else if (bit_number == 9) begin
                camera_siod_low = 1'b0;
                bit_number = 0;
                byte_number = byte_number + 1;
                received_byte = 8'd0;
            end
        end
    end

    // STOP
    always @(posedge siod) begin
        if ((sioc === 1'b1) && transaction_active) begin
            transaction_active = 1'b0;

            if ((transaction == 0) &&
                (received_packet !== 24'h42_12_80)) begin
                $display("ERROR: first packet %h, expected 421280",
                         received_packet);
                errors = errors + 1;
            end

            if ((transaction == 1) &&
                (received_packet !== 24'h42_40_D0)) begin
                $display("ERROR: second packet %h, expected 4240D0",
                         received_packet);
                errors = errors + 1;
            end

            transaction = transaction + 1;
        end
    end

    initial begin
        $display("Starting SCCB testbench");
        repeat (4) @(posedge clk);
        reset = 1'b0;

        fork
            begin
                wait (done === 1'b1);
                @(posedge clk);

                if (transaction != 2) begin
                    $display("ERROR: expected 2 transactions, got %0d",
                             transaction);
                    errors = errors + 1;
                end
                if (config_step != 8'd3) begin
                    $display("ERROR: expected config_step 3, got %0d",
                             config_step);
                    errors = errors + 1;
                end
                if (ack_error !== 1'b1) begin
                    $display("ERROR: deliberate NACK was not detected");
                    errors = errors + 1;
                end

                if (errors == 0)
                    $display("PASS: SCCB write, ACK/NACK and STOP verified");
                else
                    $display("FAIL: %0d error(s)", errors);
                $finish;
            end

            begin
                #100000;
                $display("FAIL: timeout");
                $finish;
            end
        join
    end

endmodule
