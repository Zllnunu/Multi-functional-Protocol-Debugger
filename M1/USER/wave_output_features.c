#include "wave_output_features.h"
#include "PageDesign.h"

//////// 顶部提示框 ////////
Text Crruent_Waveform = {
    {10, 10, 240, 70},   // Box: X1, Y1, Width, Height
    LCD_RED,            // TextColor
    LCD_WHITE,           // BackColor
    32                    // 字体大小
};

////////右侧按键 //////////
Button Wave_Switch = {
		{260,10,240,70},		//按键坐标X1、Y1、宽度、高度
		LCD_BLACK,BTN_BLUE_SKY_DEEP,//按键内的文本颜色和背景颜色
		24,{"Wave_Switch"}		//按键文本的字体大小和文本内容
};

Button Output_Start = {
		{520,10,120,80},
		LCD_BLACK,UI_GREEN_MINT,
		24,{"Start"}
};

Button Output_Stop = {
		{660,10,120,80},
		LCD_BLACK,UI_PINK_LIGHT,
		24,{"Stop"}
};

Button Voltage_up = {
		{520,100,120,80},
		LCD_BLACK,LCD_GRAY,
		24,{"V+"}
};

Button Voltage_down = {
		{660,100,120,80},
		LCD_BLACK,LCD_GRAY,
		24,{"V-"}
};

Button Frequency_up = {
		{520,190,120,80},
		LCD_BLACK,LCD_GRAY,
		24,{"Freq+"}
};

Button Frequency_down = {
		{660,190,120,80},
		LCD_BLACK,LCD_GRAY,
		24,{"Freq-"}
};

Button PWM_up = {
		{520,280,120,80},
		LCD_BLACK,LCD_GRAY,
		24,{"PWM+"}
};

Button PWM_down = {
		{660,280,120,80},
		LCD_BLACK,LCD_GRAY,
		24,{"PWM-"}
};

Button Out_Exit = {
		{520,370,260,80},
		LCD_BLACK,UI_YELLOW_PALE,
		24,{"Exit"}
};

////// 波形展示区 ///////
Box_XY Wave_Out_Board = {
		10,90,490,290
};

////// 底部参数展示区 ///////
Text Crruent_Volt = {
    {10,390,160, 70},   // Box: X1, Y1, Width, Height
    LCD_BLACK,            
    LCD_WHITE,           
    24                    
};
Text Crruent_Freq = {
    {175, 390, 160, 70},   
    LCD_BLACK,            
    LCD_WHITE,           
    24                   
};
Text Crruent_Duty = {
    {340, 390, 160, 70},   
    LCD_BLACK,            
    LCD_WHITE,           
    24                    
};


