//------------------------------------------------------------------------------
//-- 模块基地址 (Module Base Addresses)
//------------------------------------------------------------------------------
`define PWM_BASE_ADDR        16'h1000   // PWM 控制器地址空间
`define SPI_BASE_ADDR        16'h2000   // SPI 主控制器地址空间
`define I2C_BASE_ADDR        16'h3000   // I2C 主控制器地址空间
`define UART_BASE_ADDR       16'h4000   // UART 控制器地址空间
`define CAN_BASE_ADDR        16'h5000   // CAN 控制器地址空间
`define SEQ_BASE_ADDR        16'h6000   // 序列发生器的基地址
//------------------------------------------------------------------------------
//-- 通道步长定义 (Channel Stride for Multi-Channel Modules)
//-- 定义每个通道占据的地址空间大小
//------------------------------------------------------------------------------
`define PWM_CHANNEL_STRIDE   16'h10     // 每个PWM通道占16字节
`define SPI_CHANNEL_STRIDE   16'h10     // 每个SPI通道占16字节
`define SEQ_CHANNEL_STRIDE   16'h0100
//------------------------------------------------------------------------------
//-- 模块内部寄存器偏移 (Register Offsets, 4-Byte Aligned)
//------------------------------------------------------------------------------
// 通用寄存器
`define REG_OFFSET_CTRL      16'h00     // 控制寄存器 (启动、停止、使能等)
`define REG_OFFSET_CONFIG    16'h04     // 配置寄存器 (模式、速率等)
`define REG_OFFSET_STATUS    16'h08     // 状态寄存器
`define REG_OFFSET_DATA      16'h0C     // 数据寄存器 (可作为TX/RX FIFO的访问端口)

// PWM 专用寄存器
`define PWM_REG_OFFSET_PERIOD    16'h04     // 周期寄存器 (复用CONFIG)
`define PWM_REG_OFFSET_DUTY      16'h08     // 占空比寄存器 (复用STATUS)

// SPI 专用寄存器
`define SPI_REG_OFFSET_CTRL      16'h00     // 写: bit0=start, bit[7:4]=cs, bit[15:8]=len
`define SPI_REG_OFFSET_CONFIG    16'h04     // 写: bit[31:8]=speed_divisor, bit[1:0]=mode
`define SPI_REG_OFFSET_TX_DATA   16'h08     // 写: 发送数据到TX FIFO
`define SPI_REG_OFFSET_RX_DATA   16'h0C     // 读: 从RX FIFO读取数据
`define SPI_REG_OFFSET_STATUS    16'h10     // 读: bit0=busy, bit[9:8]=rx_fifo_level

// I2C 专用寄存器
`define I2C_REG_OFFSET_CTRL      16'h00     // 写: bit0=start, bit[7:1]=slave_addr
`define I2C_REG_OFFSET_CONFIG    16'h04     // 写: bit[31:0]=speed_divisor
`define I2C_REG_OFFSET_LEN       16'h08     // 写: bit[15:8]=wlen, bit[7:0]=rlen
`define I2C_REG_OFFSET_TX_DATA0  16'h0C     // 写: 发送数据到TX FIFO, 低32位
`define I2C_REG_OFFSET_TX_DATA1  16'h10     // 写: 发送数据到TX FIFO, 高32位
`define I2C_REG_OFFSET_RX_DATA   16'h14     // 读: 从RX FIFO读取数据 (地址已调整)
`define I2C_REG_OFFSET_STATUS    16'h18     // 读: bit0=busy/ack_error (地址已调整)

// UART 专用寄存器
`define UART_REG_OFFSET_CONFIG   16'h00     // 写: {baud_divisor, bits, parity, stop}
`define UART_REG_OFFSET_TX_DATA  16'h04     // 写: 发送数据到TX FIFO
`define UART_REG_OFFSET_RX_DATA  16'h08     // 读: 从RX FIFO读取数据
`define UART_REG_OFFSET_STATUS   16'h0C     // 读: tx_fifo_full, rx_fifo_empty

// CAN 专用寄存器
`define CAN_REG_OFFSET_CONFIG    16'h00     // 写: bitrate_config
`define CAN_REG_OFFSET_MSG_ID    16'h04     // 写: {id, ext, rtr, dlc}
`define CAN_REG_OFFSET_DATA0     16'h08     // 写: data[31:0]
`define CAN_REG_OFFSET_DATA1     16'h0C     // 写: data[63:32]
`define CAN_REG_OFFSET_CTRL      16'h10     // 写: bit0=transmit_req
`define CAN_REG_OFFSET_STATUS    16'h14     // 读: status

// --- SEQ (序列发生器) 专用寄存器 ---
// DATA Registers (256 bits = 8 * 32-bit writes)
`define SEQ_REG_OFFSET_DATA0 16'h00
`define SEQ_REG_OFFSET_DATA1 16'h04
`define SEQ_REG_OFFSET_DATA2 16'h08
`define SEQ_REG_OFFSET_DATA3 16'h0C
`define SEQ_REG_OFFSET_DATA4 16'h10
`define SEQ_REG_OFFSET_DATA5 16'h14
`define SEQ_REG_OFFSET_DATA6 16'h18
`define SEQ_REG_OFFSET_DATA7 16'h1C

// CONFIG 寄存器
// ** MODIFIED START ** 
// [24]: loop_enable
// [23:8]: (RESERVED) - Divisor 移至 0x28
// [7:0]: sequence_len (假设ADDR_WIDTH=8)
`define SEQ_REG_OFFSET_CONFIG 16'h20
`define SEQ_REG_OFFSET_CTRL   16'h24     // 控制寄存器: [0]=arm
// 新增：为32位分频器分配独立地址
`define SEQ_REG_OFFSET_DIVISOR 16'h28    // 32-bit clock divisor
// ** MODIFIED END **

// Global Control Register for SEQ module
`define SEQ_GLOBAL_CTRL_ADDR 16'h6F00 // [0]: sync_go