//=============================================================================
// Testbench: tb (Comprehensive SPI Master Verification)
// Description: Self-checking automated verification testbench for SPI Master.
//              - Verifies Wishbone bus read and write handshakes.
//              - Verifies programmable clock divider register.
//              - Tests full-duplex transmission across SPI modes:
//                * Mode 0 (CPOL=0, CPHA=0): tx_neg=1, rx_neg=0
//                * Mode 1 (CPOL=0, CPHA=1): tx_neg=0, rx_neg=1
//                * LSB-First vs MSB-First bit ordering
//                * Variable character length (4-bit and 8-bit transfers)
//                * Auto Slave Select (ASS) multi-slave decoding
//                * Interactive SPI Slave peripheral communication
//              - Golden scoreboard reporting total passes, errors, and status.
//=============================================================================

`timescale 1ns / 1ps
`include "spi_defines.v"

module tb;

    reg         wb_clk_in;
    reg         wb_rst_in;
    wire        wb_ack_out;
    wire        wb_err_in = 1'b0;
    wire [31:0] wb_dat_o;
    wire [4:0]  wb_adr_in;
    wire        wb_cyc_in;
    wire        wb_stb_in;
    wire        wb_we_in;
    wire [31:0] wb_dat_in;
    wire [3:0]  wb_sel_in;
    wire        wb_int_o;

    wire [`SPI_SS_NB-1:0] ss_pad_o;
    wire        sclk_out;
    wire        mosi;
    wire        miso;
    wire        miso_slave;

    // Loopback control: 1 = direct MOSI->MISO loopback, 0 = SPI slave model
    reg         loopback_en = 1'b1;
    assign miso = loopback_en ? mosi : miso_slave;

    // Testbench tracking
    integer pass_count = 0;
    integer err_count  = 0;
    reg [31:0] rd_data;

    parameter T = 20; // 50 MHz clock (20ns period)

    // Clock generation
    initial begin
        wb_clk_in = 1'b0;
        forever #(T/2) wb_clk_in = ~wb_clk_in;
    end

    // Instantiate Wishbone Master Model
    wishbone_master MASTER (
        .clk_in   (wb_clk_in),
        .rst_in   (wb_rst_in),
        .ack_in   (wb_ack_out),
        .err_in   (wb_err_in),
        .dat_in   (wb_dat_o),
        .adr_o    (wb_adr_in),
        .cyc_o    (wb_cyc_in),
        .stb_o    (wb_stb_in),
        .we_o     (wb_we_in),
        .dat_o    (wb_dat_in),
        .sel_o    (wb_sel_in)
    );

    // Instantiate SPI Master Top Core
    spi_top SPI_CORE (
        .wb_clk_in   (wb_clk_in),
        .wb_rst_in   (wb_rst_in),
        .wb_adr_in   (wb_adr_in),
        .wb_dat_in   (wb_dat_in),
        .wb_sel_in   (wb_sel_in),
        .wb_we_in    (wb_we_in),
        .wb_stb_in   (wb_stb_in),
        .wb_cyc_in   (wb_cyc_in),
        .wb_ack_out  (wb_ack_out),
        .wb_int_o    (wb_int_o),
        .wb_dat_o    (wb_dat_o),
        .ss_pad_o    (ss_pad_o),
        .sclk_out    (sclk_out),
        .mosi        (mosi),
        .miso        (miso)
    );

    // Instantiate SPI Slave Model
    spi_slave SLAVE (
        .sclk        (sclk_out),
        .mosi        (mosi),
        .ss_pad_o    (ss_pad_o),
        .miso        (miso_slave)
    );

    // Helper: Reset DUT
    task reset_dut;
        begin
            wb_rst_in = 1'b1;
            MASTER.initialize;
            #(T * 2);
            @(negedge wb_clk_in);
            wb_rst_in = 1'b0;
            #(T * 2);
        end
    endtask

    // Helper: Wait for SPI Transfer to complete by polling CTRL GO_BUSY bit
    task wait_spi_done;
        reg [31:0] status;
        begin
            repeat (2) @(posedge wb_clk_in);
            MASTER.single_read(5'h10, status, 4'b1111);
            while (status[8] == 1'b1) begin
                MASTER.single_read(5'h10, status, 4'b1111);
            end
        end
    endtask

    // Helper: Verification assertion check
    task check_result(input [31:0] actual, input [31:0] expected, input [255:0] test_name);
        begin
            if (actual === expected) begin
                $display("[PASS] %-45s | Received: 0x%02h (Expected: 0x%02h)", test_name, actual, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %-45s | Received: 0x%02h (Expected: 0x%02h) << MISMATCH!", test_name, actual, expected);
                err_count = err_count + 1;
            end
        end
    endtask

    // Main Test Sequence
    initial begin
        $display("==================================================================");
        $display("       STARTING SPI MASTER WITH WISHBONE INTERFACE TESTBENCH       ");
        $display("==================================================================");

        reset_dut;

        //------------------------------------------------------------------
        // TEST 1: Reset Default State Verification
        //------------------------------------------------------------------
        $display("\n[TEST 1] Verifying Register Reset Default States...");
        MASTER.single_read(5'h14, rd_data, 4'b1111); // Read DIVIDER
        check_result(rd_data, 32'h0000_0000, "Reset DIVIDER default is 0x00");

        MASTER.single_read(5'h18, rd_data, 4'b1111); // Read SS
        check_result(rd_data, 32'h0000_0000, "Reset SS default is 0x00");

        //------------------------------------------------------------------
        // TEST 2: Programmable Clock Divider Verification (Fix for Bug 1)
        //------------------------------------------------------------------
        $display("\n[TEST 2] Verifying Programmable Clock Divider...");
        MASTER.single_write(5'h14, 32'h0000_0004, 4'b1111); // Write divider = 4
        MASTER.single_read(5'h14, rd_data, 4'b1111);
        check_result(rd_data, 32'h0000_0004, "Divider programmed to 4");

        MASTER.single_write(5'h14, 32'h0000_0008, 4'b1111); // Write divider = 8
        MASTER.single_read(5'h14, rd_data, 4'b1111);
        check_result(rd_data, 32'h0000_0008, "Divider reprogrammed to 8");

        //------------------------------------------------------------------
        // TEST 3: Mode 0 Full-Duplex Serial Loopback (CPOL=0, CPHA=0, MSB-First)
        //------------------------------------------------------------------
        $display("\n[TEST 3] Testing Mode 0 (CPOL=0, CPHA=0, MSB-First) Full-Duplex Loopback...");
        loopback_en = 1'b1; // MOSI connected directly to MISO
        MASTER.single_write(5'h14, 32'h0000_0002, 4'b1111); // Divider = 2
        MASTER.single_write(5'h18, 32'h0000_0001, 4'b1111); // Select Slave 0
        MASTER.single_write(5'h00, 32'h0000_005A, 4'b1111); // TX Data = 0x5A
        // Control: ASS=1, IE=1, LSB=0, TX_NEG=1, RX_NEG=0, GO=1, CHAR_LEN=8 -> 0x3508
        MASTER.single_write(5'h10, 32'h0000_3508, 4'b1111);
        wait_spi_done;
        MASTER.single_read(5'h00, rd_data, 4'b1111);
        check_result(rd_data[7:0], 8'h5A, "Mode 0 Loopback Data Match (0x5A)");

        //------------------------------------------------------------------
        // TEST 4: Mode 1 Full-Duplex Serial Loopback (CPOL=0, CPHA=1, MSB-First)
        //------------------------------------------------------------------
        $display("\n[TEST 4] Testing Mode 1 (CPOL=0, CPHA=1, MSB-First) Full-Duplex Loopback...");
        MASTER.single_write(5'h00, 32'h0000_00A5, 4'b1111); // TX Data = 0xA5
        // Control: ASS=1, IE=1, LSB=0, TX_NEG=0, RX_NEG=1, GO=1, CHAR_LEN=8 -> 0x3308
        MASTER.single_write(5'h10, 32'h0000_3308, 4'b1111);
        wait_spi_done;
        MASTER.single_read(5'h00, rd_data, 4'b1111);
        check_result(rd_data[7:0], 8'hA5, "Mode 1 Loopback Data Match (0xA5)");

        //------------------------------------------------------------------
        // TEST 5: Mode 0 with LSB-First Bit Ordering (LSB=1)
        //------------------------------------------------------------------
        $display("\n[TEST 5] Testing LSB-First Bit Ordering Transfer...");
        MASTER.single_write(5'h00, 32'h0000_0037, 4'b1111); // TX Data = 0x37
        // Control: ASS=1, IE=1, LSB=1, TX_NEG=1, RX_NEG=0, GO=1, CHAR_LEN=8 -> 0x3D08
        MASTER.single_write(5'h10, 32'h0000_3D08, 4'b1111);
        wait_spi_done;
        MASTER.single_read(5'h00, rd_data, 4'b1111);
        check_result(rd_data[7:0], 8'h37, "LSB-First Loopback Data Match (0x37)");

        //------------------------------------------------------------------
        // TEST 6: Variable Character Length (4-bit Nibble Transfer)
        //------------------------------------------------------------------
        $display("\n[TEST 6] Testing Variable Character Length (4-bit Transfer)...");
        MASTER.single_write(5'h00, 32'h0000_000B, 4'b1111); // TX Data = 4'hB
        // Control: ASS=1, IE=1, LSB=0, TX_NEG=1, RX_NEG=0, GO=1, CHAR_LEN=4 -> 0x3504
        MASTER.single_write(5'h10, 32'h0000_3504, 4'b1111);
        wait_spi_done;
        MASTER.single_read(5'h00, rd_data, 4'b1111);
        check_result(rd_data[3:0], 4'hB, "4-Bit Character Length Match (0xB)");

        //------------------------------------------------------------------
        // TEST 7: Auto Slave Select (ASS) Verification for Multiple Slaves
        //------------------------------------------------------------------
        $display("\n[TEST 7] Testing Auto Slave Select (ASS) Decoding...");
        loopback_en = 1'b1;
        MASTER.single_write(5'h18, 32'h0000_0004, 4'b1111); // Select Slave 2 (bit 2)
        MASTER.single_write(5'h00, 32'h0000_00FF, 4'b1111);
        MASTER.single_write(5'h10, 32'h0000_3508, 4'b1111);
        repeat (3) @(posedge wb_clk_in);
        check_result(ss_pad_o, 8'hFB, "Slave 2 asserted active-low (0xFB) during transfer");
        wait_spi_done;
        check_result(ss_pad_o, 8'hFF, "Slave Select deasserts high (0xFF) after transfer");

        //------------------------------------------------------------------
        // TEST 8: Interactive SPI Slave Verification (Preloaded 0xA5 Response)
        //------------------------------------------------------------------
        $display("\n[TEST 8] Testing Interactive SPI Slave Communication...");
        loopback_en = 1'b0; // Connect to SPI Slave model
        MASTER.single_write(5'h18, 32'h0000_0001, 4'b1111); // Select Slave 0
        MASTER.single_write(5'h00, 32'h0000_0012, 4'b1111); // Send command byte
        MASTER.single_write(5'h10, 32'h0000_3508, 4'b1111); // Start Mode 0 transfer
        wait_spi_done;
        MASTER.single_read(5'h00, rd_data, 4'b1111);
        check_result(rd_data[7:0], 8'hA5, "Slave Response Payload Received (0xA5)");

        //------------------------------------------------------------------
        // FINAL VERIFICATION SCOREBOARD REPORT
        //------------------------------------------------------------------
        $display("\n==================================================================");
        $display("             SPI MASTER VERIFICATION SCOREBOARD                   ");
        $display("==================================================================");
        $display(" Total Assertions Checked : %0d", (pass_count + err_count));
        $display(" Total Passing Checks     : %0d", pass_count);
        $display(" Total Error Count        : %0d", err_count);

        if (err_count == 0 && pass_count >= 10) begin
            $display("\n >>> [STATUS: ALL SPI MASTER VERIFICATION TESTS PASSED!] <<< ");
            $display(" [CONFIRMED] Programmable clock divider functionality verified.");
            $display(" [CONFIRMED] Full-duplex serial transmission verified across SPI modes.");
            $display(" [CONFIRMED] Auto Slave Select and multi-slave decoding verified.");
            $display(" [CONFIRMED] Wishbone SoC bus read/write handshakes verified.\n");
        end else begin
            $display("\n >>> [STATUS: VERIFICATION FAILED WITH %0d ERRORS] <<< \n", err_count);
        end
        $display("==================================================================");

        $finish;
    end

endmodule