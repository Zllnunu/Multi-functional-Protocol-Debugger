`timescale 1ns / 1ps
`include "address_map.vh" 

//
// 模块: can_wrapper.v (已修复地址转译 + 读/写功能)
// 描述: 1. 增加了 cfg_read 输入和 cfg_rdata 输出端口。
//       2. 增加了地址转译逻辑 (cfg_addr - `CAN_BASE_ADDR`)。
//       3. 将 cpu_cs 连接到 (cfg_write | cfg_read)。
//       4. 将 cpu_read 连接到 cfg_read (之前为 1'b0)。
//
module can_wrapper (
    input             clk,         // 50MHz system clock
    input             rst_n,

    // --- 内部配置总线 (来自 command_parser) ---
    input      [15:0] cfg_addr,     // (这是系统地址, e.g., 0x5008)
    input      [31:0] cfg_wdata,
    input             cfg_write,
    input             cfg_read,     // *** 新增: 读使能信号 ***
    output     [31:0] cfg_rdata,    // *** 新增: 读数据总线 ***
    output            cfg_ack,      // *** ACK 握手信号回传 ***

    // --- CAN物理接口 ---
    output            can_tx,
    input             can_rx,
    
    // --- 中断输出 (可选) ---
    output            irq
);
//================================================================
//== 1. canclk 分频器 (来自您的文件)
//================================================================
reg canclk_div;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        canclk_div <= 1'b0;
    end else begin
        canclk_div <= ~canclk_div;
    end
end

//================================================================
//== 2. MODIFIED: 地址转译与总线连接
//================================================================
    
wire [31:0]  ip_core_rdata;
wire         ip_core_ack;
wire         ip_core_err;
wire [31:0]  full_addr;
wire [15:0]  local_addr; // IP 核的本地地址 (e.g., 0x0008)

    // *** 修复: 从系统地址(cfg_addr)中减去基地址，得到本地地址 ***
    assign local_addr = cfg_addr - `CAN_BASE_ADDR;
    // *** 修复: 使用 local_addr 而不是 cfg_addr ***
    assign full_addr = {16'h0, local_addr};
    
    assign cfg_ack = ip_core_ack;
    assign cfg_rdata = ip_core_rdata; // *** 新增: 回传读数据 ***
    
//================================================================
//== 3. 例化Gowin CAN IP核 (来自您的文件)
//================================================================
CAN_Top u_can_core (
    .sysclk(clk),
    .canclk(canclk_div),
    .ponrst_n(rst_n),
    
    .cfgstrp_clkdiv(8'd31), // (来自您的文件)

    .cbus_rxd(can_rx),
    .cbus_txd(can_tx),
    
    .cpu_cs(cfg_write | cfg_read), // *** 修复: CS在读或写时均有效 ***
    .cpu_read(cfg_read),           // *** 修复: 连接到 cfg_read ***
    .cpu_write(cfg_write),
    .cpu_addr(full_addr),          // *** (现在传递的是正确的本地地址) ***
    .cpu_wdat(cfg_wdata),
    
    .cpu_rdat(ip_core_rdata),
    .cpu_ack(ip_core_ack),
    .cpu_err(ip_core_err),
    
    .int_o(irq)
);
endmodule