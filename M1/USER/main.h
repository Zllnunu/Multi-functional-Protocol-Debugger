#ifndef __MAIN_H__
#define __MAIN_H__

// ----------------------------------------------------------------------------
//  本文件用于定义全局可用的类型、声明全局变量和全局函数。
//  其他 .c 文件可以通过 #include "main.h" 来访问它们。
// ----------------------------------------------------------------------------

#include <stdint.h>
#include "Touch.h" // 需要 Touch_Data 类型
#include "PageDesign.h"

// 1. 定义UI页面状态枚举
typedef enum {
    PAGE_MAIN,
    PAGE_WAVE_OUTPUT,
    PAGE_ANALOG_INPUT,
    PAGE_DIGITAL_INPUT,
		PAGE_USB_CDC
} PageState_t;

// 2. 将需要在多文件间共享的全局变量声明为 extern
extern volatile PageState_t currentPage;
extern Touch_Data Touch_LCD;
extern char display_str_buffer[64];

// 3. 声明底层驱动/判断函数
uint8_t Judge_TpXY(Touch_Data Touch_LCD, Box_XY Box);

#endif // __MAIN_H__
