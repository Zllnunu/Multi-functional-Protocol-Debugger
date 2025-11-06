#include "main.h"
#include "MCU_LCD.h"
#include "GOWIN_M1.h"
#include <stdio.h>
#include "Touch.h"
#include "PageDesign.h"
#include "event_handler.h"
#include "fpga_registers.h"
#include "ui_design_handler.h"

// 引入所有UI元素的定义
#include "Create_Features.h"
#include "wave_output_features.h"
#include "analog_input_features.h"
#include "digital_input_features.h"


// ============================================================================
// Section 1: 全局变量定义
// ============================================================================
volatile PageState_t currentPage = PAGE_MAIN;
char display_str_buffer[64];


// ============================================================================
// Section 2: 主函数 main()
// ============================================================================
int main(void)
{
	SystemInit();
	//UartInit();
	//GPIOInit();
	GT1151_Init();
	mcu_lcd_reg_init();
	
	brush_color = LCD_BLACK;
	back_color  = LCD_WHITE;
	
	lcd_clear(LCD_WHITE);
    set_display_on();
	
	Display_Main_board();

	while(1) {
		switch(currentPage) {
            case PAGE_MAIN:          Handle_Main_Page();       break;
            case PAGE_WAVE_OUTPUT:   Handle_Wave_Out_Page();   break;
            case PAGE_ANALOG_INPUT:  Handle_Analog_In_Page();  break;
            case PAGE_DIGITAL_INPUT: Handle_Digital_In_Page(); break;
						case PAGE_USB_CDC: 			 Handle_USB_CDC_Page(); 	 break;
            default:
                currentPage = PAGE_MAIN;
                Display_Main_board();
                break;
        }
	}
}

// ============================================================================
// Section 3: 底层函数
// ============================================================================
uint8_t Judge_TpXY(Touch_Data Touch_LCD, Box_XY Box)
{
	if((Touch_LCD.Tp_X[0] >= Box.X1)&&(Touch_LCD.Tp_X[0] <= Box.X1 + Box.Width)
			&&(Touch_LCD.Tp_Y[0] >= Box.Y1)&&(Touch_LCD.Tp_Y[0] <= Box.Y1 + Box.Height))
		return 1;
	else
		return 0;
}
