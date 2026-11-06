//=============================================================================
// Module: spi_slave
// Description: Synthesizable SPI Slave Model for Verification.
//              - Mode 0 compliant: MISO drives MSB immediately upon CS_N falling edge.
//              - Samples MOSI on rising edge of sclk.
//              - Shifts out next bit on falling edge of sclk.
//              - Active only when slave select (ss_pad_o[0]) is asserted LOW.
//=============================================================================

`timescale 1ns / 1ps
`include "spi_defines.v"

module spi_slave (
    input                        sclk,
    input                        mosi,
    input      [`SPI_SS_NB-1:0]  ss_pad_o,
    output                       miso
);

    // Active-low chip select for Slave 0
    wire cs_n = ss_pad_o[0];

    reg [7:0] rx_byte;
    reg [7:0] tx_byte;
    reg [2:0] bit_cnt;

    // In Mode 0, drive MSB immediately when CS asserted
    assign miso = (!cs_n) ? tx_byte[7] : 1'b0;

    // Sample MOSI on rising edge of SCLK
    always @(posedge sclk or posedge cs_n) begin
        if (cs_n) begin
            rx_byte <= 8'h00;
            bit_cnt <= 3'd0;
        end else begin
            rx_byte <= {rx_byte[6:0], mosi};
            bit_cnt <= bit_cnt + 1'b1;
        end
    end

    // Shift next bits on falling edge of SCLK
    always @(negedge sclk or posedge cs_n) begin
        if (cs_n) begin
            tx_byte <= 8'hA5; // Golden response payload for testbench verification
        end else begin
            tx_byte <= {tx_byte[6:0], 1'b0};
        end
    end

endmodule