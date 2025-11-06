// ============================================================================
// Module: digital_capture_unit.v
// Author: Gemini (调试修正版 v5 - 50MHz FSM - 语法修正)
// Description:
//   1. 修正了 `signal_in` 的异步输入 CDC 问题 (2-flop synchronizer)。
//   2. 修正了 FSM，使其在 50MHz `clk` 下运行，并由 1MHz `s_en` 
//      (sample_clk_enable) 启用，解决了 BRAM 写的 CDC 问题。
//   3. 修正了 `start_capture` 和 `ack` 的逻辑，使用 50MHz 边沿检测。
//   4. **语法修正: 将所有 if/else 块的 {...} 替换为 begin...end**
// ============================================================================
`timescale 1ns / 1ps
module digital_capture_unit(
    input  clk,       // HCLK (50MHz)
    input  reset_n,
    input  start_capture, // 来自 AHB (50MHz 域)
    input  ack,           // 来自 AHB (50MHz 域)
    input  signal_in,     // 异步输入
    output reg capture_ready,

    output reg [4:0]  bram_waddr,
    output reg        bram_we,
    output reg [31:0] bram_wdata,

    output [2:0] debug_state_out
);
    // ========================================================================
    // Section 1: 采样时钟分频器 (1MHz enable)
    // ========================================================================
    localparam SAMPLE_DIVIDER_RATIO = 50; 
    reg [$clog2(SAMPLE_DIVIDER_RATIO)-1:0] clk_divider_cnt;
    reg s_en; // 1MHz sample enable (在 50MHz 下产生一个周期的脉冲)

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin // <-- 语法修正
            clk_divider_cnt <= 0; 
            s_en <= 1'b0; 
        end
        else begin
            if (clk_divider_cnt == SAMPLE_DIVIDER_RATIO - 1) begin // <-- 语法修正
                clk_divider_cnt <= 0; 
                s_en <= 1'b1; // 拉高一个 50MHz 周期
            end else begin // <-- 语法修正
                clk_divider_cnt <= clk_divider_cnt + 1; 
                s_en <= 1'b0;
            end
        end
    end

    // ========================================================================
    // Section 2: 输入信号同步 (Async Pin -> 1MHz Domain)
    // ========================================================================
    reg signal_in_s1, signal_in_s2; // 50MHz 2-flop synchronizer
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin // <-- 语法修正
            signal_in_s1 <= 1'b1; // 默认高电平
            signal_in_s2 <= 1'b1; 
        end
        else begin // <-- 语法修正
            signal_in_s1 <= signal_in; 
            signal_in_s2 <= signal_in_s1; 
        end
    end
    
    reg signal_in_sampled, signal_in_sampled_dly; 
    
    // s_en (1MHz) 使能的采样寄存器
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin // <-- 语法修正
            signal_in_sampled <= 1'b1;
            signal_in_sampled_dly <= 1'b1;
        end
        else if (s_en) begin 
            signal_in_sampled <= signal_in_s2; // 使用同步后的 50MHz 信号
            signal_in_sampled_dly <= signal_in_sampled;
        end
    end
    
    // 1MHz 域的下降沿触发器 (wire 会在 s_en 脉冲时变化)
    wire falling_edge_trigger = signal_in_sampled_dly & ~signal_in_sampled;
    wire rising_edge_trigger  = ~signal_in_sampled_dly & signal_in_sampled; 

    // ========================================================================
    // Section 3: AHB 控制信号 50MHz 边沿检测
    // ========================================================================
    reg start_capture_dly;
    reg ack_dly;
    wire start_pulse = start_capture & ~start_capture_dly;
    wire ack_pulse   = ack & ~ack_dly;
    
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin // <-- 语法修正
            start_capture_dly <= 0; 
            ack_dly <= 0; 
        end
        else begin // <-- 语法修正
            start_capture_dly <= start_capture; 
            ack_dly <= ack; 
        end
    end

    // ========================================================================
    // Section 4: 数据路径 (50MHz 寄存器，s_en 使能)
    // ========================================================================
    reg [31:0] shift_reg;
    reg [4:0]  bit_counter;
    reg [4:0]  word_counter;

    // ========================================================================
    // Section 5: 控制逻辑核心 - 50MHz 状态机
    // ========================================================================
    localparam S_IDLE         = 3'd0,
               S_WAIT_TRIGGER = 3'd1,
               S_CAPTURING    = 3'd2,
               S_WRITE_BRAM   = 3'd3,
               S_DONE         = 3'd4;
    reg [2:0] state;
    assign debug_state_out = state; // 实时输出状态

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            bram_waddr <= 0;
            bram_we <= 0;
            capture_ready <= 0;
            bit_counter <= 0;
            word_counter <= 0;
            bram_wdata <= 0;
            shift_reg <= 0;
        end else begin
            // ** 默认值 (每 50MHz 周期) **
            bram_we <= 1'b0;
            capture_ready <= 1'b0; 

            // ** 高优先级复位 (来自 AHB 50MHz 脉冲) **
            if (ack_pulse) begin
                state <= S_IDLE;
            end
            // ** FSM 主体 **
            else begin
                case (state)
                    S_IDLE: begin
                        // 复位所有计数器
                        bit_counter <= 0;
                        word_counter <= 0;
                        shift_reg <= 0;
                        bram_waddr <= 0;
                        // `start_pulse` 是一个 50MHz 的单脉冲
                        if (start_pulse) begin 
                            state <= S_WAIT_TRIGGER;
                        end
                    end

                    S_WAIT_TRIGGER: begin
                        if (rising_edge_trigger) begin 
                            state <= S_CAPTURING;
                            bit_counter <= 0; // 重置 bit 计数
                            shift_reg <= 0;   // 清空移位寄存器
                        end
                    end

                    S_CAPTURING: begin
                        // **只在 1MHz 脉冲 (s_en) 时执行**
                        if (s_en) begin
                            // 修正: 从 MSB 移入 (与您 v4 保持一致)
                            shift_reg <= {signal_in_sampled, shift_reg[31:1]}; 
                            bit_counter <= bit_counter + 1;

                            // bit_counter 在 1MHz 下计数
                            // 当它为 31 时 (已采集 32 个 bit: 0..31)
                            if (bit_counter == 5'd31) begin
                                state <= S_WRITE_BRAM;
                            end
                        end
                    end

                    S_WRITE_BRAM: begin
                        // ** 这个状态只持续一个 50MHz 周期 **
                        // `s_en` 在这里不再需要
                        bram_we <= 1'b1;
                        bram_wdata <= shift_reg; // 写入 32 bit 的数据
                        bram_waddr <= word_counter;

                        if (word_counter == 5'd31) begin
                            state <= S_DONE;
                        end else begin
                            state <= S_CAPTURING; // 立即返回
                            word_counter <= word_counter + 1;
                        end
                    end

                    S_DONE: begin
                        capture_ready <= 1'b1; // 持续拉高
                        // 等待 ack_pulse (高优先级) 来复位
                    end

                    default: state <= S_IDLE;
                endcase
            end // end else (no ack)
        end // end else (not reset)
    end // end always
endmodule
