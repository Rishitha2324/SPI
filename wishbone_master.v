//=============================================================================
// Module: wishbone_master
// Description: Wishbone Bus Functional Model (BFM) for testbench verification.
//              Directly drives Wishbone bus signals on negedge and waits for
//              wb_ack_out without intermediate delay registers.
//=============================================================================

`timescale 1ns / 1ps

module wishbone_master (
    input             clk_in,
    input             rst_in,
    input             ack_in,
    input             err_in,
    input      [31:0] dat_in,
    output reg [4:0]  adr_o,
    output reg        cyc_o,
    output reg        stb_o,
    output reg        we_o,
    output reg [31:0] dat_o,
    output reg [3:0]  sel_o
);

    task initialize;
        begin
            adr_o = 5'd0;
            cyc_o = 1'b0;
            stb_o = 1'b0;
            we_o  = 1'b0;
            dat_o = 32'd0;
            sel_o = 4'd0;
        end
    endtask

    // Wishbone Bus Single Write Task
    task single_write;
        input [4:0]  adr;
        input [31:0] dat;
        input [3:0]  sel;
        begin
            @(negedge clk_in);
            adr_o = adr;
            dat_o = dat;
            sel_o = sel;
            we_o  = 1'b1;
            cyc_o = 1'b1;
            stb_o = 1'b1;

            // Wait for slave to assert acknowledge
            @(posedge clk_in);
            while (!ack_in) @(posedge clk_in);

            @(negedge clk_in);
            cyc_o = 1'b0;
            stb_o = 1'b0;
            we_o  = 1'b0;
            adr_o = 5'd0;
            dat_o = 32'd0;
            sel_o = 4'd0;
        end
    endtask

    // Wishbone Bus Single Read Task
    task single_read;
        input  [4:0]  adr;
        output [31:0] data_rd;
        input  [3:0]  sel;
        begin
            @(negedge clk_in);
            adr_o = adr;
            sel_o = sel;
            we_o  = 1'b0;
            dat_o = 32'd0;
            cyc_o = 1'b1;
            stb_o = 1'b1;

            // Wait for slave to assert acknowledge
            @(posedge clk_in);
            while (!ack_in) @(posedge clk_in);

            // Sample data on acknowledge
            data_rd = dat_in;

            @(negedge clk_in);
            cyc_o = 1'b0;
            stb_o = 1'b0;
            adr_o = 5'd0;
            sel_o = 4'd0;
        end
    endtask

    initial begin
        initialize;
    end

endmodule