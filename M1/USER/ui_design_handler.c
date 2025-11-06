#include "ui_design_handler.h"
#include "MCU_LCD.h"
#include "fpga_registers.h"
#include "event_handler.h"
#include <stdio.h>
#include <string.h> // 包含 string.h 用于 memset

// 引入所有UI元素的定义
#include "Create_Features.h"
#include "wave_output_features.h"
#include "analog_input_features.h"
#include "digital_input_features.h"
#include "usb_cdc_features.h"

// ============================================================================
//  本文件实现了所有与UI界面绘制、更新相关的函数。
// ============================================================================

// --- Section 0:  底层绘图辅助函数 ---
// Cohen-Sutherland 裁剪算法的区域码
#define INSIDE 0 // 0000
#define LEFT   1 // 0001
#define RIGHT  2 // 0010
#define BOTTOM 4 // 0100
#define TOP    8 // 1000

// 计算一个点的区域码
static int compute_outcode(int x, int y, Box_XY clip_box) {
    int code = INSIDE;
    if (x < clip_box.X1) code |= LEFT;
    else if (x > clip_box.X1 + clip_box.Width - 1) code |= RIGHT;
    if (y < clip_box.Y1) code |= TOP;
    else if (y > clip_box.Y1 + clip_box.Height - 1) code |= BOTTOM;
    return code;
}

// 带有 Cohen-Sutherland 裁剪算法的画线函数
static void lcd_draw_clipped_line(int x0, int y0, int x1, int y1, uint32_t color, Box_XY clip_box) {
    int outcode0 = compute_outcode(x0, y0, clip_box);
    int outcode1 = compute_outcode(x1, y1, clip_box);
    int accept = 0;

    while (1) {
        if (!(outcode0 | outcode1)) { // 两个点都在内部，直接接受
            accept = 1;
            break;
        } else if (outcode0 & outcode1) { // 两个点都在同一个外部区域，直接拒绝
            break;
        } else {
            // 需要裁剪
            int x, y;
            int outcode_out = outcode0 ? outcode0 : outcode1;
            
            if (outcode_out & TOP) {
                x = x0 + (x1 - x0) * (clip_box.Y1 - y0) / (y1 - y0);
                y = clip_box.Y1;
            } else if (outcode_out & BOTTOM) {
                x = x0 + (x1 - x0) * (clip_box.Y1 + clip_box.Height - 1 - y0) / (y1 - y0);
                y = clip_box.Y1 + clip_box.Height - 1;
            } else if (outcode_out & RIGHT) {
                y = y0 + (y1 - y0) * (clip_box.X1 + clip_box.Width - 1 - x0) / (x1 - x0);
                x = clip_box.X1 + clip_box.Width - 1;
            } else { // LEFT
                y = y0 + (y1 - y0) * (clip_box.X1 - x0) / (x1 - x0);
                x = clip_box.X1;
            }

            if (outcode_out == outcode0) {
                x0 = x; y0 = y; outcode0 = compute_outcode(x0, y0, clip_box);
            } else {
                x1 = x; y1 = y; outcode1 = compute_outcode(x1, y1, clip_box);
            }
        }
    }
    if (accept) {
        lcd_draw_line(x0, y0, x1, y1, color);
    }
}




// --- Section 1: 页面级绘制函数 ---
void Display_Main_board(void)
{
    lcd_clear(UI_BLUE_ALICE);
	Draw_Normal_Button(Wave_Generate);
	Draw_Normal_Button(Analog_Input);
	Draw_Normal_Button(Digital_Input);
	Draw_Normal_Button(USB_CDC);
}

void Display_Wave_out(void)
{
    lcd_clear(UI_BLUE_ALICE);
    Draw_Normal_Button(Wave_Switch);    
    Draw_Normal_Button(Output_Start);
    Draw_Button_Effect(Output_Stop); // 初始状态是停止，所以Stop有特效

    Draw_Normal_Button(Voltage_up);
    Draw_Normal_Button(Voltage_down);
    Draw_Normal_Button(Frequency_up);
    Draw_Normal_Button(Frequency_down);
    Draw_Normal_Button(PWM_up);
    Draw_Normal_Button(PWM_down);
    Draw_Normal_Button(Out_Exit);
    Draw_Box(Wave_Out_Board, LCD_BLACK, -1);
    Draw_Text_Boundary(Crruent_Volt,"V:");
    Draw_Text_Boundary(Crruent_Freq," F:");
    Draw_Text_Boundary(Crruent_Duty," Duty:");
    
    /* 首次进入界面时，调用更新函数来绘制所有初始状态 */
    Update_Waveform_Display(WAVE_TYPE_SINE, FREQ_1_25K, AMP_100_PERCENT, DUTY_50_PERCENT);
}

void Display_Analog_in(void)
{	
    lcd_clear(LCD_WHITE); 
	Draw_Normal_Button(Analog_Title);	
	Draw_Text_Boundary(Analog_Volt_Text, " V/Div: ---");
	Draw_Text_Boundary(Analog_Freq_Text, " Freq: ---");
	Draw_Text_Boundary(Analog_Sample_Text, " Sample: ---");
	Draw_Normal_Button(Analog_V_up);
	Draw_Normal_Button(Analog_V_down);
	Draw_Normal_Button(Analog_Freq_up);
	Draw_Normal_Button(Analog_Freq_down);	
	Draw_Normal_Button(Analog_Start);
    Draw_Button_Effect(Analog_Stop);
	Draw_Normal_Button(Analog_Reset);
	Draw_Normal_Button(Analog_Exit);
	Draw_Scope_Grid(Analog_WaveBoard);
	// ** 新增: 调用更新函数来显示所有初始参数 **
    // (初始索引: v_div=3 -> 1000mV; time_div=2 -> 50us)
    Update_Analog_Display(1000, 50); 
}

void Display_Digital_in(void)
{	
    lcd_clear(UI_BLUE_ALICE); 
	Draw_Normal_Button(Digital_Title);
	
    // 绘制所有通用的控制按钮
	Draw_Normal_Button(Digital_Start);
	Draw_Button_Effect(Digital_Pause); // ** 修正: 默认是暂停状态 **
	Draw_Normal_Button(Digital_Reset);
	Draw_Normal_Button(Digital_Exit);
  
	
   // **核心修正: 进入页面时，强制清理硬件控制寄存器，确保初始状态正确**
    DIGITAL_CONTROL_REG = 0;
    DIGITAL_CAPTURE_CONTROL_REG = 0;  
    // 绘制左侧显示区的边框
    Draw_Box(Digital_Display_Area, LCD_BLACK, -1);

    // 默认进入“测量模式”
    Display_Digital_in_MeasureMode();
}



// --- Section 2: 波形输出界面相关函数 ---
// ---  用于将参数编码映射为字符串的查找表 ---
static const char* freq_map[] = {"1.25k", "12.5k", "62.5k", "125k", "625k", "1.25M", "6.25M", "N/A"};
static const char* amp_map[]  = {"100%", "50%", "25%", "12.5%", "N/A", "N/A", "N/A", "N/A"};
static const char* duty_map[] = {"100%", "75%", "62.5%", "50%", "37.5%", "25%", "N/A", "N/A"};

// 用于 main.c 的全局字符串缓冲区
extern char display_str_buffer[64];

/* 更新波形输出UI的所有动态显示内容 */
void Update_Waveform_Display(uint32_t wave_type, uint32_t freq_code, uint32_t amp_code, uint32_t duty_code)
{
    // --- 1. 更新波形名称 ---
    char* wave_str = "Sine";
    switch(wave_type) {
        case WAVE_TYPE_SQUARE:    wave_str = "Square";    break;
        case WAVE_TYPE_TRIANGLE:  wave_str = "Triangle";  break;
        case WAVE_TYPE_COSINE:    wave_str = "Spire Cos";   break;
        case WAVE_TYPE_TRAPEZOID: wave_str = "Trapezoid"; break;
    }
    sprintf(display_str_buffer, "**%s**", wave_str);
    Draw_Text_Boundary(Crruent_Waveform, display_str_buffer);
    
    // --- 2. 更新波形预览图 ---
    Draw_Waveform_Preview(wave_type);

    // --- 3. 更新参数显示 ---
    // 更新频率
    sprintf(display_str_buffer, " F:%s", freq_map[freq_code]);
    Draw_Text_Boundary(Crruent_Freq, display_str_buffer);
    
    // 更新电压 (幅值)
    sprintf(display_str_buffer, " V:%s", amp_map[amp_code]);
    Draw_Text_Boundary(Crruent_Volt, display_str_buffer);
    
    // 更新占空比 (仅方波和三角波有效)
    if (wave_type == WAVE_TYPE_SQUARE || wave_type == WAVE_TYPE_TRIANGLE) {
        sprintf(display_str_buffer, " Duty:%s", duty_map[duty_code]);
    } else {
        sprintf(display_str_buffer, " Duty:N/A");
    }
    Draw_Text_Boundary(Crruent_Duty, display_str_buffer);
}

#define SINE_TABLE_SIZE 64
static const int8_t sine_lookup_table[SINE_TABLE_SIZE] = {
      0,  12,  25,  37,  49,  60,  71,  81,
     90,  98, 106, 112, 117, 122, 125, 127,
    127, 125, 122, 117, 112, 106,  98,  90,
     81,  71,  60,  49,  37,  25,  12,   0,
    -12, -25, -37, -49, -60, -71, -81, -90,
    -98,-106,-112,-117,-122,-125,-127,-127,
   -125,-122,-117,-112,-106, -98, -90, -81,
    -71, -60, -49, -37, -25, -12
};


/* 在指定的预览区内绘制静态的波形示意图 */
void Draw_Waveform_Preview(uint32_t wave_type)
{
    // 定义预览区域的坐标和尺寸
    uint16_t x = Wave_Out_Board.X1;
    uint16_t y = Wave_Out_Board.Y1;
    uint16_t w = Wave_Out_Board.Width;
    uint16_t h = Wave_Out_Board.Height;
    uint16_t center_y = y + h / 2;
    
    // 1. 清空预览区并画一条中心线
    lcd_fill(x + 1, y + 1, x + w - 2, y + h - 2, LCD_WHITE);
    lcd_draw_line(x, center_y, x + w - 1, center_y, UI_GRAY_LIGHT);

    // 2. 根据波形类型绘制预览图
    switch(wave_type)
    {
        case WAVE_TYPE_SINE:
        {
            // ** 使用查表法绘制，无浮点运算 **
            uint16_t last_px = 0, last_py = 0;
            int16_t amplitude = (h / 2) * 0.8; // 振幅为区域高度的80%
            
            for(int i = 0; i < w; i++)
            {
                // 计算在表中查找的位置 (为了显示两个周期，我们将索引乘以2)
                uint32_t table_index = (i * SINE_TABLE_SIZE * 2) / w;
                // 从表中获取归一化的值 (-127 to 127)
                int8_t table_value = sine_lookup_table[table_index % SINE_TABLE_SIZE];
                // 使用整数乘法和除法将其缩放到屏幕坐标
                int16_t scaled_y = (table_value * amplitude) / 127;
                uint16_t py = center_y - scaled_y;

                if (i > 0) {
                    lcd_draw_line(x + last_px, last_py, x + i, py, UI_BLUE_ROYAL);
                }
                last_px = i;
                last_py = py;
            }
            break;
        }
        case WAVE_TYPE_SQUARE:
        {
            uint16_t amp = h * 0.4;
            lcd_draw_line(x,           center_y,      x + w/4,     center_y,      UI_BLUE_ROYAL);
            lcd_draw_line(x + w/4,     center_y,      x + w/4,     center_y-amp,  UI_BLUE_ROYAL);
            lcd_draw_line(x + w/4,     center_y-amp,  x + w*3/4,   center_y-amp,  UI_BLUE_ROYAL);
            lcd_draw_line(x + w*3/4,   center_y-amp,  x + w*3/4,   center_y,      UI_BLUE_ROYAL);
            lcd_draw_line(x + w*3/4,   center_y,      x + w,       center_y,      UI_BLUE_ROYAL);
            break;
        }
        case WAVE_TYPE_TRIANGLE:
        {
            uint16_t amp = h * 0.4;
            lcd_draw_line(x,           center_y,      x + w/4,     center_y-amp, UI_BLUE_ROYAL);
            lcd_draw_line(x + w/4,     center_y-amp,  x + w*3/4,   center_y+amp, UI_BLUE_ROYAL);
            lcd_draw_line(x + w*3/4,   center_y+amp,  x + w,       center_y,     UI_BLUE_ROYAL);
            break;
        }
        case WAVE_TYPE_COSINE: // 尖顶余弦波 (用 |sin(x)| 示意)
        {
            uint16_t last_px = 0, last_py = center_y;
            int16_t amplitude = (h / 2) * 0.8; // 振幅为区域半高的80%         
            for(int i = 0; i < w; i++)
            {
                // 计算在表中查找的位置 (为了显示4个波峰，我们将索引乘以4)
                uint32_t table_index = (i * SINE_TABLE_SIZE * 4) / w;
                int8_t table_value = sine_lookup_table[table_index % SINE_TABLE_SIZE];
                table_value = (table_value < 0) ? -table_value : table_value;
                int16_t scaled_y = (table_value * amplitude) / 127;
                uint16_t py = center_y - scaled_y; // Y坐标总是在中心线之上
                if (i > 0) {
                    lcd_draw_line(x + last_px, last_py, x + i, py, UI_BLUE_ROYAL);
                }
                last_px = i;
                last_py = py;
            }
            break;
        }
        case WAVE_TYPE_TRAPEZOID: // 梯形波
        {
            uint16_t amp = h * 0.4;
            lcd_draw_line(x,           center_y,      x + w/8,     center_y-amp, UI_BLUE_ROYAL);
            lcd_draw_line(x + w/8,     center_y-amp,  x + w*3/8,   center_y-amp, UI_BLUE_ROYAL);
            lcd_draw_line(x + w*3/8,   center_y-amp,  x + w/2,     center_y,     UI_BLUE_ROYAL);
            lcd_draw_line(x + w/2,     center_y,      x + w*5/8,   center_y+amp, UI_BLUE_ROYAL);
            lcd_draw_line(x + w*5/8,   center_y+amp,  x + w*7/8,   center_y+amp, UI_BLUE_ROYAL);
            lcd_draw_line(x + w*7/8,   center_y+amp,  x + w,       center_y,     UI_BLUE_ROYAL);
            break;
        }
    }
}


// --- Section 3: 模拟输入界面相关函数 ---
// ... (此部分无修改) ...
// ** 绘制示波器网格的函数 **
void Draw_Scope_Grid(Box_XY board)
{
    // 1. 填充黑色背景
    lcd_fill(board.X1, board.Y1, board.X1 + board.Width - 1, board.Y1 + board.Height - 1, LCD_BLACK);

    uint16_t x_start = board.X1;
    uint16_t y_start = board.Y1;
    uint16_t x_end = board.X1 + board.Width - 1;
    uint16_t y_end = board.Y1 + board.Height - 1;

    // 2. 绘制网格线 (10x8)
    uint16_t x_step = board.Width / 10;
    uint16_t y_step = board.Height / 8;

    // 绘制垂直线
    for (int i = 1; i < 10; i++) {
        uint16_t x = x_start + i * x_step;
        // 中心线使用较亮的灰色
        uint32_t color = (i == 5) ? UI_GRAY_MEDIUM : UI_GRAY_DARK;
        lcd_draw_line(x, y_start, x, y_end, color);
    }
    // 绘制水平线
    for (int i = 1; i < 8; i++) {
        uint16_t y = y_start + i * y_step;
        // 中心线使用较亮的灰色
        uint32_t color = (i == 4) ? UI_GRAY_MEDIUM : UI_GRAY_DARK;
        lcd_draw_line(x_start, y, x_end, y, color);
    }
}


// ** 已重写: Draw_Scope_Waveform 函数以使用线段裁剪 **
void Draw_Scope_Waveform(uint8_t* buffer, int points, Box_XY board, uint16_t volts_per_div_mv)
{
    if (points <= 1) return;

    const int32_t VOLTS_PER_SCREEN_MV = (int32_t)volts_per_div_mv * 8;
    const int32_t y_center = board.Y1 + board.Height / 2;
    const int32_t y_half_height = board.Height / 2;

    for (int i = 0; i < (points - 1); i++)
    {
        // --- 计算线段起点 (Point A) ---
        // 使用 int 类型以匹配裁剪函数
        int pA_sx = board.X1 + (long)(i * (board.Width - 1)) / (points - 1);
        int32_t voltage_mv_A = (((int32_t)buffer[i] - 128) * ADC_FSR_MV) / 128;
        // 计算Y坐标，此时它可能超出屏幕范围
        int pA_sy = y_center - (long)(voltage_mv_A * y_half_height) / (VOLTS_PER_SCREEN_MV / 2);

        // --- 计算线段终点 (Point B) ---
        int pB_sx = board.X1 + (long)((i + 1) * (board.Width - 1)) / (points - 1);
        int32_t voltage_mv_B = (((int32_t)buffer[i+1] - 128) * ADC_FSR_MV) / 128;
        int pB_sy = y_center - (long)(voltage_mv_B * y_half_height) / (VOLTS_PER_SCREEN_MV / 2);

        // --- ** 核心修正: 使用带裁剪的画线函数 ** ---
        // 移除旧的边界检查，将原始坐标和裁剪框交给新函数处理
        lcd_draw_clipped_line(pA_sx, pA_sy, pB_sx, pB_sy, BTN_GREEN_LIME, board);
    }
}




void Update_Analog_Display(uint16_t v_div_mv, uint32_t time_div_us)
{
    // --- 更新 V/Div 显示 ---
    if (v_div_mv >= 1000) {
        sprintf(display_str_buffer, " V/Div: %uV", v_div_mv / 1000);
    } else {
        sprintf(display_str_buffer, " V/Div: %umV", v_div_mv);
    }
    Draw_Text_Boundary(Analog_Volt_Text, display_str_buffer);
    
    // --- ★ 修改：更新 Time/Div 显示 (增加 ms 单位) ★ ---
    if (time_div_us >= 1000) { // 大于等于 1ms (1000us)
        sprintf(display_str_buffer, " T/Div: %lums", time_div_us / 1000);
    } else {
        sprintf(display_str_buffer, " T/Div: %luus", time_div_us);
    }
    Draw_Text_Boundary(Analog_Freq_Text, display_str_buffer);
    
    // --- 更新采样点数显示 (固定值) ---
    sprintf(display_str_buffer, " Sample: %d", WAVEFORM_POINTS);
    Draw_Text_Boundary(Analog_Sample_Text, display_str_buffer);
}

// --- Section 4: 数字输入界面相关函数 ---
void Update_Digital_Display(uint32_t frequency, uint32_t duty, uint32_t t_high_ns, uint32_t t_low_ns)
{
    // ... (此部分无修改) ...
    // 更新频率
    if (frequency > 1000000) { // MHz
        sprintf(display_str_buffer, "Freq: %lu.%03lu MHz", frequency / 1000000, (frequency % 1000000) / 1000);
    } else if (frequency > 1000) { // kHz
        sprintf(display_str_buffer, "Freq: %lu.%03lu kHz", frequency / 1000, frequency % 1000);
    } else { // Hz
        sprintf(display_str_buffer, "Freq: %lu Hz", frequency);
    }
    Draw_Text_Boundary(Digital_Freq_Text, display_str_buffer);
    
    // 更新占空比
    sprintf(display_str_buffer, "Duty: %lu %%", duty);
    Draw_Text_Boundary(Digital_Duty_Text, display_str_buffer);

    // 更新高电平时间
    if (t_high_ns > 1000) { // us
        sprintf(display_str_buffer, "T_high: %lu.%03lu us", t_high_ns / 1000, t_high_ns % 1000);
    } else { // ns
        sprintf(display_str_buffer, "T_high: %lu ns", t_high_ns);
    }
    Draw_Text_Boundary(Digital_tHigh_Text, display_str_buffer);

    // 更新低电平时间
    if (t_low_ns > 1000) { // us
        sprintf(display_str_buffer, "T_low: %lu.%03lu us", t_low_ns / 1000, t_low_ns % 1000);
    } else { // ns
        sprintf(display_str_buffer, "T_low: %lu ns", t_low_ns);
    }
    Draw_Text_Boundary(Digital_tLow_Text, display_str_buffer);
}



// --- Section 4: 数字输入界面（拓展部分）相关函数 ---
void Display_Digital_in_MeasureMode(void)
{
    Draw_Button_Effect(Digital_Mode_Measure);
    Draw_Normal_Button(Digital_Mode_Analyze);
    // 绘制测量模式下的所有参数框
	Draw_Text_Boundary(Digital_Freq_Text,"Freq:");
	Draw_Text_Boundary(Digital_Duty_Text,"Duty:");
	Draw_Text_Boundary(Digital_tHigh_Text,"T_high:");
	Draw_Text_Boundary(Digital_tLow_Text,"T_low:");
    // **新增**: 擦除频率选择按钮区域
    Fill_Box(Freq_Select_Button.Box, UI_BLUE_ALICE, 0);
}

void Display_Digital_in_AnalyzeMode(void)
{
    Draw_Normal_Button(Digital_Mode_Measure);
    Draw_Button_Effect(Digital_Mode_Analyze);
    
    // ** 核心 1: 更新绘制逻辑 **
    sprintf(Encoding_Select_Button.Text[0], "%s", ENCODING_NAMES[ENCODE_NRZ_L]);
    Draw_Normal_Button(Encoding_Select_Button);
    // (使用新的频率列表)
    sprintf(Freq_Select_Button.Text[0], "%s", FREQ_NAMES[1]); // 默认 50kHz (索引 1)
    Draw_Normal_Button(Freq_Select_Button);
    
    Draw_Text_Boundary(Digital_Analyze_Result, " Ready to analyze...");
}


// ============================================================================
// --- Section 6: 核心分析算法与显示 (框架重构) ---
// ============================================================================

// 采样率
#define SAMPLE_RATE_HZ 1000000 
// 最大解码 bit 数
#define MAX_DECODED_BITS 24 

/**
 * @brief (内部函数) 在LCD上显示分析结果 
 */
void Display_Analyze_Results(SignalAnalysisResult_t* result)
{
    Fill_Box(Digital_Analyze_Result.Box, Digital_Analyze_Result.BackColor, 0);
    Draw_Box(Digital_Analyze_Result.Box, LCD_BLACK, 0);
    brush_color = Digital_Analyze_Result.TextColor;
    back_color = Digital_Analyze_Result.BackColor;
    uint16_t x = Digital_Analyze_Result.Box.X1 + 10;
    uint16_t y = Digital_Analyze_Result.Box.Y1 + 10;
    uint16_t w = Digital_Analyze_Result.Box.Width - 20;
    uint8_t  h = Digital_Analyze_Result.TextSize + 4;

    sprintf(display_str_buffer, "Encoding: %s", result->encoding_type);
    lcd_show_string(x, y, w, h+2, display_str_buffer, h);
    y += h + 5;
    sprintf(display_str_buffer, "Baud Rate: %lu bps", result->baud_rate_est);
    lcd_show_string(x, y, w, h+2, display_str_buffer, h);
    y += h + 5;
    sprintf(display_str_buffer, "1-Bit Width: %lu samples", result->bit_width);
    lcd_show_string(x, y, w, h+2, display_str_buffer, h);
    y += h + 10; 

    char* p = display_str_buffer;
    
    // ** (A) 如果是 UART, 显示 0x... 字节 **
    if (result->is_uart_data) {
        p += sprintf(p, "Decoded: ");
        uint8_t num_bytes = result->num_bits_decoded / 8;
        if (num_bytes > 8) num_bytes = 8; // 最多显示 8 字节
        
        for(int i = 0; i < num_bytes; i++) {
             // 检查缓冲区是否会溢出
            if ((p - display_str_buffer) > 58) break; 
            p += sprintf(p, "0x%02X ", result->decoded_bytes[i]);
        }
        *p = '\0'; 
        lcd_show_string(x, y, w, h+2, display_str_buffer, h);
        y += h + 5;
    } 
    // ** (B) 否则, 显示 01 码流 **
    else {
        p += sprintf(p, "Decoded: ");
        for(int i = 0; i < result->num_bits_decoded; i++) {
             // 检查缓冲区是否会溢出
            if ((p - display_str_buffer) > 60) break;
            *p++ = (result->decoded_bits[i] ? '1' : '0');
            if ((i + 1) % 8 == 0 && i < result->num_bits_decoded - 1) {
                *p++ = ' '; 
            }
        }
        *p = '\0'; 
        lcd_show_string(x, y, w, h+2, display_str_buffer, h);
        y += h + 5;
    }
    
    // --- ASCII 显示 (仅 UART) ---
    if (result->is_uart_data) {
        p = display_str_buffer;
        p += sprintf(p, "ASCII: ");
        uint8_t num_bytes = result->num_bits_decoded / 8;
        if (num_bytes > 8) num_bytes = 8;
        
        for(int i = 0; i < num_bytes; i++) {
            if ((p - display_str_buffer) > 62) break;
            uint8_t c = result->decoded_bytes[i];
            if (c >= 0x20 && c <= 0x7E) {
                *p++ = (char)c;
            } else {
                *p++ = '.'; 
            }
        }
        *p = '\0';
        lcd_show_string(x, y, w, h+2, display_str_buffer, h);
    }
}


// ============================================================================
// --- Section 7: 编码器子函数 (无修改) ---
// ============================================================================

// 1. NRZ-L
static int decode_nrz_l(SignalAnalysisResult_t* res, uint8_t* buf, int pts, int edge_idx, uint32_t bw)
{
    strcpy(res->encoding_type, "NRZ-L");
    int sample_idx = -1;
    
    if (edge_idx != -1) {
        sample_idx = edge_idx - (bw / 2);
        if (sample_idx < 0) sample_idx = edge_idx + (bw / 2);
    } else {
        sample_idx = bw / 2;
    }

    int num_bits = 0;
    while(num_bits < MAX_DECODED_BITS && sample_idx < pts) 
    {
        uint8_t bit = buf[sample_idx];
        res->decoded_bits[num_bits] = bit;
        
        int byte_idx = num_bits / 8;
        int bit_in_byte = 7 - (num_bits % 8);
        if (bit) res->decoded_bytes[byte_idx] |= (1 << bit_in_byte);
        
        num_bits++;
        sample_idx += bw;
    }
    res->num_bits_decoded = num_bits;
    return 1;
}

// 2. RZ
static int decode_rz(SignalAnalysisResult_t* res, uint8_t* buf, int pts, int edge_idx, uint32_t bw)
{
    strcpy(res->encoding_type, "RZ");
    int sample_idx = -1;
    
    if (edge_idx != -1) {
        sample_idx = edge_idx - (bw / 2);
        if (sample_idx < 0) sample_idx = edge_idx + (bw / 2);
    } else {
        sample_idx = bw / 2;
    }

    uint32_t sp1_offset = bw / 4; 
    uint32_t sp2_offset = (bw * 3) / 4; 

    int num_bits = 0;
    while(num_bits < MAX_DECODED_BITS && (sample_idx + sp2_offset) < pts) 
    {
        uint8_t sp1 = buf[sample_idx + sp1_offset];
        uint8_t sp2 = buf[sample_idx + sp2_offset];

        if (sp2 == 1) {
            strcpy(res->encoding_type, "RZ Error (No Return)");
            res->num_bits_decoded = num_bits;
            return 0; 
        }

        uint8_t bit = sp1; 
        res->decoded_bits[num_bits] = bit;
        
        int byte_idx = num_bits / 8;
        int bit_in_byte = 7 - (num_bits % 8);
        if (bit) res->decoded_bytes[byte_idx] |= (1 << bit_in_byte);
        
        num_bits++;
        sample_idx += bw;
    }
    res->num_bits_decoded = num_bits;
    return 1;
}


// 3. NRZ-I
static int decode_nrz_i(SignalAnalysisResult_t* res, uint8_t* buf, int pts, int edge_idx, uint32_t bw)
{
    strcpy(res->encoding_type, "NRZ-I");
    int sample_idx = -1; 
    
    if (edge_idx != -1) {
        sample_idx = edge_idx + (bw / 2);
    } else {
        sample_idx = bw / 2;
    }
    
    if (sample_idx - bw < 0) { // 检查是否能安全获取上一个电平
         strcpy(res->encoding_type, "NRZ-I Error (Sync Fail)");
         res->num_bits_decoded = 0;
         return 0; // 无法同步
    }
    int last_mid_lvl = buf[sample_idx - bw];
    
    int num_bits = 0;
    while(num_bits < MAX_DECODED_BITS && sample_idx < pts) 
    {
        uint8_t current_mid_lvl = buf[sample_idx];
        
        uint8_t bit = (current_mid_lvl != last_mid_lvl); // 1 = 翻转, 0 = 未翻转
        
        res->decoded_bits[num_bits] = bit;
        
        int byte_idx = num_bits / 8;
        int bit_in_byte = 7 - (num_bits % 8);
        if (bit) res->decoded_bytes[byte_idx] |= (1 << bit_in_byte);
        
        num_bits++;
        sample_idx += bw;
        last_mid_lvl = current_mid_lvl;
    }
		
    res->num_bits_decoded = num_bits;
    return 1; 
}

// 4. Manchester
static int decode_manchester(SignalAnalysisResult_t* res, uint8_t* buf, int pts, int edge_idx, uint32_t bw)
{
    strcpy(res->encoding_type, "Manchester");
    int sample_idx = -1; 
    
    // 曼彻斯特在码元 *中间* 翻转, 所以边沿就是码元边界
    if (edge_idx != -1) {
        sample_idx = edge_idx;
    } else {
        sample_idx = 0; 
    }

    uint32_t sp1_offset = bw / 4; 
    uint32_t sp2_offset = (bw * 3) / 4; 

    int num_bits = 0;
    while(num_bits < MAX_DECODED_BITS && (sample_idx + sp2_offset) < pts) 
    {
        uint8_t sp1 = buf[sample_idx + sp1_offset]; // 前半周
        uint8_t sp2 = buf[sample_idx + sp2_offset]; // 后半周

        uint8_t bit = 0;
        
        if (sp1 == 0 && sp2 == 1) { // 0 -> 1 (G.E. Thomas / 802.3)
            bit = 1;
        } else if (sp1 == 1 && sp2 == 0) { // 1 -> 0
            bit = 0;
        } else {
            // 失败: (0->0) 或 (1->1)
            strcpy(res->encoding_type, "Manchester Error (No Mid-Bit)");
            res->num_bits_decoded = num_bits;
            return 0; // 失败
        }

        res->decoded_bits[num_bits] = bit;
        
        int byte_idx = num_bits / 8;
        int bit_in_byte = 7 - (num_bits % 8);
        if (bit) res->decoded_bytes[byte_idx] |= (1 << bit_in_byte);
        
        num_bits++;
        sample_idx += bw;
    }
    res->num_bits_decoded = num_bits;
    return 1; // 成功
}

static int decode_diff_manchester(SignalAnalysisResult_t* res, uint8_t* buf, int pts, int edge_idx, uint32_t bw)
{
    strcpy(res->encoding_type, "Diff. Manch");
    int sample_idx = -1; 
    
    // 同样，边沿就是码元边界
    if (edge_idx != -1) {
        sample_idx = edge_idx;
    } else {
        sample_idx = 0; 
    }

    // 检查是否能安全获取上一个电平
    if (sample_idx - (bw/4) < 0) { 
         strcpy(res->encoding_type, "Diff.Manch Error (Sync Fail)");
         res->num_bits_decoded = 0;
         return 0; // 无法同步
    }
    // 获取上一个码元 *后半段* 的电平，用于比较
    uint8_t last_lvl = buf[sample_idx - (bw / 4)]; 

    uint32_t sp1_offset = bw / 4; 
    uint32_t sp2_offset = (bw * 3) / 4; 

    int num_bits = 0;
    while(num_bits < MAX_DECODED_BITS && (sample_idx + sp2_offset) < pts) 
    {
        uint8_t sp1 = buf[sample_idx + sp1_offset]; // 前半周
        uint8_t sp2 = buf[sample_idx + sp2_offset]; // 后半周

        // 1. 检查时钟位 (码元中间必须翻转)
        if (sp1 == sp2) {
            strcpy(res->encoding_type, "Diff.Manch Error (No Mid-Bit)");
            res->num_bits_decoded = num_bits;
            return 0; 
        }

        // 2. 解码数据 (比较码元 *开始* 处是否翻转)
        // sp1 就是码元开始处的电平
        uint8_t bit = (sp1 == last_lvl); // 1 = 未翻转, 0 = 翻转
        
        res->decoded_bits[num_bits] = bit;
        
        int byte_idx = num_bits / 8;
        int bit_in_byte = 7 - (num_bits % 8);
        if (bit) res->decoded_bytes[byte_idx] |= (1 << bit_in_byte);
        
        num_bits++;
        sample_idx += bw;
        last_lvl = sp2; // 下一次比较的 "上一个电平" 是当前码元的后半段电平
    }
    res->num_bits_decoded = num_bits;
    return 1; // 成功
}

static int decode_uart(SignalAnalysisResult_t* res, uint8_t* buf, int pts, uint32_t bw)
{
    strcpy(res->encoding_type, "UART");
    res->is_uart_data = 1; // ** 标记为 UART 数据 **
    
    // --- 1. 搜索第一个起始位 ---
    // (UART idle=1, start=0. 在我们的反相世界中: idle=0, start=1)
    // 我们搜索 0 -> 1 的跳变
    int start_bit_idx = -1; 
    for (int i = 1; i < pts; i++) {
        if (buf[i-1] == 0 && buf[i] == 1) {
            start_bit_idx = i; 
            break;
        }
    }
    
    if (start_bit_idx == -1) {
        strcpy(res->encoding_type, "UART Error (No Start)");
        return 0;
    }

    int num_bytes = 0;
    int current_idx = start_bit_idx; 
    
    // --- 2. 循环解码字节 (最多 3 字节或 24 bit) ---
    while (num_bytes < 3 && (current_idx + (bw * 9.5)) < pts) 
    {
        uint8_t byte = 0;
        // 采样 D0 的中心 (起始位 + 1.5 * 位宽)
        int data_start_idx = current_idx + (bw * 3 / 2);
        
        // --- 3. 解码 8 个数据位 ---
        for (int j = 0; j < 8; j++) {
            int sample_pt = data_start_idx + (j * bw);
            if (sample_pt >= pts) {
                 strcpy(res->encoding_type, "UART Error (Incomplete)");
                 res->num_bits_decoded = num_bytes * 8;
                 return 0;
            }
            // (UART LSB-first)
            if (buf[sample_pt]) { 
                byte |= (1 << j);
            }
        }
        
        // --- 4. 验证停止位 ---
        // (停止位在 D7 之后 1 个位宽)
        int stop_bit_idx = data_start_idx + (8 * bw);
        if (stop_bit_idx >= pts) {
             strcpy(res->encoding_type, "UART Error (Incomplete)");
             res->num_bits_decoded = num_bytes * 8;
             return 0;
        }
        // (UART stop=1. 在我们的反相世界中: stop=0)
        // 如果停止位不是 0, 则帧错误
        if (buf[stop_bit_idx] == 1) { 
            strcpy(res->encoding_type, "UART Error (Framing)");
            res->num_bits_decoded = num_bytes * 8;
            return 0;
        }
        
        // --- 5. 存储数据 ---
        res->decoded_bytes[num_bytes] = byte;
        res->num_bits_decoded += 8;
        num_bytes++;
        
        // 移动到下一个可能的起始位
        current_idx += (10 * bw);
        
        // (为简化,我们只解码连续的字节,不重新搜索)
        // (如果下一个不是起始位, 退出)
        if (current_idx >= pts || buf[current_idx] == 0) {
            break;
        }
    }
    
    if (num_bytes == 0) {
        strcpy(res->encoding_type, "UART Error (Incomplete)");
        return 0;
    }

    return 1; // 成功
}

// ============================================================================
// --- Section 8: 主分析函数 (Master Analyzer) (无修改) ---
// ============================================================================
void Analyze_and_Display_Signal(
    uint8_t* buffer, 
    int points, 
    uint8_t freq_code,  // 频率索引
    uint8_t baud_code,  // ** <--- 新增 **
    EncodingType_t encoding
)
{
    SignalAnalysisResult_t result;
    memset(&result, 0, sizeof(SignalAnalysisResult_t));
    result.sample_rate_hz = SAMPLE_RATE_HZ;
    result.is_uart_data = 0; // 默认
    
    // --- Pass 1: 计算位宽 ---
    if (encoding == ENCODE_UART) {
        result.baud_rate_est = UART_BAUD_RATES[baud_code];
    } else {
        result.baud_rate_est = FREQ_HZ[freq_code];
    }
    result.bit_width = SAMPLE_RATE_HZ / result.baud_rate_est;
    
    
    // --- Pass 1.5: 查找第一个跳变沿 ---
    int first_edge_index = -1; 
    uint8_t last_level = buffer[0];
    for (int i = 1; i < points; i++) {
        if (buffer[i] != last_level) {
            first_edge_index = i; 
            break;
        }
    }
    
    // --- Pass 2: 根据选择的编码器进行解码 ---
    int success = 0;
    switch (encoding)
    {
        case ENCODE_NRZ_L:
            success = decode_nrz_l(&result, buffer, points, first_edge_index, result.bit_width);
            break;
        case ENCODE_RZ:
            success = decode_rz(&result, buffer, points, first_edge_index, result.bit_width);
            break;
        case ENCODE_NRZ_I:
            success = decode_nrz_i(&result, buffer, points, first_edge_index, result.bit_width);
            break;
        case ENCODE_MANCHESTER:
            success = decode_manchester(&result, buffer, points, first_edge_index, result.bit_width);
            break;
        case ENCODE_DIFF_MANCHESTER:
             success = decode_diff_manchester(&result, buffer, points, first_edge_index, result.bit_width);
            break;
        case ENCODE_UART: // ** <--- 新增 **
             // UART 解码器有自己的同步逻辑，不需要 first_edge_index
             success = decode_uart(&result, buffer, points, result.bit_width);
             break;
        default:
            strcpy(result.encoding_type, "Not Implemented");
            success = 0;
    }
    
    Display_Analyze_Results(&result);
}

// ★ 新增：USB CDC 页面绘制实现 ★
void Display_USB_CDC(void)
{
    lcd_clear(UI_BLUE_ALICE);
    Draw_Normal_Button(USB_CDC_Title);
    
    // --- 绘制右侧按钮 ---
    Draw_Normal_Button(USB_CDC_Start);
    Draw_Button_Effect(USB_CDC_Stop); // 默认是 Stop 状态
    Draw_Normal_Button(USB_CDC_Exit);

    // --- 绘制左侧功能说明文本框 ---
    Draw_Text_Boundary(USB_CDC_Description, "Function: USB CDC Protocol Converter"); 

    
    // ★ 修复：显式设置画笔颜色 ★
    // 确保在调用 lcd_show_string 之前，全局颜色是正确的（黑字白底）
    brush_color = LCD_BLACK;
    back_color = LCD_WHITE;

    // 在文本框内逐行显示说明文字
    // (注意：这里的坐标是相对于文本框 USB_CDC_Description 的左上角)
    uint16_t x = USB_CDC_Description.Box.X1 + 10;
    uint16_t y = USB_CDC_Description.Box.Y1 + 15;
    uint16_t s = USB_CDC_Description.TextSize;
    uint16_t w = USB_CDC_Description.Box.Width - 20;
		
		y += (s + 8); // 增加行距 (到第二行)
    lcd_show_string(x, y, w, s+2, "This module bridges the USB CDC (Serial", s);
    y += (s + 5);
    lcd_show_string(x, y, w, s+2, "port) with FPGA internal logic.", s);
    y += (s + 8);
    lcd_show_string(x, y, w, s+2, "PC software can send commands to control:", s);
    y += (s + 8);
    lcd_show_string(x, y, w, s+2, " - SPI Master", s);
    y += (s + 5);
    lcd_show_string(x, y, w, s+2, " - I2C Master", s);
    y += (s + 5);
    lcd_show_string(x, y, w, s+2, " - UART Bridge", s);
    y += (s + 5);
    lcd_show_string(x, y, w, s+2, " - Multi-Channel PWM Output", s);
    y += (s + 15);
    lcd_show_string(x, y, w, s+2, "M1 CPU is NOT involved in the protocol", s);
    y += (s + 5);
    lcd_show_string(x, y, w, s+2, "conversion. M1 only starts or stops", s);
    y += (s + 5);
    lcd_show_string(x, y, w, s+2, "this mode.", s);
    y += (s + 15);
    lcd_show_string(x, y, w, s+2, "Press 'Start CDC' to enable PC connection.", s);
}


// --- Section 2: 特定功能更新/绘制函数 ---

// ★ 新增：加载屏幕函数 ★
void Display_Loading_Screen(const char* module_name)
{
    lcd_clear(UI_BLUE_ALICE);
    
    // 绘制一个居中的方框
    Box_XY loading_box = {400 - 150, 240 - 50, 300, 100};
    Draw_Box(loading_box, LCD_BLACK, UI_GRAY_LIGHT);
    
    char buffer[64];
    sprintf(buffer, "Loading %s...", module_name);
    
    // ★ 修复：使用 lcd_show_string 替换 Draw_Text_In_Box ★
    // 并手动计算居中坐标
    uint16_t s = 24; // 字体大小
    uint16_t w = loading_box.Width - 10;  // 文本区域宽度
    uint16_t h = s + 2;                    // 文本区域高度
    uint16_t x = loading_box.X1 + 10;      // 文本 X 坐标
    uint16_t y = loading_box.Y1 + (loading_box.Height - h) / 2; // 文本 Y 坐标 (垂直居中)
    
    // 确保颜色正确
    brush_color = LCD_BLACK;
    back_color = LCD_WHITE; // 背景是方框的填充色
    
    lcd_show_string(x, y, w, h, buffer, s);
}

// ★ 新增：软件延时函数 ★
// (这是一个粗略的、阻塞的延时，仅用于UI)
// (注意：GOWIN_M1 CPU时钟频率是 50MHz)
#define CPU_CYCLES_PER_MS (50000) // 假设 50MHz, 每毫秒 50000 周期
void mcu_sw_delay_ms(volatile uint32_t ms)
{
    volatile uint32_t i, j;
    // (这个循环计数需要根据实际CPU频率和优化等级进行粗略调整)
    // (我们假设内循环消耗约 10-20 个周期)
    const uint32_t loops_per_ms = CPU_CYCLES_PER_MS / 15; 

    for (i = 0; i < ms; i++) {
        for (j = 0; j < loops_per_ms; j++) {
            __asm volatile("nop");
        }
    }
}