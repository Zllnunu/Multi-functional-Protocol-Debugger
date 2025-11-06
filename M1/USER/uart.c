/*
 ******************************************************************************************
 * @file          uart.c
 * @author        GowinSemicoductor
 * @device        Gowin_EMPU_M1
 * @brief         Uart0 App.
 ******************************************************************************************
 */

/* Includes ------------------------------------------------------------------*/
#include "uart.h"

/* Definitions ---------------------------------------------------------------*/
void UartInit(void)
{
  UART_InitTypeDef UART_InitStruct;

  UART_InitStruct.UART_Mode.UARTMode_Tx = ENABLE;
  UART_InitStruct.UART_Mode.UARTMode_Rx = ENABLE;
  UART_InitStruct.UART_Int.UARTInt_Tx = DISABLE;
  UART_InitStruct.UART_Int.UARTInt_Rx = DISABLE;
  UART_InitStruct.UART_Ovr.UARTOvr_Tx = DISABLE;
  UART_InitStruct.UART_Ovr.UARTOvr_Rx = DISABLE;
  UART_InitStruct.UART_Hstm = DISABLE;
  UART_InitStruct.UART_BaudRate = 115200;//Baud Rate

  UART_Init(UART0,&UART_InitStruct);
}
