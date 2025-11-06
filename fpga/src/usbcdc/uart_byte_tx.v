//八位并行数据转串行数据输出
//关键在于定义好计数器，在计数器计数到一定时依次给串行数据赋值
//三百多次计数一位，然后再按照通信协议传输
//起始位 + 8位数据位 + （奇偶校验1位）+ 停止位 
`timescale 1ns / 1ps
`timescale 1ns / 1ps

// 串口字节发送模块 (可配置数据位/奇偶校验/停止位)
module uart_byte_tx1(
	input               clk,
	input               rst_n,
	input      [7:0]    data_byte,
	input               send_en,

	input      [15:0]   baud_divisor,
	
    // --- 可配置参数 ---
    input      [3:0]    bits_cfg,
    input      [1:0]    parity_cfg,
    input      [1:0]    stop_cfg,       // *** NEW: 停止位配置 (例如 2'd1=1位, 2'd2=2位) ***

	output reg          uart_tx,
	output reg          tx_done,
	output reg          tx_busy
);

    // --- 内部参数定义 ---
    localparam [1:0] NONE = 2'b00, EVEN = 2'b01, ODD = 2'b10;
	localparam START_BIT = 1'b0;
	localparam STOP_BIT  = 1'b1;

    // --- 状态机定义 ---
    localparam [3:0] S_IDLE       = 4'd0,
                     S_START_BIT  = 4'd1,
                     S_DATA_BITS  = 4'd2,
                     S_PARITY_BIT = 4'd3,
                     S_STOP_BIT   = 4'd4,
                     S_STOP_BIT_2 = 4'd5; // *** NEW STATE ***
    
    reg [3:0] current_state;

    // ... [其他 reg 和 wire 定义保持不变] ...
    reg [15:0]  baud_clk_cnt;
    reg [3:0]   bit_idx;
    reg [7:0]   data_byte_reg;
    reg         parity_bit_to_send;
    reg         even_parity;

    // ... [波特率时钟生成逻辑保持不变] ...
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_clk_cnt <= 0;
        end else if (current_state != S_IDLE) begin
            if (baud_clk_cnt >= baud_divisor - 1) begin
                baud_clk_cnt <= 0;
            end else begin
                baud_clk_cnt <= baud_clk_cnt + 1;
            end
        end else begin
            baud_clk_cnt <= 0;
        end
    end
    wire baud_tick = (current_state != S_IDLE) && (baud_clk_cnt == baud_divisor - 1);

    // ... [奇偶校验位计算逻辑保持不变] ...
    always @(*) begin
        case (bits_cfg)
            4'd5: even_parity = ^data_byte_reg[4:0];
            4'd6: even_parity = ^data_byte_reg[5:0];
            4'd7: even_parity = ^data_byte_reg[6:0];
            4'd8: even_parity = ^data_byte_reg[7:0];
            default: even_parity = 1'b0;
        endcase

        if (parity_cfg == ODD) begin
            parity_bit_to_send = ~even_parity;
        end else begin
            parity_bit_to_send = even_parity;
        end
    end

    // =================================================================
    // == 3. 发送状态机 (*** MODIFIED ***)
    // =================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            uart_tx <= 1'b1;
            tx_done <= 1'b0;
            tx_busy <= 1'b0;
            bit_idx <= 0;
            data_byte_reg <= 0;
        end else begin
            tx_done <= 1'b0;

            case (current_state)
                S_IDLE: begin
                    uart_tx <= 1'b1;
                    if (send_en) begin
                        data_byte_reg <= data_byte;
                        bit_idx <= 0;
                        tx_busy <= 1'b1;
                        current_state <= S_START_BIT;
                    end
                end

                S_START_BIT: begin
                    uart_tx <= START_BIT;
                    if (baud_tick) begin
                        current_state <= S_DATA_BITS;
                    end
                end

                S_DATA_BITS: begin
                    uart_tx <= data_byte_reg[bit_idx];
                    if (baud_tick) begin
                        if (bit_idx == bits_cfg - 1) begin
                            if (parity_cfg == NONE) begin
                                current_state <= S_STOP_BIT;
                            end else begin
                                current_state <= S_PARITY_BIT;
                            end
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end
                end

                S_PARITY_BIT: begin
                    uart_tx <= parity_bit_to_send;
                    if (baud_tick) begin
                        current_state <= S_STOP_BIT;
                    end
                end

                S_STOP_BIT: begin
                    uart_tx <= STOP_BIT;
                    if (baud_tick) begin
                        // *** MODIFIED: Check stop bit configuration ***
                        if (stop_cfg == 2'd2) begin
                            current_state <= S_STOP_BIT_2;
                        end else begin // stop_cfg == 1 or other
                            current_state <= S_IDLE;
                            tx_done <= 1'b1;
                            tx_busy <= 1'b0;
                        end
                    end
                end
                
                // *** NEW STATE ***
                S_STOP_BIT_2: begin
                    uart_tx <= STOP_BIT;
                    if (baud_tick) begin
                        current_state <= S_IDLE;
                        tx_done <= 1'b1;
                        tx_busy <= 1'b0;
                    end
                end
                
                default: current_state <= S_IDLE;
            endcase
        end
    end

endmodule