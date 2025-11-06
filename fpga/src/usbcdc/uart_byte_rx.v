//接受模块，将接受到的串行数据转为8位并行数据
//关键在于过采样求然后再依次给赋值
//过采样采用投票表决而非求均值
`timescale 1ns / 1ps

// 串口字节接收模块 (可配置数据位/奇偶校验/停止位)
module uart_byte_rx(
	input               clk,
	input               rst_n,

	input      [15:0]   baud_divisor,
	input               uart_rx,
	
    // --- 可配置参数 ---
    input      [3:0]    bits_cfg,
    input      [1:0]    parity_cfg,
    input      [1:0]    stop_cfg,       // *** NEW: 停止位配置 (例如 2'd1=1位, 2'd2=2位) ***

	output reg [7:0]    data_byte,
	output reg          rx_done,
    output reg          parity_error
);

    // ... [内部参数定义保持不变] ...
    localparam OVERSAMPLE_RATE = 16;
    localparam [1:0] NONE = 2'b00, EVEN = 2'b01, ODD = 2'b10;
    
    // --- 状态机定义 ---
    localparam [3:0] S_IDLE       = 4'd0,
                     S_START_BIT  = 4'd1,
                     S_DATA_BITS  = 4'd2,
                     S_PARITY_BIT = 4'd3,
                     S_STOP_BIT   = 4'd4,
                     S_STOP_BIT_2 = 4'd5; // *** NEW STATE ***
    
    reg [3:0] current_state;

    // ... [其他 reg 和 wire 定义保持不变] ...
    reg uart_rx_sync1, uart_rx_sync2, uart_rx_reg1, uart_rx_reg2;
    wire uart_rx_nedge;
    reg [15:0]  sample_clk_divisor, sample_clk_cnt;
    reg [4:0]   sample_cnt;
    reg [3:0]   bit_idx;
    reg [7:0]   data_byte_reg;
    reg         received_parity, expected_parity, even_parity_bit;

    // ... [输入信号同步 & 采样时钟生成逻辑保持不变] ...
	always@(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			uart_rx_sync1 <= 1'b1; uart_rx_sync2 <= 1'b1;
			uart_rx_reg1  <= 1'b1; uart_rx_reg2  <= 1'b1;
		end else begin
			uart_rx_sync1 <= uart_rx; uart_rx_sync2 <= uart_rx_sync1;
			uart_rx_reg1  <= uart_rx_sync2; uart_rx_reg2  <= uart_rx_reg1;
		end
	end
	assign uart_rx_nedge = uart_rx_reg2 & ~uart_rx_reg1;
    always @(*) sample_clk_divisor = baud_divisor >> 4;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sample_clk_cnt <= 0;
        else if (current_state != S_IDLE) if (sample_clk_cnt >= sample_clk_divisor) sample_clk_cnt <= 0; else sample_clk_cnt <= sample_clk_cnt + 1;
        else sample_clk_cnt <= 0;
    end
    wire sample_tick = (current_state != S_IDLE) && (sample_clk_cnt == sample_clk_divisor);
    
    // ... [奇偶校验位计算逻辑保持不变] ...
    always @(*) begin
        case (bits_cfg)
            4'd5: even_parity_bit = ^data_byte_reg[4:0];
            4'd6: even_parity_bit = ^data_byte_reg[5:0];
            4'd7: even_parity_bit = ^data_byte_reg[6:0];
            4'd8: even_parity_bit = ^data_byte_reg[7:0];
            default: even_parity_bit = 1'b0;
        endcase
        if (parity_cfg == ODD) expected_parity = ~even_parity_bit;
        else expected_parity = even_parity_bit;
    end

    // =================================================================
    // == 4. 接收状态机 (*** MODIFIED ***)
    // =================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            sample_cnt <= 0;
            bit_idx <= 0;
            rx_done <= 1'b0;
            parity_error <= 1'b0;
            data_byte_reg <= 0;
        end else begin
            rx_done <= 1'b0;
            
            case (current_state)
                S_IDLE: begin
                    if (uart_rx_nedge) begin
                        current_state <= S_START_BIT;
                        sample_cnt <= 0;
                        bit_idx <= 0;
                        data_byte_reg <= 0;
                        parity_error <= 1'b0;
                    end
                end

                S_START_BIT: begin
                    if (sample_tick) begin
                        sample_cnt <= sample_cnt + 1;
                        if (sample_cnt == (OVERSAMPLE_RATE/2 - 1)) begin
                            if (uart_rx_sync2 == 1'b0) begin
                                current_state <= S_DATA_BITS;
                                sample_cnt <= 0;
                            end else begin
                                current_state <= S_IDLE;
                            end
                        end
                    end
                end

                S_DATA_BITS: begin
                    if (sample_tick) begin
                        sample_cnt <= sample_cnt + 1;
                        if (sample_cnt == (OVERSAMPLE_RATE/2 - 1)) begin // 在数据位中心采样
                            data_byte_reg[bit_idx] <= uart_rx_sync2;
                        end
                        if (sample_cnt == OVERSAMPLE_RATE - 1) begin
                            sample_cnt <= 0;
                            if (bit_idx == bits_cfg - 1) begin
                                if (parity_cfg == NONE) current_state <= S_STOP_BIT;
                                else current_state <= S_PARITY_BIT;
                            end else begin
                                bit_idx <= bit_idx + 1;
                            end
                        end
                    end
                end

                S_PARITY_BIT: begin
                    if (sample_tick) begin
                        sample_cnt <= sample_cnt + 1;
                        if (sample_cnt == (OVERSAMPLE_RATE/2 - 1)) begin
                            received_parity <= uart_rx_sync2;
                        end
                        if (sample_cnt == OVERSAMPLE_RATE - 1) begin
                            current_state <= S_STOP_BIT;
                            sample_cnt <= 0;
                        end
                    end
                end

                S_STOP_BIT: begin
                    if (sample_tick) begin
                        sample_cnt <= sample_cnt + 1;
                        if (sample_cnt == OVERSAMPLE_RATE - 1) begin
                            if (uart_rx_sync2 == 1'b1) begin // 第一个停止位正确
                                // *** MODIFIED: Check stop bit configuration ***
                                if (stop_cfg == 2'd2) begin
                                    current_state <= S_STOP_BIT_2;
                                    sample_cnt <= 0;
                                end else begin // 1位停止位, 帧结束
                                    if (parity_cfg != NONE) if (received_parity != expected_parity) parity_error <= 1'b1;
                                    data_byte <= data_byte_reg;
                                    rx_done <= 1'b1;
                                    current_state <= S_IDLE;
                                end
                            end else begin // 帧错误
                                current_state <= S_IDLE;
                            end
                        end
                    end
                end
                
                // *** NEW STATE ***
                S_STOP_BIT_2: begin
                    if (sample_tick) begin
                        sample_cnt <= sample_cnt + 1;
                        if (sample_cnt == OVERSAMPLE_RATE - 1) begin
                            if(uart_rx_sync2 == 1'b1) begin // 第二个停止位正确, 帧结束
                                if (parity_cfg != NONE) if (received_parity != expected_parity) parity_error <= 1'b1;
                                data_byte <= data_byte_reg;
                                rx_done <= 1'b1;
                            end
                            // 无论第二个停止位是否正确, 帧都结束
                            current_state <= S_IDLE;
                        end
                    end
                end

                default: current_state <= S_IDLE;
            endcase
        end
    end
endmodule