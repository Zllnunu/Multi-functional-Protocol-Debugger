#include "usb_cdc_features.h"
#include "PageDesign.h"

// ================== 标题 ==================
Button USB_CDC_Title = {
    {5, 5, 790, 60},  // X1, Y1, Width, Height (横跨整个屏幕)
    LCD_BLACK, LCD_GRAY, // TextColor, BackColor
    24, {"USB CDC Serial Converter"}
};

// ================== 功能说明区 (左半部分) ==================
Text USB_CDC_Description = {
    {5, 70, 545, 405},   // Box: X1, Y1, Width, Height (和模拟波形区一样大)
    LCD_BLACK,           // TextColor
    LCD_WHITE,           // BackColor
    20                   // 字体大小
};


// ================== 按钮区 (右半部分) ==================
Button USB_CDC_Start = {
    {565, 120, 220, 100}, // X1, Y1, Width, Height
    LCD_BLACK,UI_GREEN_MINT, // TextColor, BackColor
    24, {"Start CDC"}  
};

Button USB_CDC_Stop = {
    {565, 240, 220, 100},
    LCD_BLACK, UI_PINK_LIGHT,
    24, {"Stop CDC"}  
};

Button USB_CDC_Exit = {
    {565, 360, 220, 100},
    LCD_BLACK, UI_YELLOW_PALE,
    24, {"Exit"}
};