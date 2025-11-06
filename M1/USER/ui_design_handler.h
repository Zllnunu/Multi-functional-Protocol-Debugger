#ifndef __UI_DESIGN_HANDLER_H__
#define __UI_DESIGN_HANDLER_H__

#include "PageDesign.h"
#include <stdint.h>
#include "digital_input_features.h" 


// ============================================================================
//  (所有 Section 1 和 2 的声明都无修改)
// ============================================================================
void Display_Main_board(void);
void Display_Wave_out(void);
void Display_Analog_in(void);
void Display_Digital_in(void);
void Display_USB_CDC(void);

void Update_Waveform_Display(uint32_t wave_type, uint32_t freq_code, uint32_t amp_code, uint32_t duty_code);
void Draw_Waveform_Preview(uint32_t wave_type);
void Update_Analog_Display(uint16_t v_div_mv, uint32_t time_div_us);
void Draw_Scope_Grid(Box_XY board);
void Draw_Scope_Waveform(uint8_t* buffer, int points, Box_XY board, uint16_t volts_per_div_mv);
void Update_Digital_Display(uint32_t frequency, uint32_t duty, uint32_t t_high, uint32_t t_low);
void Display_Digital_in_MeasureMode(void);
void Display_Digital_in_AnalyzeMode(void);


void Display_Loading_Screen(const char* module_name);
void mcu_sw_delay_ms(volatile uint32_t ms);
// ============================================================================
// --- Section 3: 分析函数 ---
// ============================================================================

typedef struct {
    uint32_t sample_rate_hz;    
    uint32_t bit_width;         
    uint32_t baud_rate_est;     
    char     encoding_type[32]; 
    uint8_t  decoded_bytes[16]; // ** 用于 UART 字节 **
    uint8_t  decoded_bits[24];  // ** 用于 01 码流 **
    uint8_t  num_bits_decoded;  
    uint8_t  is_uart_data;      
} SignalAnalysisResult_t;


// ** 核心 2: 更新函数原型 **
void Analyze_and_Display_Signal(
    uint8_t* buffer, 
    int points, 
    uint8_t freq_code, 
    uint8_t baud_code,      
    EncodingType_t encoding
);
void Display_Analyze_Results(SignalAnalysisResult_t* result);

#endif // __UI_DESIGN_HANDLER_H__