`timescale 1ns / 1ps
`include "address_map.vh"

//
// 模块: sequence_generator.v
// 功能: 多通道自定义序列发生器
//       - 通过内部总线配置
//       - 支持多通道、自定义长度、循环/单次模式、独立时钟分频
//       - 支持全局同步触发
//
module sequence_generator #(
    parameter NUM_CHANNELS = 4,
    parameter MAX_SEQ_LEN  = 256, // 每个序列的最大长度 (bit)
    parameter ADDR_WIDTH   = $clog2(MAX_SEQ_LEN)
)(
    input                       clk,
    input                       rst_n,

    // --- 配置总线接口 (来自 command_parser) ---
    input      [15:0]           cfg_addr,
    input      [31:0]           cfg_wdata,
    input                       cfg_write,

    // --- 序列输出 ---
    output     [NUM_CHANNELS-1:0] seq_outs
);
//================================================================
//== 1. 内部寄存器定义
//================================================================

// --- 存储每个通道的配置 ---
reg [MAX_SEQ_LEN-1:0]   sequence_data_r [NUM_CHANNELS-1:0];
reg [ADDR_WIDTH-1:0]    sequence_len_r  [NUM_CHANNELS-1:0];
// ** MODIFIED START **
// 将分频器扩展到32位以支持低频
reg [31:0]              clk_divider_r   [NUM_CHANNELS-1:0];
// ** MODIFIED END **
reg                     loop_enable_r   [NUM_CHANNELS-1:0];
reg                     arm_r           [NUM_CHANNELS-1:0];
// 'arm' 用于预备通道

// --- 全局同步触发信号和各通道的运行状态 ---
reg                     sync_go_trigger;
reg [NUM_CHANNELS-1:0]  running_state_r;


//================================================================
//== 2. 总线从机逻辑 (接收来自 command_parser 的配置)
//================================================================
    
    // --- 地址解码 ---
    wire [3:0]  ch_index;
// 支持最多16通道
    wire [15:0] reg_offset;
    
    assign ch_index = (cfg_addr - `SEQ_BASE_ADDR) / `SEQ_CHANNEL_STRIDE;
    assign reg_offset = cfg_addr - (`SEQ_BASE_ADDR + ch_index * `SEQ_CHANNEL_STRIDE);

    // --- 写操作逻辑 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_go_trigger <= 1'b0;
            for (integer i = 0; i < NUM_CHANNELS; i = i + 1) begin
                sequence_data_r[i] <= 0;
                sequence_len_r[i]  <= 0;
                clk_divider_r[i]   <= 32'd0; // MODIFIED: 32-bit reset
                loop_enable_r[i]   <= 1'b0;
                arm_r[i]           <= 1'b0;
            end
        end else begin
            // 触发信号是自复位的，只持续一个时钟周期
            if(sync_go_trigger) begin
                sync_go_trigger <= 1'b0;
            end

            // 通道配置写操作
            if (cfg_write && (cfg_addr >= `SEQ_BASE_ADDR) && (cfg_addr < (`SEQ_BASE_ADDR + NUM_CHANNELS * `SEQ_CHANNEL_STRIDE))) begin
                case (reg_offset)
                    `SEQ_REG_OFFSET_DATA0: sequence_data_r[ch_index][31:0]     <= cfg_wdata;
                    `SEQ_REG_OFFSET_DATA1: sequence_data_r[ch_index][63:32]    <= cfg_wdata;
                    `SEQ_REG_OFFSET_DATA2: sequence_data_r[ch_index][95:64]    <= cfg_wdata;
                    `SEQ_REG_OFFSET_DATA3: sequence_data_r[ch_index][127:96]   <= cfg_wdata;
                    `SEQ_REG_OFFSET_DATA4: sequence_data_r[ch_index][159:128]  <= cfg_wdata;
                    `SEQ_REG_OFFSET_DATA5: sequence_data_r[ch_index][191:160]  <= cfg_wdata;
                    `SEQ_REG_OFFSET_DATA6: sequence_data_r[ch_index][223:192]  <= cfg_wdata;
                    `SEQ_REG_OFFSET_DATA7: sequence_data_r[ch_index][255:224]  <= cfg_wdata;
                    `SEQ_REG_OFFSET_CONFIG: begin
                        sequence_len_r[ch_index] <= cfg_wdata[ADDR_WIDTH-1:0];
                        // ** MODIFIED START **
                        // clk_divider_r[ch_index]  <= cfg_wdata[23:8]; // (已移除)
                        // ** MODIFIED END **
                        loop_enable_r[ch_index]  <= cfg_wdata[24];
                    end
                    `SEQ_REG_OFFSET_CTRL: begin
                        arm_r[ch_index] <= cfg_wdata[0];
                    end
                    // ** MODIFIED START **
                    // 添加新的case来接收32位分频器
                    `SEQ_REG_OFFSET_DIVISOR: begin
                        clk_divider_r[ch_index] <= cfg_wdata;
                    end
                    // ** MODIFIED END **
                endcase
            // 全局控制写操作
            end else if (cfg_write && cfg_addr == `SEQ_GLOBAL_CTRL_ADDR) begin
                if (cfg_wdata[0]) begin
                    sync_go_trigger <= 1'b1;
// 触发GO信号
                end
            end
        end
    end

//================================================================
//== 3. 序列发生器核心逻辑 (多通道并行)
//================================================================
    genvar j;
    generate
        for (j = 0; j < NUM_CHANNELS; j = j + 1) begin : gen_seq_channels
            
            // ** MODIFIED START **
            // 将计数器扩展到32位
            reg [31:0]           div_cnt;
            // ** MODIFIED END **
            reg [ADDR_WIDTH-1:0] seq_ptr;
            wire                 tick_w;

            // -- 运行状态控制逻辑 --
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    running_state_r[j] <= 1'b0;
                end else if (!arm_r[j]) begin
                    running_state_r[j] <= 1'b0;
// 如果通道被disarm，则立即停止
                end else if (sync_go_trigger) begin
                    running_state_r[j] <= 1'b1;
// 当 arm=1 且收到全局GO信号时，开始运行
                end else if (tick_w && (seq_ptr == sequence_len_r[j] - 1'b1) && !loop_enable_r[j]) begin
                    running_state_r[j] <= 1'b0;
// 单次模式下，运行完一个周期后停止
                end
            end

            // -- 独立时钟分频器 --
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    div_cnt <= 32'd0; // MODIFIED: 32-bit reset
                end else if (!running_state_r[j]) begin 
                    div_cnt <= 32'd0; // MODIFIED: 32-bit reset
// 不运行时复位
                end else if (div_cnt >= clk_divider_r[j]) begin
                    div_cnt <= 32'd0; // MODIFIED: 32-bit reset
                end else begin
                    div_cnt <= div_cnt + 1;
                end
            end
            assign tick_w = (running_state_r[j] && (div_cnt == clk_divider_r[j]));

            // -- 独立序列指针 --
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    seq_ptr <= 0;
                end else if (!running_state_r[j]) begin 
                    seq_ptr <= 0;
// 不运行时复位
                end else if (tick_w) begin // 仅在分频时钟有效时移动指针
                    if (seq_ptr >= sequence_len_r[j] - 1'b1) begin
                        if (loop_enable_r[j]) begin
                           seq_ptr <= 0; // 循环模式，回到开头
                        end
                        // 单次模式则停留在最后一位
                    end else begin
                       seq_ptr <= seq_ptr + 1;
                    end
                end
            end
            
            // -- 输出逻辑 --
            assign seq_outs[j] = (running_state_r[j]) ?
                                 sequence_data_r[j][seq_ptr] : 1'b0;

        end
    endgenerate

endmodule