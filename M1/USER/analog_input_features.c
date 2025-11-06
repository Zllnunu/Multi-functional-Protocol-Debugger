#include "analog_input_features.h"
#include "PageDesign.h"

// ================== 标题 ==================
Button Analog_Title = {
    {5, 5, 545, 60},  // X1, Y1, Width, Height
		LCD_BLACK, LCD_GRAY, // TextColor, BackColor
    24, {"*** Analog in ***"}
};


// ================== 波形展示区 ==================
Box_XY Analog_WaveBoard = {
    5, 70,     // 左上角 Y, X
    545,395  // 宽度, 高度 (550-5=545, 470-5=465)
};

// ================== 参数显示区 ==================
Text Analog_Volt_Text = {
    {560, 15, 220, 40},   // Box: X1, Y1, Width, Height
    LCD_BLACK,            // TextColor
    LCD_WHITE,           // BackColor
    24                    // 字体大小
};

Text Analog_Freq_Text = {
    {560, 65, 220, 40},
    LCD_BLACK,            
    LCD_WHITE,           
    24
};

Text Analog_Sample_Text = {
    {560, 115, 220, 40},
    LCD_BLACK,            
    LCD_WHITE,           
    24
};

// ================== 调节按键区 ==================
Button Analog_V_up = {
    {625, 165, 100, 40},  // X1, Y1, Width, Height
    LCD_BLACK, LCD_GRAY, // TextColor, BackColor
    24, {"Div/V+"}
};

Button Analog_Freq_down = {
    {560, 210, 80, 40},
    LCD_BLACK, LCD_GRAY,
    24, {"Time-"}
};

Button Analog_Freq_up = {
    {710, 210, 80, 40},
    LCD_BLACK, LCD_GRAY,
    24, {"Time+"}
};

Button Analog_V_down = {
    {625, 255, 100, 40},
    LCD_BLACK, LCD_GRAY,
    24, {"Div/V-"}
};

// ================== 按钮区 ==================
Button Analog_Start = {
    {565, 310, 100, 70},  // X1, Y1, Width, Height
    LCD_BLACK,UI_GREEN_MINT, // TextColor, BackColor
    24, {"Start"}  
};

Button Analog_Stop = {
    {685, 310, 100, 70},
    LCD_BLACK, UI_PINK_LIGHT,
    24, {"Stop"}  
};

Button Analog_Reset = {
    {565, 400, 100, 70},
    LCD_BLACK, UI_LAVENDER,
    24, {"Reset"}
};

Button Analog_Exit = {
    {685, 400, 100, 70},
    LCD_BLACK, UI_YELLOW_PALE ,
    24, {"Exit"}
};

