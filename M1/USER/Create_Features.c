
#include "PageDesign.h"
#include "Create_Features.h"

/*
主界面UI部分
*/

// --- 波形输出按钮 ---
// 使用经典的UI蓝色，给人一种精确、科技的感觉。
Button Wave_Generate = {
		{90,70,270,150},
		LCD_BLACK, UI_PINK_LIGHT, // 文本颜色, 背景颜色
		32,{"Wave Out"}
};

// --- 模拟输入按钮 ---
// 使用清晰、友好的绿色，暗示信号的“激活”或“自然”属性。
Button Analog_Input = {
		{440,70,270,150},
		LCD_BLACK, BTN_GREEN_LIGHT,
		32,{"Analog In"}
};

// --- 数字输入按钮 ---
// 使用温暖、引人注目的金色，代表数字信号的“注意”或“重要”。
Button Digital_Input = {
		{90,280,270,150},
		LCD_BLACK, BTN_TEAL_LIGHT,
		32,{"Digital In"}
};

// --- USB CDC 按钮 ---
// 使用介于蓝绿之间的青色，给人一种“连接”和“通信”的感觉，且富有现代感。
Button USB_CDC = {
		{440,280,270,150},
		LCD_BLACK,BTN_YELLOW_GOLD,
		32,{"USB CDC"}
};

