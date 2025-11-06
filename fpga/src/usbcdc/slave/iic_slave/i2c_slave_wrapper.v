`timescale 1ns / 1ps

// ===========================================================================
// ** Module: i2c_slave_wrapper **
// ** Description: (全新模块) **
//   此模块封装了 I2C 协议层 (iic_slave.v) 并实现了
//   一个可配置的寄存器地址和 256 字节的内部 RAM 存储。
//   它负责：
//   1. 将来自配置器(parser)的动态从机地址传递给 iic_slave 模块。
//   2. 实现一个状态机，根据 cfg_reg_addr_16bit (8位或16位)
//      来解析主机的写操作，分离 "寄存器地址" 和 "数据"。
//   3. 维护一个内部 RAM 地址指针 (ram_addr)，该指针在读/写时自动递增。
//   4. 响应主机的读操作，从 RAM 中提供数据。
// ===========================================================================
module i2c_slave_wrapper (
    input             clk,        // 系统时钟
    input             rst_n,      // 异步复位, 低有效

    // --- I2C 物理总线 ---
    inout             scl,        // I2C 时钟线
    inout             sda,        // I2C 数据线

    // --- 来自 slave_config_parser.v 的配置输入 ---
    input      [6:0]  cfg_slave_address,       // 动态7位从机地址
    input             cfg_reg_addr_16bit,      // 0=8位寄存器地址, 1=16位

    // --- 调试输出 (可选) ---
    output     [15:0] debug_current_ram_addr,  // 当前内部地址指针
    output     [7:0]  debug_ram_data_out       // RAM 在当前地址的数据
);

//--------------------------------------------------------------------------
// 内部 RAM 定义
//--------------------------------------------------------------------------
    // 定义一个 256 字节的 RAM 来模拟从机寄存器
    // 注意: 即使在16位地址模式下，我们也只使用地址的低8位
    //       如果需要超过256字节，需要实例化一个更大的 RAM
    reg [7:0]  internal_ram [0:255];
    
    // 内部地址指针 (使用16位以容纳两种模式)
    reg [15:0] ram_addr;

//--------------------------------------------------------------------------
// 状态机定义
//--------------------------------------------------------------------------
    reg [1:0]  state;
    localparam STATE_IDLE      = 2'd0; // 空闲, 等待主机寻址
    localparam STATE_RECV_ADDR = 2'd1; // 正在接收寄存器地址 (仅用于16位模式的第2字节)
    localparam STATE_RW_DATA   = 2'd2; // 正在读/写数据
    
    // 状态寄存器
    reg [1:0]  addr_byte_count; // 已接收的地址字节计数器
    reg        is_write;        // 锁存当前事务是写操作

//--------------------------------------------------------------------------
// 连接底层 iic_slave 模块的信号
//--------------------------------------------------------------------------
    wire [7:0] data_from_master_w; // 从 iic_slave 收到的字节
    wire       write_received_w;   // iic_slave 收到一个字节的脉冲
    wire       data_read_ack_w;    // iic_slave 发送的字节被主机 ACK 的脉冲
    wire       slave_selected_w;   // iic_slave 模块当前被选中
    
    reg [7:0]  data_to_master_r; // 要发送给 iic_slave 的字节
    reg        data_valid_r;     // data_to_master_r 有效脉冲

//--------------------------------------------------------------------------
// 状态机与 RAM 访问逻辑 (核心)
//--------------------------------------------------------------------------

    always @(posedge clk or negedge rst_n) begin
        // 默认将脉冲信号拉低
        data_valid_r <= 1'b0;

        if (!rst_n || (state != STATE_IDLE && !slave_selected_w)) begin
            // --- 复位 或 接收到 STOP 条件 ---
            state           <= STATE_IDLE;
            addr_byte_count <= 2'd0;
            is_write        <= 1'b0;
            data_valid_r    <= 1'b0;
            // 注意: ram_addr 指针在 STOP 后保持不变, 这是I2C设备标准行为
            
        end else if (slave_selected_w) begin
            // --- 事务激活 (slave_selected_w 为高) ---
            
            if (write_received_w) begin
                // --- 事件: 主机正在写入一个字节 ---
                is_write <= 1'b1; // 锁存: 这是一个写事务

                if (!cfg_reg_addr_16bit && addr_byte_count == 0) begin
                    // 模式: 8位地址。第1个字节就是寄存器地址
                    ram_addr[7:0]   <= data_from_master_w;
                    ram_addr[15:8]  <= 8'h00;
                    addr_byte_count <= 1; // 标记地址已加载
                    state           <= STATE_RW_DATA;
                
                end else if (cfg_reg_addr_16bit && addr_byte_count == 0) begin
                    // 模式: 16位地址。第1个字节是地址高位 (MSB)
                    ram_addr[15:8]  <= data_from_master_w;
                    addr_byte_count <= 1;
                    state           <= STATE_RECV_ADDR; // 等待第2个字节
                
                end else if (cfg_reg_addr_16bit && addr_byte_count == 1) begin
                    // 模式: 16位地址。第2个字节是地址低位 (LSB)
                    ram_addr[7:0]   <= data_from_master_w;
                    addr_byte_count <= 2; // 标记地址已加载
                    state           <= STATE_RW_DATA;
                
                end else if (state == STATE_RW_DATA) begin
                    // 模式: 地址已加载, 这是一个数据字节
                    internal_ram[ram_addr[7:0]] <= data_from_master_w;
                    ram_addr <= ram_addr + 1; // 地址自动递增
                    state    <= STATE_RW_DATA; // 保持在数据状态
                end

            end else if (state == STATE_IDLE && !is_write) begin
                // --- 事件: 主机正在读取 (第一个字节) ---
                // (条件: 刚被选中, 且不是写事务, 底层在S_TX_BYTE等待数据)
                data_to_master_r <= internal_ram[ram_addr[7:0]];
                data_valid_r     <= 1'b1; // 发送数据
                state            <= STATE_RW_DATA; // 切换到数据状态
            
            end else if (data_read_ack_w) begin
                // --- 事件: 主机正在读取 (后续字节) ---
                // (条件: 主机 ACK 了我们发送的上一个字节)
                ram_addr <= ram_addr + 1; // 地址自动递增
                // 预取下一个字节
                data_to_master_r <= internal_ram[(ram_addr[7:0] + 1'b1)]; 
                data_valid_r     <= 1'b1; // 发送数据
                state            <= STATE_RW_DATA; // 保持在数据状态
            end
            
        end // if (slave_selected_w)
    end // always

//--------------------------------------------------------------------------
// 调试信号
//--------------------------------------------------------------------------
    assign debug_current_ram_addr = ram_addr;
    assign debug_ram_data_out = internal_ram[ram_addr[7:0]];

//--------------------------------------------------------------------------
// 例化 I2C 协议层 (iic_slave.v)
//--------------------------------------------------------------------------
    iic_slave u_i2c_protocol_engine (
        .clk        (clk),
        .rst_n      (rst_n),
        
        // --- 动态配置端口 ---
        .dynamic_slave_address (cfg_slave_address), // 传递动态地址
        
        // --- I2C 总线 ---
        .scl        (scl),
        .sda        (sda),
        
        // --- 接口 (连接到本模块的状态机) ---
        .data_to_master  (data_to_master_r),
        .data_valid      (data_valid_r),
        .data_read_ack   (data_read_ack_w),
        
        .data_from_master(data_from_master_w),
        .write_received  (write_received_w),
        
        .slave_selected  (slave_selected_w)
    );

endmodule