#ifndef __MCU_LCD_H__
#define __MCU_LCD_H__

#include "GOWIN_M1.h"


typedef struct
{
    __IO uint32_t LCD_REG;
    __IO uint32_t LCD_RAM;
} LCD_TypeDef;


#define LCD	((LCD_TypeDef *) AHB_M1)

#define mpu_write_cmd(reg)		LCD->LCD_REG = reg
#define mpu_write_data(data)	LCD->LCD_RAM = data
#define mpu_read_data()			LCD->LCD_RAM

/* 定义LCD尺寸 */
#define LCD_WIDTH	800
#define LCD_HEIGHT	480

extern uint16_t brush_color; //笔刷颜色
extern uint16_t back_color;  //背景颜色


//笔刷颜色
#define LCD_WHITE		0XFFFF	//白色
#define LCD_BLACK		0X0000	//黑色

#define LCD_RED			0xF800	//红色
#define LCD_GREEN		0x07E0	//绿色
#define LCD_BLUE		0x001F	//蓝色

#define LCD_YELLOW		0xFFE0	//黄色
#define LCD_CYAN		0x07FF	//青色
#define LCD_PURPLE		0x780F	//紫色

#define LCD_GRAY		0xCE79	//灰色
#define LCD_BROWN		0X8945	//棕色
#define LCD_VIOLET		0X88BC	//紫罗兰
#define LCD_PINK		0XFE19	//粉红色
#define LCD_DARKBLUE	0x000F	//深蓝色
#define LCD_ORANGE		0xFC00	//橘黄色

// ============================================================================
// UI设计颜色 (淡雅/柔和色系)
// ============================================================================

// --- 灰色系 (用于背景、边框、非激活文字) ---
#define UI_GRAY_LIGHT     0xD69A  // 浅灰色 (RGB: 211, 211, 211)
#define UI_GRAY_MEDIUM    0x8410  // 中灰色 (RGB: 128, 128, 128)
#define UI_GRAY_DARK      0x4208  // 深灰色 (RGB: 64, 64, 64)

// --- 蓝色系 (适合用作主题色、按钮背景) ---
#define UI_BLUE_SKY       0x867C  // 淡天蓝色 (RGB: 135, 206, 235)
#define UI_BLUE_STEEL     0x441A  // 钢青色 (RGB: 70, 130, 180) - 一种沉稳的蓝色
#define UI_BLUE_ALICE     0xEFBF  // 爱丽丝蓝 (RGB: 240, 248, 255) - 非常浅，接近白色的蓝，适合做背景
#define UI_BLUE_ROYAL			0x435C  // 宝蓝色 (Hex: #4169E1)

// --- 绿色系 (适合表示“成功”、“启用”状态) ---
#define UI_GREEN_MINT     0x97F2  // 薄荷绿 (RGB: 152, 255, 152)
#define UI_GREEN_SEAFOAM  0x9EE3  // 海泡绿 (RGB: 159, 226, 191)

// --- 红色/粉色系 (适合表示“警告”、“退出”或点缀) ---
#define UI_PINK_LIGHT     0xFDB7  // 浅粉红 (RGB: 255, 182, 193)
#define UI_SALMON         0xFC0E  // 鲑鱼红/肉色 (RGB: 250, 128, 114)

// --- 黄色/橙色系 (适合表示“注意”、“提醒”) ---
#define UI_YELLOW_PALE    0xFFFB  // 淡黄色 (RGB: 255, 255, 224)
#define UI_ORANGE_PEACH   0xFCEE  // 桃色/浅橙 (RGB: 255, 160, 122)

// --- 紫色系 ---
#define UI_LAVENDER       0xE71E  // 薰衣草紫 (RGB: 230, 230, 250)

// ============================================================================
// **  适合黑色文字的按键背景色 **
// ============================================================================

// --- 功能绿色系 (适合 "Start", "Confirm", "Enable" 等按钮) ---
#define BTN_GREEN_LIGHT   0x9732  // 亮绿色 (Hex: #90EE90) - 清晰、友好
#define BTN_GREEN_LIME    0xAFE5  // 酸橙绿 (Hex: #ADFF2F) - 活泼、醒目

// --- 功能红色系 (适合 "Stop", "Exit", "Cancel" 等按钮) ---
#define BTN_RED_LIGHT     0xF410  // 浅珊瑚红 (Hex: #F08080) - 柔和的警示色
#define BTN_TOMATO        0xFB08  // 番茄红 (Hex: #FF6347) - 饱和度高，但不过于刺眼

// --- 功能蓝色系 (适合通用功能按钮) ---
#define BTN_BLUE_CORN     0x64BD  // 矢车菊蓝 (Hex: #6495ED) - 经典的UI蓝色
#define BTN_BLUE_SKY_DEEP 0x867E  // 蔚蓝色 (Hex: #87CEFA) - 明亮、干净

// --- 功能黄色/橙色系 (适合 "Pause", "Warning", "Mode" 等按钮) ---
#define BTN_YELLOW_GOLD   0xFF08  // 金黄色 (Hex: #FFD700) - 温暖、引人注目
#define BTN_ORANGE_SAND   0xF5AA  // 沙褐色 (Hex: #F4A460) - 稳重的橙色

// --- 功能中性色系 (适合次要或信息类按钮) ---
#define BTN_GRAY_SILVER   0xC618  // 银色 (Hex: #C0C0C0) - 标准的中性灰
#define BTN_TEAL_LIGHT    0x4E99  // 浅青色 (Hex: #48D1CC) - 介于蓝绿之间，有科技感


void mcu_lcd_reg_init(void);
void set_display_on(void);
void lcd_clear(uint16_t color);
void lcd_draw_point(uint16_t x, uint16_t y, uint16_t color);
uint16_t lcd_read_point(uint16_t x, uint16_t y);
void lcd_draw_bline(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint16_t color);
void lcd_fill(uint16_t xs, uint16_t ys, uint16_t xe, uint16_t ye, uint16_t color);
void lcd_draw_line(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint16_t color);
void lcd_draw_bline(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint16_t color);
void lcd_draw_rectangle(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint16_t color);
void lcd_show_pic(uint16_t x, uint16_t y, uint16_t width, uint16_t height, uint16_t *pic);
void lcd_show_char(uint16_t x, uint16_t y, char ch,  uint8_t size);
void lcd_show_string(uint16_t x, uint16_t y, uint16_t width, uint16_t height, char *str, uint8_t size);

#endif /* __MCU_LCD_H__ */
