#ifndef __FPGA_REGISTERS_H__
#define __FPGA_REGISTERS_H__

#include <stdint.h>

// ============================================================================
// AHB2 外设基地址
// ============================================================================
#define FPGA_PERIPH_BASE 0x81000000U

// ============================================================================
// Section 1: 主模式选择寄存器
// ============================================================================
#define MODE_SELECT_REG        (*(volatile uint32_t*)(FPGA_PERIPH_BASE + 0x00))

// --- MODE_SELECT_REG (0x81000000) 值定义 ---
#define MODE_EXIT_TO_MAIN      (0x00)
#define MODE_WAVEFORM_OUTPUT   (0x01)
#define MODE_ANALOG_INPUT      (0x02)
#define MODE_DIGITAL_INPUT     (0x04) 
#define MODE_USB_CDC           (0x08)

// ============================================================================
// Section 2: 波形输出 (DDS) 相关寄存器
// ============================================================================
#define DDS_CONTROL_REG        (*(volatile uint32_t*)(FPGA_PERIPH_BASE + 0x04))

// --- DDS_CONTROL_REG (0x81000004) 位域定义 ---
// 波形类型 [2:0]
#define DDS_WAVE_TYPE_Pos      (0)
#define DDS_WAVE_TYPE_Msk      (0x7U << DDS_WAVE_TYPE_Pos)
enum {
    WAVE_TYPE_SINE,      // 000: 正弦波
    WAVE_TYPE_SQUARE,    // 001: 方波
    WAVE_TYPE_TRIANGLE,  // 010: 三角波
    WAVE_TYPE_COSINE,    // 011: 尖顶余弦波
    WAVE_TYPE_TRAPEZOID, // 100: 梯形波
    WAVE_TYPE_MAX = WAVE_TYPE_TRAPEZOID
};

// 频率选择 [5:3]
#define DDS_FREQ_SELECT_Pos    (3)
#define DDS_FREQ_SELECT_Msk    (0x7U << DDS_FREQ_SELECT_Pos)
enum {
    FREQ_1_25K,  // 000
    FREQ_12_5K,  // 001
    FREQ_62_5K,  // 010
    FREQ_125K,   // 011
    FREQ_625K,   // 100
    FREQ_1_25M,  // 101
    FREQ_12_5M,  // 110
    FREQ_MAX_CODE = FREQ_12_5M
};

// 幅值选择 [8:6]
#define DDS_AMP_SELECT_Pos     (6)
#define DDS_AMP_SELECT_Msk     (0x7U << DDS_AMP_SELECT_Pos)
enum {
    AMP_100_PERCENT,  // 000
    AMP_50_PERCENT,   // 001
    AMP_25_PERCENT,   // 010
    AMP_12_5_PERCENT, // 011
    AMP_MAX_CODE = AMP_12_5_PERCENT
};

// 占空比选择 [11:9]
#define DDS_DUTY_SELECT_Pos    (9)
#define DDS_DUTY_SELECT_Msk    (0x7U << DDS_DUTY_SELECT_Pos)
enum {
    DUTY_100_PERCENT, // 000 (实际可能无效,仅为占位)
    DUTY_75_PERCENT,  // 001
    DUTY_62_5_PERCENT,// 010
    DUTY_50_PERCENT,  // 011
    DUTY_37_5_PERCENT,// 100
    DUTY_25_PERCENT,  // 101
    DUTY_MAX_CODE = DUTY_25_PERCENT
};


// ============================================================================
// Section 3: 模拟信号输入相关寄存器 
// ============================================================================
#define ANALOG_CONTROL_REG     (*(volatile uint32_t*)(FPGA_PERIPH_BASE + 0x08))
#define ANALOG_STATUS_REG      (*(volatile uint32_t*)(FPGA_PERIPH_BASE + 0x0C))
#define ANALOG_DECIM_REG       (*(volatile uint32_t*)(FPGA_PERIPH_BASE + 0x28))
	
// ** 数据缓存区基地址，指针类型为 uint8_t* **
#define ANALOG_DATA_BUFFER     ((volatile uint8_t*)(FPGA_PERIPH_BASE + 0x100)) //512位数据

// --- ANALOG_CONTROL_REG (0x81000008) 写操作位定义 ---
#define ANALOG_CTRL_START_STOP_Pos (0)
#define ANALOG_CTRL_START_STOP_Msk (1U << ANALOG_CTRL_START_STOP_Pos) // bit 0: 1=Start, 0=Stop
#define ANALOG_CTRL_ACK_DATA_Pos   (1)
#define ANALOG_CTRL_ACK_DATA_Msk   (1U << ANALOG_CTRL_ACK_DATA_Pos)   // bit 1: M1写入1,通知FPGA数据已取走

// --- ANALOG_STATUS_REG (0x8100000C) 读操作位定义 ---
#define ANALOG_STATUS_DATA_READY_Pos (0)
#define ANALOG_STATUS_DATA_READY_Msk (1U << ANALOG_STATUS_DATA_READY_Pos) // bit 0: 1=数据准备就绪


// ============================================================================
// Section 4: 数字信号输入相关寄存器
// ============================================================================
#define DIGITAL_CONTROL_REG     (*(volatile uint32_t*)(FPGA_PERIPH_BASE + 0x10))
#define DIGITAL_STATUS_REG      (*(volatile uint32_t*)(FPGA_PERIPH_BASE + 0x14))
#define DIGITAL_PERIOD_REG      (*(volatile uint32_t*)(FPGA_PERIPH_BASE + 0x18))
#define DIGITAL_HIGH_TIME_REG   (*(volatile uint32_t*)(FPGA_PERIPH_BASE + 0x1C))

// --- DIGITAL_CONTROL_REG (0x81000010) ---
#define DIGITAL_CTRL_START_STOP_Pos (0)
#define DIGITAL_CTRL_START_STOP_Msk (1U << DIGITAL_CTRL_START_STOP_Pos)
#define DIGITAL_CTRL_ACK_Pos        (1)
#define DIGITAL_CTRL_ACK_Msk        (1U << DIGITAL_CTRL_ACK_Pos)

// --- DIGITAL_STATUS_REG (0x81000014) ---
#define DIGITAL_STATUS_READY_Pos    (0)
#define DIGITAL_STATUS_READY_Msk    (1U << DIGITAL_STATUS_READY_Pos)

// ========================================================================
// Section 5: 数字信号分析 (协议解析) 相关寄存器
// ========================================================================
#define DIGITAL_CAPTURE_CONTROL_REG (*(volatile uint32_t*)(FPGA_PERIPH_BASE + 0x20))
#define DIGITAL_CAPTURE_STATUS_REG  (*(volatile uint32_t*)(FPGA_PERIPH_BASE + 0x24))
#define DIGITAL_CAPTURE_BUFFER      ((volatile uint8_t*)(FPGA_PERIPH_BASE + 0x400)) 
// --- 位定义 ---
#define CAPTURE_CTRL_START_STOP_Pos (0)
#define CAPTURE_CTRL_ACK_Pos        (1)
#define CAPTURE_STATUS_READY_Pos    (0)
#define CAPTURE_STATUS_READY_Msk    (1U << CAPTURE_STATUS_READY_Pos)

// ========================================================================
// Section 7: USB CDC 模式相关寄存器
// ========================================================================
// ★ 新增：USB CDC 控制寄存器 ★
// (M1 只需操作 bit 0 即可)
#define USB_CDC_CONTROL_REG   (*(volatile uint32_t*)(FPGA_PERIPH_BASE + 0x2C))

// --- USB_CDC_CONTROL_REG (0x8100002C) 写操作位定义 ---
#define USB_CDC_CTRL_START_STOP_Pos (0)
#define USB_CDC_CTRL_START_STOP_Msk (1U << USB_CDC_CTRL_START_STOP_Pos) // bit 0: 1=Start, 0=Stop


#endif // __FPGA_REGISTERS_H__
