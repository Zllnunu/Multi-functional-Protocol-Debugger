#ifndef TOUCH_TOUCH_H_
#define TOUCH_TOUCH_H_

#include "GOWIN_M1.h"

#define SLAVE_DEV_ADDR 0x28	//8位设备地址

#define TP_IIC_Init(freq)  					I2C_Init(I2C,freq)

#define	TP_RST_HIGH	GPIO_SetBit(GPIO0,GPIO_Pin_2)
#define	TP_RST_LOW	GPIO_ResetBit(GPIO0,GPIO_Pin_2)


//GT1151常用寄存器
#define GT_CTRL_REG     0X8040      //GT1151控制寄存器
#define GT_CFGS_REG     0X8050      //GT1151配置起始地址寄存器
#define GT_CHECK_REG    0X813C      //GT1151校验和寄存器
#define GT_PID_REG      0X8140      //GT1151产品ID寄存器

#define GT_GSTID_REG    0X814E      //GT1151当前检测到的触摸情况
#define GT_TP1_REG      0X8150      //第一个触摸点数据地址
#define GT_TP2_REG      0X8158      //第二个触摸点数据地址
#define GT_TP3_REG      0X8160      //第三个触摸点数据地址
#define GT_TP4_REG      0X8168      //第四个触摸点数据地址
#define GT_TP5_REG      0X8170      //第五个触摸点数据地址

//创建触摸数据结构体
typedef struct {
	uint8_t Touched;		//本次是否被触摸
	uint8_t Touched_Last;	//上次是否被触摸
	uint8_t Touch_Num;		//触摸点数
	uint16_t Tp_X[5];		//触摸点的X坐标
	uint16_t Tp_Y[5];		//触摸点的Y坐标
} Touch_Data;

extern Touch_Data Touch_LCD;

uint8_t GT1151_Send_Cfg(uint8_t mode);//发送GT1151配置参数
void GT1151_Init(void);		//初始化GT1151触摸屏
void GT1151_Scan(Touch_Data *Touch_LCD, uint8_t dir);//扫描触摸屏
void delay_ms(__IO uint32_t nCount);

#endif /* TOUCH_TOUCH_H_ */
