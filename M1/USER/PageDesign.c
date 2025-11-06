#include "PageDesign.h"
#include "string.h"


//绘制方框
void Draw_Box(Box_XY Box, uint32_t Color,int16_t Offset)
{
	lcd_draw_rectangle(Box.X1 + Offset, Box.Y1 + Offset,
			Box.X1 + Box.Width - Offset, Box.Y1 + Box.Height - Offset, Color);
}

//填充区域
void Fill_Box(Box_XY Box,uint32_t BackColor,int16_t Offset)
{
	lcd_fill(Box.X1+Offset,Box.Y1+Offset,
			Box.X1+Box.Width-Offset,Box.Y1+Box.Height-Offset,BackColor);
}


//绘制普通按键 
void Draw_Normal_Button(Button Button)
{
	uint8_t Byte = 0;
	uint8_t Rows = 0;
	uint8_t i;
	uint8_t Border_LineWidth = 2; //按键边框的线宽
	const uint8_t PADDING = 5;    // 文本与边框的最小间距

	brush_color = Button.TextColor;
	back_color = Button.BackColor;

	//画白色边框
	for(i=0; i<Border_LineWidth; i++)
		Draw_Box(Button.Box, LCD_WHITE, i);

	//画背景色边框
	for(i=Border_LineWidth; i<Border_LineWidth*2; i++)
		Draw_Box(Button.Box, PAGE_COLOR, i);


	//填充按键背景
	Fill_Box(Button.Box, Button.BackColor, Border_LineWidth*2);

	//计算Text的行数
	while (strlen(Button.Text[Rows]))
		Rows++;

	for(i=0; i<Rows; i++) {
		Byte = strlen(Button.Text[i]);
		uint16_t estimated_text_width = Byte * Button.TextSize / 2;
		uint16_t available_width = Button.Box.Width - (Border_LineWidth * 2) * 2 - PADDING * 2;
        
        uint16_t x_start_pos;
        uint16_t y_start_pos;

		// 计算 Y 轴偏移 (垂直居中)
		y_start_pos = Button.Box.Y1 + ((Button.Box.Height - Button.TextSize * Rows) / (Rows + 1)) * (i + 1) + (Button.TextSize * i);


		// 计算 X 轴偏移 (带溢出保护)
		if (estimated_text_width > available_width) {
			// 如果文本太长，则左对齐并留出边距
			x_start_pos = Button.Box.X1 + Border_LineWidth * 2 + PADDING;
		} else {
			// 如果文本可以容纳，则水平居中
			x_start_pos = Button.Box.X1 + (Button.Box.Width - estimated_text_width) / 2;
		}

		// 计算可用于绘制的最大宽度，确保 lcd_show_string 函数不会越界
		uint16_t max_draw_width = (Button.Box.X1 + Button.Box.Width) - x_start_pos - (Border_LineWidth * 2 + PADDING);

		lcd_show_string(x_start_pos, y_start_pos,
				max_draw_width, Button.TextSize + 2, Button.Text[i], Button.TextSize);
	}
}
//绘制普通文本
void Draw_Normal_Text(Text Text, char *str)

{
	uint16_t Byte;
	uint16_t X_Offset,Y_Offset;
	Box_XY Box = Text.Box;

	Byte = strlen(str);
	X_Offset = (Text.Box.Width - Byte*Text.TextSize/2)/2;
	Y_Offset = (Text.Box.Height - Text.TextSize)/2;

	brush_color = Text.TextColor;
	back_color = Text.BackColor;
	Box.Width = X_Offset;
	Fill_Box(Box,Text.BackColor,0);//先擦除
	Box.X1 = Text.Box.X1 + Text.Box.Width - X_Offset;
	Fill_Box(Box,Text.BackColor,0);//先擦除
	lcd_show_string(Text.Box.X1+X_Offset,Text.Box.Y1+Y_Offset,
		150,Text.TextSize+2,str,Text.TextSize);
}

// 绘制文本框
void Draw_Text_Boundary(Text Text, char *str)
{
    uint16_t x1 = Text.Box.X1;
    uint16_t y1 = Text.Box.Y1;
    uint16_t x2 = Text.Box.X1 + Text.Box.Width - 1;
    uint16_t y2 = Text.Box.Y1 + Text.Box.Height - 1;

    // 1. 设置全局颜色变量, 这会影响 lcd_show_string 的行为
    brush_color = Text.TextColor; // 设置文字颜色
    back_color = Text.BackColor;  // 设置文字的背景色

    // 2. 填充整个文本框的背景区域
    lcd_fill(x1, y1, x2, y2, Text.BackColor);

    // 3. 绘制黑色的外边框 (与按钮风格类似)
    lcd_draw_rectangle(x1, y1, x2, y2, LCD_BLACK);

    // 4. 显示文字
    // lcd_show_string 会使用我们刚设置的 back_color 作为文字背景
    // 这样文字背景和文本框背景就完全一致了
    lcd_show_string(x1 + 15,                                      // X坐标: 左对齐, 并向右偏移5像素
                    y1 + (Text.Box.Height - Text.TextSize) / 2,  // Y坐标: 垂直居中
                    Text.Box.Width - 10,                         // 文字显示区域的最大宽度
                    Text.Box.Height,                             // 文字显示区域的最大高度
                    str,
                    Text.TextSize);
}

//绘制按键特效
void Draw_Button_Effect(Button Button)
{
	uint8_t Byte = 0;
	uint8_t Rows = 0;
	uint8_t i;
	uint16_t X_Offset,Y_Offset;
	uint8_t Border_LineWidth = 3;	//按键边框的线宽，值越大线越粗
	uint8_t Effect_Width = 4;	//按键特效的效果，值越大特效越明显
	brush_color = Button.TextColor;
	back_color = Button.BackColor;

	//清除外框
	for(i=0;i<Border_LineWidth*4;i++)
		Draw_Box(Button.Box, PAGE_COLOR, i);

	//画白色边框
	for(i=0;i<Border_LineWidth;i++)
		Draw_Box(Button.Box, LCD_WHITE, i+Effect_Width);

	//填充按键背景
	Fill_Box(Button.Box,Button.BackColor,Border_LineWidth*2+Effect_Width);

	//计算Text的行数
	while (strlen(Button.Text[Rows]))
		Rows++;

	for(i=0;i<Rows;i++){
		Byte = strlen(Button.Text[i]);
		X_Offset = (Button.Box.Width - Byte*Button.TextSize/2)/2;
		Y_Offset = (Button.Box.Height - Button.TextSize*Rows)/(Rows+1) + Button.TextSize*i;
		lcd_show_string(Button.Box.X1+X_Offset,Button.Box.Y1+Y_Offset,
				150,Button.TextSize+2,Button.Text[i],Button.TextSize);
	}
}
