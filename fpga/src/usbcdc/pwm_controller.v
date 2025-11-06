//多通道PWM控制器, 连接到内部配置总线。
//              它管理多个 pwm_channel 实例，并支持无毛刺的影子寄存器更新。

`timescale 1ns / 1ps
`include "address_map.vh"

module pwm_controller #(
    parameter NUM_CHANNELS = 4
)(
    input             clk,
    input             rst_n,

    // --- 配置总线接口 (来自 command_parser) ---
    input      [15:0] cfg_addr,
    input      [31:0] cfg_wdata,
    input             cfg_write,

    // --- PWM 输出 ---
    output     [NUM_CHANNELS-1:0] pwm_outs
);

    // ==========================================================
    // == 信号定义
    // ==========================================================
    
    // --- 状态寄存器 (在时序逻辑中更新) ---
    reg [31:0] period_in_r [NUM_CHANNELS-1:0];
    reg [31:0] duty_in_r   [NUM_CHANNELS-1:0];
    reg [NUM_CHANNELS-1:0] enable_in_r;

    // --- 下一状态信号 (在组合逻辑中计算) ---
    reg [31:0] period_in_next [NUM_CHANNELS-1:0];
    reg [31:0] duty_in_next   [NUM_CHANNELS-1:0];
    reg [NUM_CHANNELS-1:0] enable_in_next;
    
    // --- 内部连线 ---
    reg [NUM_CHANNELS-1:0] update_regs_w;

        integer i;
        
        reg [NUM_CHANNELS-1:0] channel_sel_onehot;
        reg [15:0]             reg_offset;
    // ==========================================================
    // == 组合逻辑: 解码总线信号, 计算下一状态
    // ==========================================================
    always @(*) begin
        // --- 默认值 ---
        update_regs_w = 0;
        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
            period_in_next[i] = period_in_r[i];
            duty_in_next[i]   = duty_in_r[i];
            enable_in_next[i] = enable_in_r[i];
        end

        // --- 地址解码 ---
        channel_sel_onehot = 0;
        reg_offset         = 0;
        if (cfg_write && cfg_addr >= `PWM_BASE_ADDR && cfg_addr < (`PWM_BASE_ADDR + NUM_CHANNELS * `PWM_CHANNEL_STRIDE)) begin
            i = (cfg_addr - `PWM_BASE_ADDR) / `PWM_CHANNEL_STRIDE;
            channel_sel_onehot = (1 << i);
            reg_offset = cfg_addr - (`PWM_BASE_ADDR + i * `PWM_CHANNEL_STRIDE);
        end

        // --- 数据路由: 根据解码结果计算下一状态的值 ---
        if (channel_sel_onehot != 0) begin
            update_regs_w = channel_sel_onehot;
            i = (cfg_addr - `PWM_BASE_ADDR) / `PWM_CHANNEL_STRIDE;

            case (reg_offset)
                `PWM_REG_OFFSET_PERIOD: period_in_next[i] = cfg_wdata;
                `PWM_REG_OFFSET_DUTY:   duty_in_next[i]   = cfg_wdata;
                `REG_OFFSET_CTRL:      enable_in_next[i] = cfg_wdata[0];
                default: ; // 保持默认值
            endcase
        end
    end

    // ==========================================================
    // == 时序逻辑: 在时钟边沿更新状态寄存器
    // ==========================================================
    always @(posedge clk or negedge rst_n) begin
        // ** 修正 #1: 遵循 Verilog-1995, 在块开头声明循环变量 **
        if (!rst_n) begin
            // ** 修正 #2: 在循环中不再声明 'integer i' **
            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                period_in_r[i] <= 0;
                duty_in_r[i]   <= 0;
                enable_in_r[i] <= 1'b0;
            end
        end else begin

            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                period_in_r[i] <= period_in_next[i];
                duty_in_r[i]   <= duty_in_next[i];
                enable_in_r[i] <= enable_in_next[i];
            end
        end
    end

    // ==========================================================
    // == 模块例化
    // ==========================================================
    genvar j;
    generate
        for (j = 0; j < NUM_CHANNELS; j = j + 1) begin : gen_pwm_channels
            pwm_channel u_pwm_channel (
                .clk         (clk),
                .rst_n       (rst_n),
                .update_regs (update_regs_w[j]),
                .period_in   (period_in_r[j]),
                .duty_in     (duty_in_r[j]),
                .enable_in   (enable_in_r[j]),
                .pwm_out     (pwm_outs[j])
            );
        end
    endgenerate

endmodule