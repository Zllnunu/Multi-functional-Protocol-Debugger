//根据PC发出来的指令解析之后进行对应的操作
// File: pwm_channel.v
// Description: 带影子寄存器的单通道PWM生成器，支持无毛刺更新

// File: pwm_channel.v (最终优化版 - 增加流水线以满足时序)
// Description: 带影子寄存器的单通道PWM生成器，支持无毛刺更新

module pwm_channel (
    input             clk,
    input             rst_n,

    // --- 配置输入 ---
    input             update_regs,    // 寄存器更新使能信号
    input      [31:0] period_in,      // 周期设置
    input      [31:0] duty_in,        // 占空比设置
    input             enable_in,      // 通道使能

    // --- PWM 输出 ---
    output            pwm_out
);
    // --- 影子寄存器 (Shadow Registers) ---
    reg [31:0] period_shadow_reg;
    reg [31:0] duty_shadow_reg;
    reg        enable_shadow_reg;

    // --- 活动寄存器 (Active Registers) ---
    reg [31:0] period_active_reg;
    reg [31:0] duty_active_reg;
    reg        enable_active_reg;

    // --- PWM 计数器 ---
    reg [31:0] counter;
    reg        pwm_out_reg; // MODIFIED: 使用寄存器作为PWM输出

    // --- MODIFIED: 为长路径增加流水线寄存器 ---
    reg        counter_reset_cond; // 寄存比较结果
    reg        pwm_out_cond;       // 寄存比较结果

    // 逻辑块 1: 更新影子寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            period_shadow_reg <= 0;
            duty_shadow_reg   <= 0;
            enable_shadow_reg <= 1'b0;
        end else if (update_regs) begin
            period_shadow_reg <= period_in;
            duty_shadow_reg   <= duty_in;
            enable_shadow_reg <= enable_in;
        end
    end

    // 逻辑块 2: PWM核心逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            pwm_out_reg <= 1'b0;
            period_active_reg <= 0;
            duty_active_reg   <= 0;
            enable_active_reg <= 1'b0;
        end else begin
            if (enable_active_reg && period_active_reg > 0) begin
                // --- PWM 计数器逻辑 (流水线化) ---
                if (counter_reset_cond) begin
                    counter <= 0;
                end else begin
                    counter <= counter + 1;
                end

                // --- PWM 输出逻辑 (流水线化) ---
                pwm_out_reg <= pwm_out_cond;

                // --- 周期结束时，同步更新活动寄存器 ---
                if (counter_reset_cond) begin
                    period_active_reg <= period_shadow_reg;
                    duty_active_reg   <= duty_shadow_reg;
                    enable_active_reg <= enable_shadow_reg;
                end
            end else begin
                // 如果不使能，则所有状态回到复位值
                counter <= 0;
                pwm_out_reg <= 1'b0;
                // 即使在不使能时，也需要同步更新，以便下一次使能时使用最新参数
                period_active_reg <= period_shadow_reg;
                duty_active_reg   <= duty_shadow_reg;
                enable_active_reg <= enable_shadow_reg;
            end
        end
    end

    // --- MODIFIED: 将组合逻辑移出核心 always 块 ---
    // 在这里进行耗时的比较运算，其结果将在下一个时钟周期被寄存
    always @(*) begin
        // 决定计数器是否在下一个周期复位
        if (period_active_reg > 0 && counter >= period_active_reg - 1) begin
            counter_reset_cond = 1'b1;
        end else begin
            counter_reset_cond = 1'b0;
        end
        
        // 决定PWM输出在下一个周期的电平
        if (counter < duty_active_reg) begin
            pwm_out_cond = 1'b1;
        end else begin
            pwm_out_cond = 1'b0;
        end
    end
    
    assign pwm_out = pwm_out_reg;

endmodule