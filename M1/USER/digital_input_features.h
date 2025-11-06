#ifndef _DIGITAL_INPUT_FEATURES_H_
#define _DIGITAL_INPUT_FEATURES_H_

#include "PageDesign.h"

// ================== 标题 ==================
extern Button Digital_Title;

// ================== 模式切换按钮 ==================
extern Button Digital_Mode_Measure;
extern Button Digital_Mode_Analyze;

// ================== 参数显示区 ==================
extern Text Digital_Freq_Text ;
extern Text Digital_Duty_Text;
extern Text Digital_tHigh_Text ;
extern Text Digital_tLow_Text;

// ================== “分析模式”的结果显示区 ==================
extern Text Digital_Analyze_Result;

// ================== 按键区 ==================
extern Button Digital_Start;
extern Button Digital_Pause;
extern Button Digital_Reset;
extern Button Digital_Exit;
extern Button Freq_Select_Button; 
extern Button Encoding_Select_Button;

// ** 核心 1: 增加新的编码类型 **
typedef enum {
    ENCODE_NRZ_L,
    ENCODE_RZ,
    ENCODE_NRZ_I,
    ENCODE_MANCHESTER,
    ENCODE_DIFF_MANCHESTER, 
    ENCODE_UART,         
    ENCODE_TYPE_COUNT 
} EncodingType_t;

// ** 核心 2: 增加新的频率/波特率档位 **
#define FREQ_LEVELS 4
extern const char* FREQ_NAMES[FREQ_LEVELS];
extern const uint32_t FREQ_HZ[FREQ_LEVELS];

// ** 核心 3: 新增 UART 波特率档位 **
#define UART_BAUD_LEVELS 5
extern const char* UART_BAUD_NAMES[UART_BAUD_LEVELS];
extern const uint32_t UART_BAUD_RATES[UART_BAUD_LEVELS];

extern const char* ENCODING_NAMES[ENCODE_TYPE_COUNT];
extern Box_XY Digital_Display_Area;

#endif /* _DIGITAL_INPUT_FEATURES_H_ */
