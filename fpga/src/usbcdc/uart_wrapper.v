`timescale 1ns / 1ps
`include "address_map.vh"

module uart_wrapper (
    input             clk,
    input             rst_n,
    input      [15:0] cfg_addr,
    input      [31:0] cfg_wdata,
    input             cfg_write,
    output wire [7:0] cfg_rdata_out,
    output wire       cfg_rvalid_out,
  
    input             uart_rx_pin,
    output            uart_tx_pin
);
    // 内部总线输入寄存器，用于稳定时序
    reg [15:0] cfg_addr_reg;
    reg [31:0] cfg_wdata_reg;
    reg        cfg_write_reg;
    // 寄存器和信号定义
    reg [31:0] config_reg;
    wire [15:0] baud_divisor_w = config_reg[31:16];
    wire [3:0]  bits_cfg_w     = config_reg[3:0];
    wire [1:0]  parity_cfg_w   = config_reg[5:4];
    wire [1:0]  stop_cfg_w     = config_reg[7:6];
    
    // TX FIFO -- 容量已扩大到32字节
    reg [7:0]  tx_fifo [0:31];
    reg [5:0]  tx_wr_ptr, tx_rd_ptr;
    wire       tx_fifo_full;
    wire       tx_fifo_empty;
    reg        tx_send_en;
    wire       tx_done_w;
    wire       tx_busy_w;

    // RX 信号
    wire [7:0] rx_data_w;
    wire       rx_done_w;
    wire       rx_parity_error_w;
    
    // FIFO 满/空逻辑更新以匹配新指针位宽
    assign tx_fifo_full  = (tx_wr_ptr[4:0] == tx_rd_ptr[4:0]) && (tx_wr_ptr[5] != tx_rd_ptr[5]);
    assign tx_fifo_empty = (tx_wr_ptr == tx_rd_ptr);
    
    assign cfg_rdata_out  = rx_data_w;
    assign cfg_rvalid_out = rx_done_w;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_addr_reg  <= 16'h0;
            cfg_wdata_reg <= 32'h0;
            cfg_write_reg <= 1'b0;
        end else begin
            cfg_addr_reg  <= cfg_addr;
            cfg_wdata_reg <= cfg_wdata;
            cfg_write_reg <= cfg_write;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            config_reg <= {16'd434, 8'd0, 2'd1, 2'd0, 4'd8}; // 默认 115200, 8N1
            tx_wr_ptr  <= 6'd0;
        end 
        else begin
            if (cfg_write_reg) begin
                if (cfg_addr_reg == `UART_BASE_ADDR + `UART_REG_OFFSET_CONFIG) begin
                    config_reg <= cfg_wdata_reg;
                end
                
                if (cfg_addr_reg == `UART_BASE_ADDR + `UART_REG_OFFSET_TX_DATA && !tx_fifo_full) begin
                    tx_fifo[tx_wr_ptr[4:0]] <= cfg_wdata_reg[7:0];
                    tx_wr_ptr <= tx_wr_ptr + 1'b1;
                end
            end
        end
    end

    // TX 控制器 -- 已替换为更稳健的状态机
    localparam TX_IDLE = 2'd0;
    localparam TX_SEND = 2'd1;
    reg [1:0] tx_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_rd_ptr  <= 6'd0;
            tx_send_en <= 1'b0;
            tx_state   <= TX_IDLE;
        end 
        else begin
            tx_send_en <= 1'b0;
            case (tx_state)
                TX_IDLE: begin
                    if (!tx_fifo_empty && !tx_busy_w) begin
                        tx_send_en <= 1'b1;
                        tx_state   <= TX_SEND;
                    end
                end
                TX_SEND: begin
                    if (tx_done_w) begin
                        tx_rd_ptr <= tx_rd_ptr + 1'b1;
                        tx_state  <= TX_IDLE;
                    end
                end
                default: begin
                    tx_state <= TX_IDLE;
                end
            endcase
        end
    end

    // 例化底层UART模块
    uart_byte_tx1 u_uart_tx1 (
        .clk(clk), .rst_n(rst_n), .data_byte(tx_fifo[tx_rd_ptr[4:0]]),
        .send_en(tx_send_en), .baud_divisor(baud_divisor_w), .bits_cfg(bits_cfg_w),
        .parity_cfg(parity_cfg_w), .stop_cfg(stop_cfg_w), .uart_tx(uart_tx_pin),
        .tx_done(tx_done_w), .tx_busy(tx_busy_w)
    );
    uart_byte_rx u_uart_rx (
        .clk(clk), .rst_n(rst_n), .baud_divisor(baud_divisor_w),
        .bits_cfg(bits_cfg_w), .parity_cfg(parity_cfg_w), .stop_cfg(stop_cfg_w),
        .uart_rx(uart_rx_pin), .data_byte(rx_data_w), .rx_done(rx_done_w),
        .parity_error(rx_parity_error_w)
    );
endmodule