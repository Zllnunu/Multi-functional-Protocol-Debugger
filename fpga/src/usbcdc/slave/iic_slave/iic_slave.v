`timescale 1ns / 1ps

// ===========================================================================
// ** MODIFIED VERSION (支持 7 位和 10 位地址) **
// 1. 增加了 10 位地址输入端口 (dynamic_10bit_address, enable_10bit_mode)
// 2. S_ADDR_MATCH 状态现在可以匹配 7 位地址或 10 位地址帧头 (11110)
// 3. 增加了 S_10B_* 状态来处理 10 位地址的接收和匹配
// ===========================================================================
module i2c_slave (
    input             clk,        // System clock (must be faster than SCL)
    input             rst_n,      // Asynchronous reset, active low

    // --- 动态配置输入 ---
    input             enable_10bit_mode,     // 1 = 使能 10 位地址匹配
    input      [6:0]  dynamic_7bit_address,  // 动态 7 位从机地址
    input      [9:0]  dynamic_10bit_address, // 动态 10 位从机地址

    // I2C Bus Lines
    inout             scl,
    inout             sda,

    // --- 接口到用户逻辑 (Wrapper) ---
    input      [7:0]  data_to_master,
    input             data_valid,
    output reg        data_read_ack,
    output reg [7:0]  data_from_master,
    output reg        write_received,
    output reg        slave_selected
);

//--------------------------------------------------------------------------
// 状态定义
//--------------------------------------------------------------------------
    localparam S_IDLE              = 5'd0;
    localparam S_START_DETECTED    = 5'd1;
    localparam S_ADDR_MATCH        = 5'd2; // 匹配第1个地址字节 (7-bit 或 10-bit 头)
    localparam S_ADDR_ACK_TX       = 5'd3;
    localparam S_RX_BYTE           = 5'd4;
    localparam S_RX_ACK_TX         = 5'd5;
    localparam S_TX_BYTE           = 5'd6;
    localparam S_TX_ACK_RX         = 5'd7;
    localparam S_WAIT_STOP         = 5'd8;
    // --- 10-bit 新增状态 ---
    localparam S_10B_ADDR_ACK_TX   = 5'd10; // 匹配10-bit头后的ACK
    localparam S_10B_RECV_ADDR2    = 5'd11; // 接收10-bit地址的第2字节 (A7-A0)
    localparam S_10B_ADDR2_ACK_TX  = 5'd12; // 匹配10-bit第2字节后的ACK

//--------------------------------------------------------------------------
// 内部信号
//--------------------------------------------------------------------------
    // Synchronizers
    reg [2:0] scl_sync, sda_sync;
    wire      scl_in_reg, sda_in_reg;
    wire      scl_rising, scl_falling;
    wire      start_cond, stop_cond;

    // State machine
    reg [4:0]  current_state, next_state;
    reg [2:0]  bit_count;
    reg [7:0]  shift_reg;
    reg        rw_bit_7b; // 存储 7-bit 读写标志

    // 10-bit 专用寄存器
    reg [1:0]  stored_A9_A8;    // 存储 10-bit 地址的高2位
    reg [7:0]  stored_A7_A0;    // 存储 10-bit 地址的低8位
    reg        rw_bit_10b;    // 存储 10-bit 帧头的 R/W 标志

    // Output registers
    reg        scl_out_en_reg;
    reg        sda_out_en_reg;
    reg        scl_out_reg;
    reg        sda_out_reg;
    
//--------------------------------------------------------------------------
// I/O 逻辑
//--------------------------------------------------------------------------
    assign scl = scl_out_en_reg ? scl_out_reg : 1'bz;
    assign sda = sda_out_en_reg ? sda_out_reg : 1'bz;

//--------------------------------------------------------------------------
// 输入同步与边沿检测
//--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_sync <= 3'b111;
            sda_sync <= 3'b111;
        end else begin
            scl_sync <= {scl_sync[1:0], scl};
            sda_sync <= {sda_sync[1:0], sda};
        end
    end
    
    assign scl_in_reg = scl_sync[1];
    assign sda_in_reg = sda_sync[1];
    assign scl_rising  = (scl_sync[2:1] == 2'b01);
    assign scl_falling = (scl_sync[2:1] == 2'b10);
    assign start_cond = scl_in_reg && (sda_sync[2:1] == 2'b10);
    assign stop_cond  = scl_in_reg && (sda_sync[2:1] == 2'b01);

//--------------------------------------------------------------------------
// 主状态机 (组合逻辑)
//--------------------------------------------------------------------------
    always @(*) begin
        // Default values
        next_state      = current_state;
        scl_out_en_reg  = 1'b0;
        sda_out_en_reg  = 1'b0;
        scl_out_reg     = 1'b0;
        sda_out_reg     = 1'b0;
        write_received  = 1'b0;
        data_read_ack   = 1'b0;
        
        // --- 时钟拉伸 (Clock Stretching) ---
        if (slave_selected && !scl_in_reg) begin
            if (current_state == S_TX_BYTE && !data_valid) begin
                scl_out_en_reg = 1'b1; // Drive SCL low
                scl_out_reg    = 1'b0;
            end
        end

        case (current_state)
            S_IDLE: begin
                slave_selected = 1'b0;
                if (start_cond) begin
                    next_state = S_START_DETECTED;
                    bit_count  = 3'd0;
                    shift_reg  = 8'h00;
                end
            end

            S_START_DETECTED: begin
                if (scl_falling) begin
                    next_state = S_ADDR_MATCH;
                end
            end

            S_ADDR_MATCH: begin
                if (scl_rising) begin
                    shift_reg = {shift_reg[6:0], sda_in_reg};
                    if (bit_count == 3'd7) begin
                        // --- 地址匹配逻辑 ---
                        if (shift_reg[7:1] == dynamic_7bit_address) begin
                            // ** 7-bit 地址匹配 **
                            slave_selected = 1'b1;
                            rw_bit_7b  = shift_reg[0];
                            next_state = S_ADDR_ACK_TX;
                        end
                        else if (enable_10bit_mode && (shift_reg[7:3] == 5'b11110)) begin
                            // ** 10-bit 地址帧头匹配 **
                            stored_A9_A8 = shift_reg[2:1];
                            rw_bit_10b   = shift_reg[0];
                            next_state   = S_10B_ADDR_ACK_TX;
                        end
                        else begin
                            // 地址不匹配, 等待 STOP
                            next_state = S_WAIT_STOP;
                        end
                        bit_count = 3'd0;
                    end else begin
                        bit_count = bit_count + 1'b1;
                    end
                end
            end
            
            S_ADDR_ACK_TX: begin // 7-bit 地址的 ACK
                sda_out_en_reg = 1'b1;
                sda_out_reg    = 1'b0; 
                if (scl_falling) begin
                    if (rw_bit_7b == 1'b0) begin // Master Write
                        next_state = S_RX_BYTE;
                    end else begin // Master Read
                        next_state = S_TX_BYTE;
                    end
                    bit_count = 3'd0;
                    shift_reg = 8'h00;
                end
            end
            
            // --- 10-bit 状态 ---
            S_10B_ADDR_ACK_TX: begin // 10-bit 帧头的 ACK
                sda_out_en_reg = 1'b1;
                sda_out_reg    = 1'b0;
                if (scl_falling) begin
                    bit_count = 3'd0;
                    shift_reg = 8'h00;
                    if (rw_bit_10b == 1'b0) begin
                        // Master Write (或 10-bit Read 的设置阶段)
                        // 准备接收第 2 个地址字节 (A7-A0)
                        next_state = S_10B_RECV_ADDR2;
                    end else begin
                        // Master Read (10-bit Read 的最终读取阶段)
                        // 检查存储的地址是否匹配
                        if ({stored_A9_A8, stored_A7_A0} == dynamic_10bit_address) begin
                            slave_selected = 1'b1;
                            next_state = S_TX_BYTE; // 匹配, 准备发送数据
                        end else begin
                            next_state = S_WAIT_STOP; // 不匹配
                        end
                    end
                end
            end

            S_10B_RECV_ADDR2: begin // 接收 10-bit 地址的 A7-A0
                if (scl_rising) begin
                    shift_reg = {shift_reg[6:0], sda_in_reg};
                    if (bit_count == 3'd7) begin
                        stored_A7_A0 = shift_reg;
                        // 检查完整 10-bit 地址是否匹配
                        if ({stored_A9_A8, shift_reg} == dynamic_10bit_address) begin
                            next_state = S_10B_ADDR2_ACK_TX; // 匹配, 准备 ACK
                        end else begin
                            next_state = S_WAIT_STOP; // 不匹配
                        end
                    end else begin
                        bit_count = bit_count + 1'b1;
                    end
                end
            end

            S_10B_ADDR2_ACK_TX: begin // 10-bit 第2字节的 ACK
                sda_out_en_reg = 1'b1;
                sda_out_reg    = 1'b0;
                if (scl_falling) begin
                    // 此时, 10-bit Write (rw_bit_10b=0) 已经完成
                    // 地址指针已设置, 准备接收数据
                    slave_selected = 1'b1;
                    next_state = S_RX_BYTE;
                    bit_count = 3'd0;
                    shift_reg = 8'h00;
                    // (10-bit Read 的设置阶段也在此完成, 等待 R-START)
                end
            end

            // --- 共享的 RX/TX 状态 ---
            S_RX_BYTE: begin
                if (scl_rising) begin
                    shift_reg = {shift_reg[6:0], sda_in_reg};
                    if (bit_count == 3'd7) begin
                        next_state = S_RX_ACK_TX;
                        data_from_master = {shift_reg[6:0], sda_in_reg};
                        write_received   = 1'b1;
                        bit_count = 3'd0;
                    end else begin
                        bit_count = bit_count + 1'b1;
                    end
                end
            end
            
            S_RX_ACK_TX: begin
                sda_out_en_reg = 1'b1;
                sda_out_reg    = 1'b0;
                if (scl_falling) begin
                    next_state = S_RX_BYTE;
                    bit_count  = 3'd0;
                end
            end

            S_TX_BYTE: begin
                if (data_valid) begin
                    if (bit_count == 3'd0) begin
                         shift_reg = data_to_master;
                    end
                    sda_out_en_reg = 1'b1;
                    sda_out_reg    = shift_reg[7];
                    
                    if (scl_falling) begin
                        shift_reg = {shift_reg[6:0], 1'b0};
                        if (bit_count == 3'd7) begin
                            next_state = S_TX_ACK_RX;
                        end else begin
                            bit_count = bit_count + 1'b1;
                        end
                    end
                end
            end

            S_TX_ACK_RX: begin
                sda_out_en_reg = 1'b0; 
                if (scl_rising) begin
                    if (sda_in_reg == 1'b0) begin
                        data_read_ack = 1'b1;
                        next_state    = S_TX_BYTE;
                    end else begin
                        next_state    = S_IDLE; // NACK
                    end
                end
                if (stop_cond) next_state = S_IDLE;
            end

            S_WAIT_STOP: begin
                 sda_out_en_reg = 1'b0;
                 if (stop_cond) begin
                     next_state = S_IDLE;
                 end else if (start_cond) begin
                     next_state = S_START_DETECTED;
                     bit_count = 3'd0;
                 end
            end
            default: next_state = S_IDLE;
        endcase

        if (stop_cond && current_state != S_WAIT_STOP) begin
            next_state = S_IDLE;
        end
    end

//--------------------------------------------------------------------------
// 状态机寄存器 (时序)
//--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            slave_selected <= 1'b0;
            // 10-bit 寄存器
            stored_A9_A8 <= 2'b00;
            stored_A7_A0 <= 8'h00;
            rw_bit_10b   <= 1'b0;
        end else begin
            current_state <= next_state;
            slave_selected <= slave_selected; // 在组合逻辑中赋值
            
            // 锁存 10-bit 信息
            if (next_state == S_10B_ADDR_ACK_TX) begin
                stored_A9_A8 <= stored_A9_A8;
                rw_bit_10b   <= rw_bit_10b;
            end
            if (next_state == S_10B_ADDR2_ACK_TX) begin
                stored_A7_A0 <= stored_A7_A0;
            end
        end
    end
    
    // (其余 data_from_master, write_received, data_read_ack 的时序逻辑保持不变)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_from_master <= 8'h00;
            write_received   <= 1'b0;
            data_read_ack    <= 1'b0;
        end else begin
            data_from_master <= (write_received) ? data_from_master : data_from_master;
            write_received   <= write_received; // 组合逻辑脉冲
            data_read_ack    <= data_read_ack;  // 组合逻辑脉冲
        end
    end

endmodule