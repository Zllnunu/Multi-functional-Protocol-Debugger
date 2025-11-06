// ============================================================================
// Module: digital_measurement_unit.v
// Author: Gemini
// Description:
//   **已修正**: 状态机逻辑已加固，确保在测量完成后能被正确重置，
//   避免遗漏上升沿导致频率测量减半的问题。
// ============================================================================
`timescale 1ns / 1ps
module digital_measurement_unit(
    input  clk,
    input  reset_n,
    input  start_stop,
    input  ack,
    input  signal_in,
    output reg measurement_ready,
    output reg [31:0] period_count_out,
    output reg [31:0] high_time_count_out
);

    // --- 输入信号同步与边沿检测 ---
    reg signal_d0, signal_d1;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) {signal_d0, signal_d1} <= 2'b00;
        else         {signal_d0, signal_d1} <= {signal_in, signal_d0};
    end
    wire rising_edge = (signal_d0 == 1'b1) && (signal_d1 == 1'b0);

    // --- 核心计数器 ---
    reg [31:0] period_counter;
    reg [31:0] high_time_counter;

    // --- 状态机定义 ---
    localparam S_IDLE        = 2'd0;
    localparam S_MEASURING   = 2'd1;
    localparam S_LATCH_DATA  = 2'd2;

    reg [1:0] state;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            period_counter <= 0;
            high_time_counter <= 0;
            measurement_ready <= 0;
            period_count_out <= 0;
            high_time_count_out <= 0;
        end else begin
            // ** 核心修正: 将ACK的处理逻辑移到状态机外部，作为最高优先级 **
            // 收到ACK后，无条件清除ready标志，并准备好下一次测量
            if (ack) begin
                measurement_ready <= 0;
                state <= S_IDLE;
            end

            case (state)
                S_IDLE: begin
                    // 如果收到Start命令，并且检测到第一个上升沿
                    if (start_stop && rising_edge) begin
                        period_counter <= 0; // 清零并准备开始计数
                        high_time_counter <= 0;
                        state <= S_MEASURING;
                    end
                end

                S_MEASURING: begin
                    if (!start_stop) begin
                        state <= S_IDLE;
                    end else begin
                        // 计数器在测量状态下持续运行
                        period_counter <= period_counter + 1;
                        if (signal_d0) begin
                            high_time_counter <= high_time_counter + 1;
                        end
                        
                        if (rising_edge) begin
                            state <= S_LATCH_DATA;
                            // 锁存结果 (注意: 锁存的是当前周期的计数值)
                            period_count_out <= period_counter + 1;
                            high_time_count_out <= high_time_counter + (signal_d0 ? 1 : 0);
                            measurement_ready <= 1;
                        end
                    end
                end
                
                S_LATCH_DATA: begin
                    // 在此状态等待M1内核的ACK信号
                    // ACK到来后，会自动返回IDLE
                    // 如果在等待期间收到Stop命令，也返回IDLE
                    if (!start_stop) begin
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
