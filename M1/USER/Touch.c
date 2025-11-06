/**
  *****************************************************************************
  * 						触摸屏相关库
  *****************************************************************************
  *
  * @File   : Touch.c
  * @By     : Sun
  * @Version: V1.1
  * @Date   : 2021 / 11 / 04
  * @Shop	: https://xiaomeige.taobao.com/
  *
  *****************************************************************************
**/

#include "Touch.h"
/******** X轴和Y轴坐标方向 ********

————————————————→X轴(0~800)
|
|
|
|
↓
Y轴(0~480)

*********************************/
Touch_Data Touch_LCD;
uint16_t tp_x[5];        //当前坐标
uint16_t tp_y[5];
uint16_t tp_sta;
const uint16_t GT1151_TPX_TBL[5]= {GT_TP1_REG,GT_TP2_REG,GT_TP3_REG,GT_TP4_REG,GT_TP5_REG};

static void delay_ms(__IO uint32_t nCount);

/***************GT1151配置参数表***************/
const uint8_t GT1151_CFG_TBL[236]= {
	0x83,0xE0,0x01,0x20,0x03,0x05,0x3D,0x14,
	0x00,0x00,0x02,0x0C,0x5F,0x4B,0x35,0x01,
	0x00,0x06,0x06,0x1E,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x38,0x00,0x00,0x64,0x08,
	0x32,0x28,0x28,0x64,0x00,0x00,0x87,0xA0,
	0xCD,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x8A,0x00,
	0x10,0x74,0x76,0xEB,0x06,0x02,0x1E,0x52,
	0x24,0xFA,0x1E,0x18,0x32,0xAA,0x63,0x99,
	0x6E,0x82,0x79,0x80,0x85,0x00,0x00,0x00,
	0x00,0x64,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x58,0x9C,0xC0,0x94,0x85,0x28,0x0A,0x03,
	0xAA,0x63,0x99,0x6E,0x8A,0x79,0x80,0x85,
	0x77,0x90,0x71,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x0D,0x0E,0x0F,0x10,0x12,0x13,0x14,
	0x15,0x16,0x17,0x18,0x19,0x1A,0x1B,0x1D,
	0x1F,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
	0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
	0xFF,0x06,0x08,0x0C,0x12,0x13,0x14,0x15,
	0x17,0x18,0x19,0xFF,0xFF,0xFF,0xFF,0xFF,
	0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
	0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
	0xFF,0x00,0xC4,0x09,0x23,0x23,0x50,0x5D,
	0x54,0x50,0x3C,0x14,0x32,0xFF,0xFF,0x06,
	0x51,0x00,0x8A,0x02,0x40,0x00,0xAA,0x00,
	0x22,0x22,0x00,0x40,
};


void GT1151_WR_Reg(uint16_t Reg_Addr, uint8_t *Buff, uint16_t Len)
{
	uint32_t i;
	
	I2C->TXR = SLAVE_DEV_ADDR;
	I2C->CR = I2C_CMD_STA|I2C_CMD_WR;
	while(I2C->SR&I2C_SR_TIP);//wait TIP
	while(I2C->SR&I2C_SR_RXACK);//wait ack-----Over Here

	//高8位
	I2C->TXR = Reg_Addr >> 8;
	I2C->CR = (I2C_CMD_WR);
	while(I2C->SR&I2C_SR_TIP);//wait TIP
	while(I2C->SR&I2C_SR_RXACK);//wait ack
	
	//低8位
	I2C->TXR = Reg_Addr & 0xFF;	
	I2C->CR = (I2C_CMD_WR);
	while(I2C->SR&I2C_SR_TIP);//wait TIP
	while(I2C->SR&I2C_SR_RXACK);//wait ack
	
	for(i=0;i<Len;i++)
	{
		I2C->TXR = Buff[i];
		if((Len-1) == i)
		{
			I2C->CR = (I2C_CMD_STO|I2C_CMD_WR);
		}
		else
		{
			I2C->CR = (I2C_CMD_WR);
		}
		
		while(I2C->SR&I2C_SR_TIP);//wait TIP
		while(I2C->SR&I2C_SR_RXACK);//wait ack
	}
	
	while(I2C->SR&I2C_SR_BUSY);
	Delay_ms_i2c(3);//Wait the data to I2C Ready
	
}

void GT1151_RD_Reg(uint16_t Reg_Addr, uint8_t *Buff, uint16_t Len)
{
	uint32_t i;
	
	I2C->TXR = SLAVE_DEV_ADDR;
	I2C->CR = I2C_CMD_STA|I2C_CMD_WR;	
	while(I2C->SR&I2C_SR_TIP);
	while(I2C->SR&I2C_SR_RXACK);//wait ack-----Over Here
	
	//高8位
	I2C->TXR = Reg_Addr >> 8;	
	I2C->CR = (I2C_CMD_WR);
	while(I2C->SR&I2C_SR_TIP);//wait TIP
	while(I2C->SR&I2C_SR_RXACK);//wait ack
	
	//低8位
	I2C->TXR = Reg_Addr & 0xFF;	
	I2C->CR = (I2C_CMD_WR);
	while(I2C->SR&I2C_SR_TIP);//wait TIP
	while(I2C->SR&I2C_SR_RXACK);//wait ack

	I2C->TXR = SLAVE_DEV_ADDR | 0x01;	
	I2C->CR = (I2C_CMD_STA|I2C_CMD_WR);
	while(I2C->SR&I2C_SR_TIP);
	while(I2C->SR&I2C_SR_RXACK);//wait ack	
	
	for(i=0;i<Len;i++)
	{
		if((Len-1) == i)
		{
			I2C->CR = (I2C_CMD_ACK|I2C_CMD_STO|I2C_CMD_RD);//send nack
		}
		else
		{
			I2C->CR = (~I2C_CMD_ACK&I2C_CMD_RD);//send ack
		}
		
		while(I2C->SR&I2C_SR_TIP);
		Buff[i] = I2C->RXR;
	}
	
	while(I2C->SR&I2C_SR_BUSY);
	
}

/**
  *****************************************************************************
  * @功能描述: 发送GT1151配置参数
  *
  * @输入参数: mode:0,参数不保存到flash;1,参数保存到flash
  *****************************************************************************
**/
uint8_t GT1151_Send_Cfg(uint8_t mode)
{
    uint8_t buf[3];
    uint16_t i,checksum = 0;
    buf[2]=mode;    //是否掉电保存
	
	//计算校验和
	for(i=0;i<118;i++)
		checksum += (((uint16_t)GT1151_CFG_TBL[2*i] << 8) + GT1151_CFG_TBL[2*i + 1]);
	checksum = ~checksum + 1;
	printf("checksum :0x%04X \n",checksum);
	
	buf[0] = checksum >> 8;
	buf[1] = checksum & 0xFF;
	
    GT1151_WR_Reg(GT_CFGS_REG,(uint8_t*)GT1151_CFG_TBL,236);//发送寄存器配置
    GT1151_WR_Reg(GT_CHECK_REG,buf,3);//写入校验和,和配置更新标记
    return 0;
}

/**
  *****************************************************************************
  * @功能描述: 初始化GT1151触摸屏
  *
  * @返回值   : 0,初始化成功;1,初始化失败
  *****************************************************************************
**/
void GT1151_Init(void)
{
    uint8_t id[5] = {0};
    uint8_t buff[1];

    TP_IIC_Init(100);	//初始化I2C,频率为400K

    TP_RST_LOW;			//RST输出为0，复位
    delay_ms(10);		//延时10ms
    TP_RST_HIGH;		//RST输出为1，释放复位
	delay_ms(100);

    GT1151_RD_Reg(GT_PID_REG,id,4);		//读取ID
    printf("Touch ID:%s\n",id);				//打印ID
    buff[0]=0X02;
	GT1151_WR_Reg(GT_CTRL_REG,buff,1);	//软复位GT1151
	GT1151_RD_Reg(GT_CFGS_REG,buff,1);	//读取GT_CFGS_REG寄存器
	printf("Previous version: 0x%02X\n",buff[0]);		//显示之前配置的版本号（A~Z）
	if(buff[0] < GT1151_CFG_TBL[0])		//如果之前配置版本小于预配置版本
		GT1151_Send_Cfg(0);		//更新配置但不保存
	GT1151_RD_Reg(GT_CFGS_REG,buff,1);		//读取GT_CFGS_REG寄存器
	printf("Current version: 0x%02X\n",buff[0]);		//显示当前配置的版本号（A~Z）
	delay_ms(10);		//延时10ms
	buff[0]=0X00;
	GT1151_WR_Reg(GT_CTRL_REG,buff,1);//结束复位
}

/**
  *****************************************************************************
  * @功能描述: 扫描触摸屏(轮询方式)
  * @输入值：Touch_Data结构体变量
  *****************************************************************************
**/
void GT1151_Scan(Touch_Data *Touch_LCD, uint8_t dir)
{
	uint8_t i;
	uint8_t State = 0;
	uint8_t Data_XY[4]={0};
	uint16_t X_Pos,Y_Pos;
	uint8_t Zero = 0;

	Touch_LCD->Touched_Last = Touch_LCD->Touched;//保存上次的触摸状态
	GT1151_RD_Reg(GT_GSTID_REG,&State,1);	//读取触摸状态寄存器
	//最高位为1表示数据有效
	if(State & 0X80) {
		Touch_LCD->Touch_Num = State & 0X0F;		//获取触点数量，数量为0表示无按键
		//将触摸点换算到对应bit，为1表示触摸，为0表示未触摸
		Touch_LCD->Touched = 0x1F >> (5 - Touch_LCD->Touch_Num);

		//依次获取触摸点坐标
		if(dir==0){ //竖屏
			for(i=0;i<5;i++) {//for(i=0;i<Touch_LCD->Touch_Num;i++) {
				GT1151_RD_Reg(GT1151_TPX_TBL[i],Data_XY,4);	//读取XY坐标值
				X_Pos = Data_XY[3] << 8;
				X_Pos |= Data_XY[2];
				Y_Pos = Data_XY[1] << 8;
				Y_Pos |= Data_XY[0];
				
				if(X_Pos <= 480)
					Touch_LCD->Tp_X[i] = X_Pos;
				if(Y_Pos <= 800)
					Touch_LCD->Tp_Y[i] = Y_Pos;
			}
		}else{	//横屏
			for(i=0;i<5;i++) {//for(i=0;i<Touch_LCD->Touch_Num;i++) {
				GT1151_RD_Reg(GT1151_TPX_TBL[i],Data_XY,4);	//读取XY坐标值
				X_Pos = Data_XY[3] << 8;
				X_Pos |= Data_XY[2];
				Y_Pos = Data_XY[1] << 8;
				Y_Pos |= Data_XY[0];
				
				if(X_Pos <= 800)
					Touch_LCD->Tp_X[i] = 800 - X_Pos;
				if(Y_Pos <= 480)
					Touch_LCD->Tp_Y[i] = Y_Pos;
			}
		}
		GT1151_WR_Reg(GT_GSTID_REG, &Zero, 1);	//写0清寄存器来开启下一次检测
	}
}

//delay ms
static void delay_ms(__IO uint32_t nCount)
{
	nCount *= 4333;
	for(; nCount != 0; nCount--);
}
