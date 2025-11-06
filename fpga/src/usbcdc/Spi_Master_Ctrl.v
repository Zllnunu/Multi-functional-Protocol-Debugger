`timescale 1ns / 1ps

// =================================================================================
// MODIFIED: This module now accepts a pre-calculated clock divisor instead of a frequency.
// =================================================================================
module Spi_Master_Ctrl #(
    parameter integer BITS_ORDER = 1'b1
)(
    input               clk,
    input               rst_n,
    input               cpol_i,
    input               cpha_i,
    input      [31:0]   clk_divisor, // MODIFIED: Port renamed to accept pre-calculated divisor
    output              SPI_CS,
    output              SPI_SCLK,
    output              SPI_MOSI,
    input               SPI_MISO,
    input      [7:0]    tx_data,
    input               trans_en,
    output reg [7:0]    rx_data,
    output reg          trans_done,
    output reg          spi_busy
);
    reg  cs;
    reg  sclk;
    reg  mosi;
    wire miso;
    assign SPI_CS = cs;
    assign SPI_SCLK = sclk;
    assign SPI_MOSI = mosi;
    assign miso = SPI_MISO;

    reg [31:0] clk_div_max;
    reg [31:0] clk_div_cnt;
    reg spi_clk_x2;

    reg [7:0] rx_data_r;
    reg [7:0] tx_data_r;
    reg [4:0] spi_state_cnt;

    // --- MODIFIED: Removed the slow hardware divider. ---
    // This block now simply registers the pre-calculated divisor.
    // This path is now extremely fast and will meet timing.
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            clk_div_max <= 32'd1;
        end else begin
            clk_div_max <= clk_divisor;
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            clk_div_cnt <= 32'd0;
            spi_clk_x2  <= 1'b0;
        end else if(clk_div_cnt >= clk_div_max - 1'd1) begin
            clk_div_cnt <= 32'd0;
            spi_clk_x2  <= 1'b1;
        end else begin
            clk_div_cnt <= clk_div_cnt + 1'd1;
            spi_clk_x2  <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            spi_busy <= 1'b0;
            rx_data  <= 8'h00;
            tx_data_r<= 8'h00;
        end else if (trans_en) begin
            spi_busy <= 1'b1;
            if(BITS_ORDER)
                tx_data_r <= {tx_data[0],tx_data[1],tx_data[2],tx_data[3],tx_data[4],tx_data[5],tx_data[6],tx_data[7]};
            else
                tx_data_r <= tx_data;
        end else if (spi_state_cnt >= 5'd17 - cpha_i) begin
            spi_busy <= 1'b0;
            if(BITS_ORDER)
                rx_data <= {rx_data_r[0],rx_data_r[1],rx_data_r[2],rx_data_r[3],rx_data_r[4],rx_data_r[5],rx_data_r[6],rx_data_r[7]};
            else
                rx_data <= rx_data_r;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            spi_state_cnt <= 5'd0;
            sclk <= cpol_i;
        end else if (spi_state_cnt >= 5'd17 - cpha_i) begin
            sclk <= cpol_i;
            spi_state_cnt <= 5'd0;
        end else if (spi_clk_x2) begin
            if (spi_busy) begin
                if((cpha_i == 1'b0) && (spi_state_cnt == 5'd0))
                    sclk <= sclk;
                else
                    sclk <= ~sclk;
                spi_state_cnt <= spi_state_cnt + 1'd1;
            end else begin
                sclk <= cpol_i;
                spi_state_cnt <= 5'd0;
            end
        end else begin
            sclk <= sclk;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            mosi <= 1'b0;
            rx_data_r <= 8'h00;
        end else if (spi_clk_x2 && spi_busy) begin
            if (cpha_i == 1'b0) begin
                if (spi_state_cnt[0] == 1'b1) 
                    rx_data_r[7 - spi_state_cnt[4:1]] <= miso;
                else 
                    mosi <= tx_data_r[7 - spi_state_cnt[4:1]];
            end else begin
                if (spi_state_cnt[0] == 1'b1)
                     mosi <= tx_data_r[7 - spi_state_cnt[4:1]];
                else 
                    rx_data_r[7 - spi_state_cnt[4:1]] <= miso;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            trans_done <= 1'b0;
        end else if (spi_state_cnt >= 5'd17 - cpha_i) begin
            trans_done <= 1'b1;
        end else begin
            trans_done <= 1'b0;
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            cs <= 1'b1;
        end else if (trans_en) begin
            cs <= 1'b0;
        end else if (trans_done) begin
            cs <= 1'b1;
        end
    end

endmodule