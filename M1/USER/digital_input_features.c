#include "digital_input_features.h"
#include "PageDesign.h"

// ================== 标题 (保持不变) ==================
Button Digital_Title = {
    {5, 5, 790, 60},
    LCD_BLACK, BTN_TEAL_LIGHT, 
    24, {"** Digital Signal Analyzer **"} 
};

// ================== 左侧：显示区 ==================
// 这是一个占位框，定义了左侧显示区的范围
Box_XY Digital_Display_Area = {
    10, 70, 540, 400
};

// “测量模式”的参数显示区 (位于显示区内部)
Text Digital_Freq_Text = {{20, 80, 520, 70}, LCD_BLACK, LCD_WHITE, 32};
Text Digital_Duty_Text = {{20, 160, 520, 70}, LCD_BLACK, LCD_WHITE, 32};
Text Digital_tHigh_Text = {{20, 240, 520, 70}, LCD_BLACK, LCD_WHITE, 32};
Text Digital_tLow_Text = {{20, 320, 520, 70}, LCD_BLACK, LCD_WHITE, 32};

// “分析模式”的结果显示区 (同样位于显示区内部)
Text Digital_Analyze_Result = {
    {15, 75, 530, 390},
    LCD_BLACK, UI_BLUE_ALICE,
    20
};

// ================== 右侧：控制面板区 ==================

// --- 模式切换按钮 ---
Button Digital_Mode_Measure = {
    {560, 70, 230, 60},
    LCD_WHITE, BTN_BLUE_CORN,
    24, {"Measure Mode"}
};

Button Digital_Mode_Analyze = {
    {560, 140, 230, 60},
    LCD_BLACK, BTN_GRAY_SILVER,
    24, {"Analyze Mode"}
};


// (定义编码名称字符串)
const char* ENCODING_NAMES[ENCODE_TYPE_COUNT] = {
    "[NRZ-L]",
    "[RZ]",
    "[NRZ-I]",
    "[Manchester]",
    "[Diff. Manch]",
		"[UART]"
};

const char* FREQ_NAMES[FREQ_LEVELS] = {
    "Freq: 25kHz",  
    "Freq: 50kHz",
    "Freq: 100kHz",
    "Freq: 250kHz"  
};
// (对应的 HZ 值，用于计算)
const uint32_t FREQ_HZ[FREQ_LEVELS] = {
    25000,
    50000,
    100000,
    250000
};

// --- ** 核心 3: 新增 UART 波特率列表 ** ---
const char* UART_BAUD_NAMES[UART_BAUD_LEVELS] = {
    "Baud: 9600",
    "Baud: 19200",
    "Baud: 38400",
    "Baud: 57600",
    "Baud: 115200"
};
const uint32_t UART_BAUD_RATES[UART_BAUD_LEVELS] = {
    9600, 19200, 38400, 57600, 115200
};


Button Encoding_Select_Button = {
    {560, 210, 230, 60}, // 放在 Analyze 按钮下方
    LCD_BLACK, BTN_ORANGE_SAND, // 复制 Freq 按钮的颜色
    24, {"[NRZ-L]"}       // ** 已按要求修改 **
};

Button Freq_Select_Button = {
    {560, 280, 230, 60}, // **Y 坐标下移**
    LCD_BLACK, UI_GRAY_LIGHT, 
    24, {"Freq: 50kHz"}    // 默认 50kHz
};

Button Digital_Start = {
    {560, 350, 110, 60}, // **宽度减半**
    LCD_BLACK, UI_GREEN_MINT,
    24, {"RUN"}
};

Button Digital_Pause = {
    {680, 350, 110, 60}, // **宽度减半并移到右侧**
    LCD_BLACK, UI_PINK_LIGHT,
    24, {"STOP"}
};


// --- 系统按钮 (保持不变) ---
Button Digital_Reset = {
    {560, 420, 110, 55}, // 稍微调整大小和位置
    LCD_BLACK, UI_LAVENDER,
    24, {"Reset"}
};

Button Digital_Exit = {
    {680, 420, 110, 55}, // 稍微调整大小和位置
    LCD_BLACK, UI_YELLOW_PALE,
    24, {"Exit"}
};