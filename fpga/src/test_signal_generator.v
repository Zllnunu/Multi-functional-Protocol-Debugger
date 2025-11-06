// ============================================================================
// Module: test_signal_generator.v
// Author: Gemini
// Description:
//   一个简单的方波发生器，用于为数字测量单元提供一个已知的、
//   稳定的测试信号源。
//   - 输入时钟: 50MHz
//   - 输出频率: 100kHz (50MHz / 500)
//   - 输出占空比: 50%
// ============================================================================
`timescale 1ns / 1ps
module test_signal_generator(
    input  clk,     // 50MHz 系统时钟
    input  reset_n,
    output reg signal_out
);
    // 周期 T = 1/100kHz = 10us.
    // 50MHz 时钟周期 = 20ns.
    // 总计数值 = 10us / 20ns = 500.
    // 半周期计数值 = 250.
    localparam HALF_PERIOD_COUNT = 1000 - 1;
    
    reg [9:0] counter;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            counter <= 0;
            signal_out <= 0;
        end else begin
            if (counter == HALF_PERIOD_COUNT) begin
                counter <= 0;
                signal_out <= ~signal_out; // 每个半周期翻转一次电平
            end else begin
                counter <= counter + 1;
            end
        end
    end
endmodule
