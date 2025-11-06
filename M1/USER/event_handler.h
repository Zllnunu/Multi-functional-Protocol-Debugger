#ifndef __EVENT_HANDLER_H__
#define __EVENT_HANDLER_H__

#include "main.h"

// ============================================================================
//  本文件声明了所有事件处理函数，并定义了跨模块共享的配置。
// ============================================================================

// --- 1. 公共配置定义 ---
#define WAVEFORM_POINTS 512
#define ADC_FSR_MV 3300 // ADC满量程电压，单位: 毫伏(mV)

// --- 2. 声明事件处理函数 ---
void Handle_Main_Page(void);
void Handle_Wave_Out_Page(void);
void Handle_Analog_In_Page(void);
void Handle_Digital_In_Page(void);
void Handle_USB_CDC_Page(void);

// --- 3. 声明档位数组 (使用整数，单位: 毫伏) ---
extern const uint16_t v_div_options_mv[];
extern const uint32_t time_div_options_us[];
#define V_DIV_LEVELS (sizeof(v_div_options_mv)/sizeof(uint16_t))
#define TIME_DIV_LEVELS (sizeof(time_div_options_us)/sizeof(uint16_t))

//  定义数字输入功能的子模式
typedef enum {
    DIGITAL_MODE_MEASURE, // 测量模式
    DIGITAL_MODE_ANALYZE  // 分析模式
} DigitalMode_t;



#endif // __EVENT_HANDLER_H__

