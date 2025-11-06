`timescale 1ns / 1ps

// ===========================================================================
// ** Module: spi_slave_robust **
// ** Description: (修复 RX FIFO 写入时机问题) **
//   1. 完全同步设计：所有逻辑运行在系统 'clk' 时钟域。
//   2. 信号同步：SPI 输入信号 (cs, sck, mosi) 经过3级同步器。
//   3. 动态模式配置：通过 cfg_cpol 和 cfg_cpha 支持所有4种模式。
//   4. FIFO 缓冲：内置 TX 和 RX 同步 FIFO，解耦协议层和用户逻辑。
//   5. 灵活数据长度：只要 CS 为低，就可以连续收发数据。
// ===========================================================================

module spi_slave_robust #(
    parameter FIFO_DEPTH_BITS = 4 // FIFO 深度 (4 -> 16 字节)
)(
    input             clk,        // 系统时钟
    input             rst_n,      // 系统复位, 低有效

    // --- 物理 SPI 接口 (来自主机) ---
    input             spi_cs,
    input             spi_sck,
    input             spi_mosi,
    output            spi_miso,

    // --- 动态配置输入 ---
    input             cfg_cpol,   // CPOL (0 or 1)
    input             cfg_cpha,   // CPHA (0 or 1)

    // --- 用户逻辑接口 (TX - 数据从用户 -> SPI) ---
    input             user_tx_valid, // 用户断言: user_tx_data 有效
    input      [7:0]  user_tx_data,  // 用户要发送的数据
    output            tx_fifo_full,  // 反压: 告诉用户 TX FIFO 已满

    // --- 用户逻辑接口 (RX - 数据从 SPI -> 用户) ---
    output            user_rx_valid, // 脉冲: user_rx_data 有效
    output     [7:0]  user_rx_data,  // 从 SPI 收到的数据
    input             user_rx_pop    // 用户断言: 已接收数据, 弹出 FIFO
);
//--------------------------------------------------------------------------
// 1. 输入信号同步
//--------------------------------------------------------------------------
    reg [2:0] sck_sync, mosi_sync, cs_sync;
    wire      sck_reg, mosi_reg, cs_reg;
    wire      sck_prev, cs_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sck_sync  <= 3'b0;
            mosi_sync <= 3'b0;
            cs_sync   <= 3'b1; // CS 默认高
        end else begin
            sck_sync  <= {sck_sync[1:0], spi_sck};
            mosi_sync <= {mosi_sync[1:0], spi_mosi};
            cs_sync   <= {cs_sync[1:0], spi_cs};
        end
    end

    assign sck_reg  = sck_sync[1];
    assign sck_prev = sck_sync[2]; // 延迟一拍的 sck
    assign mosi_reg = mosi_sync[1];
    assign cs_reg   = cs_sync[1];
    assign cs_prev  = cs_sync[2]; // 延迟一拍的 cs
    
//--------------------------------------------------------------------------
// 2. 边沿检测 (在 'clk' 域)
//--------------------------------------------------------------------------
    wire sck_adj, sck_adj_prev;
    wire sck_rising_adj, sck_falling_adj;
    wire sample_edge, shift_edge;
    
    assign sck_adj = sck_reg ^ cfg_cpol; // CPOL 调整 (空闲为 0)
    assign sck_adj_prev = sck_prev ^ cfg_cpol;
    assign sck_rising_adj  = ~sck_adj_prev & sck_adj; // 调整后的上升沿
    assign sck_falling_adj = sck_adj_prev & ~sck_adj; // 调整后的下降沿
    
    // 根据 CPHA 确定采样和移出边沿
    assign sample_edge = (cfg_cpha == 0) ? sck_falling_adj : sck_rising_adj;
    assign shift_edge  = (cfg_cpha == 0) ? sck_rising_adj : sck_falling_adj;
    
    // CS 边沿检测
    wire cs_falling = cs_prev & ~cs_reg;
    wire cs_rising  = ~cs_prev & cs_reg;
    
//--------------------------------------------------------------------------
// 3. 核心收发逻辑
//--------------------------------------------------------------------------
    reg [2:0]  bit_count;
    reg [7:0]  rx_shifter;
    reg [7:0]  tx_shifter;
    reg        miso_reg;
    reg        spi_active;
    
    // *** 新增: 用于锁存待写入 RX FIFO 的数据 ***
    reg [7:0]  rx_byte_to_fifo; 

    // MISO 输出逻辑
    assign spi_miso = (cs_reg) ? 1'bz : miso_reg; // CS 高时, MISO 高阻

    // FIFO 接口
    wire [7:0] tx_fifo_rdata;
    wire       tx_fifo_empty;
    reg        tx_fifo_rinc;
    wire [7:0] rx_fifo_rdata;
    wire       rx_fifo_empty;
    reg        rx_fifo_winc;
    wire       rx_fifo_full;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_count       <= 3'd0;
            rx_shifter      <= 8'h00;
            tx_shifter      <= 8'hFF; // 默认 MISO 输出
            miso_reg        <= 1'b1;
            spi_active      <= 1'b0;
            tx_fifo_rinc    <= 1'b0;
            rx_fifo_winc    <= 1'b0;
            rx_byte_to_fifo <= 8'h00; // 复位新增寄存器
        end else begin
            // 默认关闭脉冲
            tx_fifo_rinc <= 1'b0;
            rx_fifo_winc <= 1'b0;

            if (cs_falling) begin
                // --- SPI 事务开始 ---
                spi_active <= 1'b1;
                bit_count  <= 3'd0;
                // 从 TX FIFO 加载第一个字节
                if (!tx_fifo_empty) begin
                    tx_shifter <= tx_fifo_rdata;
                    tx_fifo_rinc <= 1'b1;
                end else begin
                    tx_shifter <= 8'hFF; // FIFO 为空, 发送 0xFF
                end
                
                // CPHA=1 模式下, 第一个 bit 在 CS 下降沿后立刻移出
                if (cfg_cpha == 1) begin
                    miso_reg <= tx_fifo_empty ? 1'b1 : tx_fifo_rdata[7];
                end

            end else if (cs_rising) begin
                // --- SPI 事务结束 ---
                spi_active <= 1'b0;
                bit_count  <= 3'd0;
                
            end else if (spi_active) begin
                
                // --- 采样边沿 (MOSI -> rx_shifter) ---
                if (sample_edge) begin
                    rx_shifter <= {rx_shifter[6:0], mosi_reg};
                    bit_count  <= bit_count + 1'b1;
                    
                    // *** 修改: 在第 8 个 bit 采样时锁存完整字节 ***
                    if (bit_count == 3'd7) begin
                        rx_byte_to_fifo <= {rx_shifter[6:0], mosi_reg}; // 锁存当前完整字节
                        // (rx_fifo_winc 将在下一个周期置位)
                    end
                end
                
                // --- 移出边沿 (tx_shifter -> MISO) ---
                if (shift_edge) begin
                    miso_reg   <= tx_shifter[7];
                    tx_shifter <= tx_shifter << 1;
                end

                // --- *** 修改: 在 bit_count=7 的 *下一个周期* 触发 FIFO 写 *** ---
                // (条件: 上一个周期 sample_edge 发生了, 且 bit_count 为 7)
                // (注意: 这里使用了 bit_count 的当前值, 它已经是 0 了)
                if (bit_count == 3'd0 && spi_active && sample_edge) begin 
                     // 推入 RX FIFO (如果 FIFO 不满)
                     if (!rx_fifo_full) begin
                         rx_fifo_winc <= 1'b1; // 使用上周期锁存的 rx_byte_to_fifo
                     end
                     // 从 TX FIFO 加载下一个字节 (如果 FIFO 非空)
                     if (!tx_fifo_empty) begin
                         tx_shifter <= tx_fifo_rdata;
                         tx_fifo_rinc <= 1'b1;
                     end else begin
                         tx_shifter <= 8'hFF;
                     end
                end
            end
        end
    end
    
//--------------------------------------------------------------------------
// 4. TX FIFO (用户 -> SPI)
//--------------------------------------------------------------------------
    sync_fifo #(
        .DATA_WIDTH ( 8 ),
        .ADDR_WIDTH ( FIFO_DEPTH_BITS )
    ) u_tx_fifo (
        .clk    ( clk ),
        .rst_n  ( rst_n ),
        // Write (User)
        .winc   ( user_tx_valid & ~tx_fifo_full ),
        .wdata  ( user_tx_data ),
        .wfull  ( tx_fifo_full ),
        // Read (SPI Core)
        .rinc   ( tx_fifo_rinc ),
        .rdata  ( tx_fifo_rdata ),
        .rempty ( tx_fifo_empty )
    );
    
//--------------------------------------------------------------------------
// 5. RX FIFO (SPI -> 用户)
//--------------------------------------------------------------------------
    sync_fifo #(
        .DATA_WIDTH ( 8 ),
        .ADDR_WIDTH ( FIFO_DEPTH_BITS )
    ) u_rx_fifo (
        .clk    ( clk ),
        .rst_n  ( rst_n ),
        // Write (SPI Core)
        .winc   ( rx_fifo_winc ),
        // *** 修改: 使用锁存的数据 ***
        .wdata  ( rx_byte_to_fifo ), 
        .wfull  ( rx_fifo_full ),
        // Read (User)
        .rinc   ( user_rx_pop & ~rx_fifo_empty ),
        .rdata  ( user_rx_data ),
        .rempty ( rx_fifo_empty )
    );
    
    // user_rx_valid 是电平信号 (只要 FIFO 非空)
    assign user_rx_valid = ~rx_fifo_empty;
    
endmodule