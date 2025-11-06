#include "MCU_LCD.h"
#include "font.h"
#include "math.h"

uint16_t brush_color =LCD_BLACK; //笔刷颜色
uint16_t back_color  =LCD_WHITE; //背景颜色


//delay
static void delay_ms(__IO uint32_t nCount)
{
	nCount *= 4333;
	for(; nCount != 0; nCount--);
}

void mpu_write_reg(uint16_t reg, uint16_t dat)
{
    mpu_write_cmd(reg);
	__nop();
    mpu_write_data(dat);
}


static void set_column_address(uint16_t sc, uint16_t ec)
{
    mpu_write_cmd(0x2A00);
    mpu_write_data((uint8_t)(sc >> 8) & 0xFF);
    mpu_write_cmd(0x2A01);
    mpu_write_data((uint8_t)sc & 0xFF);
    mpu_write_cmd(0x2A02);
    mpu_write_data((uint8_t)(ec >> 8) & 0xFF);
    mpu_write_cmd(0x2A03);
    mpu_write_data((uint8_t)ec & 0xFF);
}


static void set_row_address(uint16_t sp, uint16_t ep)
{
    mpu_write_cmd(0x2B00);
    mpu_write_data((uint8_t)(sp >> 8) & 0xFF);
    mpu_write_cmd(0x2B01);
    mpu_write_data((uint8_t)sp & 0xFF);
    mpu_write_cmd(0x2B02);
    mpu_write_data((uint8_t)(ep >> 8) & 0xFF);
    mpu_write_cmd(0x2B03);
    mpu_write_data((uint8_t)ep & 0xFF);
}


static void start_write_memory(void)
{
    mpu_write_cmd(0x2C00);
}

static void start_read_memory(void)
{
    mpu_write_cmd(0x2E00);
}

void mcu_lcd_reg_init(void)
{
	uint16_t lcd_id = 0;
	
	//读取NT35510 ID
	mpu_write_cmd(0XDA00);
	lcd_id=mpu_read_data();  //0X00
	mpu_write_cmd(0XDB00);
	lcd_id=mpu_read_data();  //0X80
	lcd_id<<=8;
	mpu_write_cmd(0XDC00);
	lcd_id|=mpu_read_data(); //0X00
	if(lcd_id==0x8000)
		lcd_id=0x5510;//NT35510读回ID是8000H,为方便区分,设置为5510
	printf("lcd id: 0x%04X",lcd_id);
    if(lcd_id==0x5510) {
		mpu_write_reg(0xF000, 0x55);
		mpu_write_reg(0xF001, 0xAA);
		mpu_write_reg(0xF002, 0x52);
		mpu_write_reg(0xF003, 0x08);
		mpu_write_reg(0xF004, 0x01);
		mpu_write_reg(0xB000, 0x0D);
		mpu_write_reg(0xB001, 0x0D);
		mpu_write_reg(0xB002, 0x0D);
		mpu_write_reg(0xB600, 0x34);
		mpu_write_reg(0xB601, 0x34);
		mpu_write_reg(0xB602, 0x34);
		mpu_write_reg(0xB100, 0x0D);
		mpu_write_reg(0xB101, 0x0D);
		mpu_write_reg(0xB102, 0x0D);
		mpu_write_reg(0xB700, 0x34);
		mpu_write_reg(0xB701, 0x34);
		mpu_write_reg(0xB702, 0x34);
		mpu_write_reg(0xB200, 0x00);
		mpu_write_reg(0xB201, 0x00);
		mpu_write_reg(0xB202, 0x00);
		mpu_write_reg(0xB800, 0x24);
		mpu_write_reg(0xB801, 0x24);
		mpu_write_reg(0xB802, 0x24);
		mpu_write_reg(0xBF00, 0x01);
		mpu_write_reg(0xB300, 0x0F);
		mpu_write_reg(0xB301, 0x0F);
		mpu_write_reg(0xB302, 0x0F);
		mpu_write_reg(0xB900, 0x34);
		mpu_write_reg(0xB901, 0x34);
		mpu_write_reg(0xB902, 0x34);
		mpu_write_reg(0xB500, 0x08);
		mpu_write_reg(0xB501, 0x08);
		mpu_write_reg(0xB502, 0x08);
		mpu_write_reg(0xC200, 0x03);
		mpu_write_reg(0xBA00, 0x24);
		mpu_write_reg(0xBA01, 0x24);
		mpu_write_reg(0xBA02, 0x24);
		mpu_write_reg(0xBC00, 0x00);
		mpu_write_reg(0xBC01, 0x78);
		mpu_write_reg(0xBC02, 0x00);
		mpu_write_reg(0xBD00, 0x00);
		mpu_write_reg(0xBD01, 0x78);
		mpu_write_reg(0xBD02, 0x00);
		mpu_write_reg(0xBE00, 0x00);
		mpu_write_reg(0xBE01, 0x64);
		mpu_write_reg(0xD100, 0x00);
		mpu_write_reg(0xD101, 0x33);
		mpu_write_reg(0xD102, 0x00);
		mpu_write_reg(0xD103, 0x34);
		mpu_write_reg(0xD104, 0x00);
		mpu_write_reg(0xD105, 0x3A);
		mpu_write_reg(0xD106, 0x00);
		mpu_write_reg(0xD107, 0x4A);
		mpu_write_reg(0xD108, 0x00);
		mpu_write_reg(0xD109, 0x5C);
		mpu_write_reg(0xD10A, 0x00);
		mpu_write_reg(0xD10B, 0x81);
		mpu_write_reg(0xD10C, 0x00);
		mpu_write_reg(0xD10D, 0xA6);
		mpu_write_reg(0xD10E, 0x00);
		mpu_write_reg(0xD10F, 0xE5);
		mpu_write_reg(0xD110, 0x01);
		mpu_write_reg(0xD111, 0x13);
		mpu_write_reg(0xD112, 0x01);
		mpu_write_reg(0xD113, 0x54);
		mpu_write_reg(0xD114, 0x01);
		mpu_write_reg(0xD115, 0x82);
		mpu_write_reg(0xD116, 0x01);
		mpu_write_reg(0xD117, 0xCA);
		mpu_write_reg(0xD118, 0x02);
		mpu_write_reg(0xD119, 0x00);
		mpu_write_reg(0xD11A, 0x02);
		mpu_write_reg(0xD11B, 0x01);
		mpu_write_reg(0xD11C, 0x02);
		mpu_write_reg(0xD11D, 0x34);
		mpu_write_reg(0xD11E, 0x02);
		mpu_write_reg(0xD11F, 0x67);
		mpu_write_reg(0xD120, 0x02);
		mpu_write_reg(0xD121, 0x84);
		mpu_write_reg(0xD122, 0x02);
		mpu_write_reg(0xD123, 0xA4);
		mpu_write_reg(0xD124, 0x02);
		mpu_write_reg(0xD125, 0xB7);
		mpu_write_reg(0xD126, 0x02);
		mpu_write_reg(0xD127, 0xCF);
		mpu_write_reg(0xD128, 0x02);
		mpu_write_reg(0xD129, 0xDE);
		mpu_write_reg(0xD12A, 0x02);
		mpu_write_reg(0xD12B, 0xF2);
		mpu_write_reg(0xD12C, 0x02);
		mpu_write_reg(0xD12D, 0xFE);
		mpu_write_reg(0xD12E, 0x03);
		mpu_write_reg(0xD12F, 0x10);
		mpu_write_reg(0xD130, 0x03);
		mpu_write_reg(0xD131, 0x33);
		mpu_write_reg(0xD132, 0x03);
		mpu_write_reg(0xD133, 0x6D);
		mpu_write_reg(0xD200, 0x00);
		mpu_write_reg(0xD201, 0x33);
		mpu_write_reg(0xD202, 0x00);
		mpu_write_reg(0xD203, 0x34);
		mpu_write_reg(0xD204, 0x00);
		mpu_write_reg(0xD205, 0x3A);
		mpu_write_reg(0xD206, 0x00);
		mpu_write_reg(0xD207, 0x4A);
		mpu_write_reg(0xD208, 0x00);
		mpu_write_reg(0xD209, 0x5C);
		mpu_write_reg(0xD20A, 0x00);
		mpu_write_reg(0xD20B, 0x81);
		mpu_write_reg(0xD20C, 0x00);
		mpu_write_reg(0xD20D, 0xA6);
		mpu_write_reg(0xD20E, 0x00);
		mpu_write_reg(0xD20F, 0xE5);
		mpu_write_reg(0xD210, 0x01);
		mpu_write_reg(0xD211, 0x13);
		mpu_write_reg(0xD212, 0x01);
		mpu_write_reg(0xD213, 0x54);
		mpu_write_reg(0xD214, 0x01);
		mpu_write_reg(0xD215, 0x82);
		mpu_write_reg(0xD216, 0x01);
		mpu_write_reg(0xD217, 0xCA);
		mpu_write_reg(0xD218, 0x02);
		mpu_write_reg(0xD219, 0x00);
		mpu_write_reg(0xD21A, 0x02);
		mpu_write_reg(0xD21B, 0x01);
		mpu_write_reg(0xD21C, 0x02);
		mpu_write_reg(0xD21D, 0x34);
		mpu_write_reg(0xD21E, 0x02);
		mpu_write_reg(0xD21F, 0x67);
		mpu_write_reg(0xD220, 0x02);
		mpu_write_reg(0xD221, 0x84);
		mpu_write_reg(0xD222, 0x02);
		mpu_write_reg(0xD223, 0xA4);
		mpu_write_reg(0xD224, 0x02);
		mpu_write_reg(0xD225, 0xB7);
		mpu_write_reg(0xD226, 0x02);
		mpu_write_reg(0xD227, 0xCF);
		mpu_write_reg(0xD228, 0x02);
		mpu_write_reg(0xD229, 0xDE);
		mpu_write_reg(0xD22A, 0x02);
		mpu_write_reg(0xD22B, 0xF2);
		mpu_write_reg(0xD22C, 0x02);
		mpu_write_reg(0xD22D, 0xFE);
		mpu_write_reg(0xD22E, 0x03);
		mpu_write_reg(0xD22F, 0x10);
		mpu_write_reg(0xD230, 0x03);
		mpu_write_reg(0xD231, 0x33);
		mpu_write_reg(0xD232, 0x03);
		mpu_write_reg(0xD233, 0x6D);
		mpu_write_reg(0xD300, 0x00);
		mpu_write_reg(0xD301, 0x33);
		mpu_write_reg(0xD302, 0x00);
		mpu_write_reg(0xD303, 0x34);
		mpu_write_reg(0xD304, 0x00);
		mpu_write_reg(0xD305, 0x3A);
		mpu_write_reg(0xD306, 0x00);
		mpu_write_reg(0xD307, 0x4A);
		mpu_write_reg(0xD308, 0x00);
		mpu_write_reg(0xD309, 0x5C);
		mpu_write_reg(0xD30A, 0x00);
		mpu_write_reg(0xD30B, 0x81);
		mpu_write_reg(0xD30C, 0x00);
		mpu_write_reg(0xD30D, 0xA6);
		mpu_write_reg(0xD30E, 0x00);
		mpu_write_reg(0xD30F, 0xE5);
		mpu_write_reg(0xD310, 0x01);
		mpu_write_reg(0xD311, 0x13);
		mpu_write_reg(0xD312, 0x01);
		mpu_write_reg(0xD313, 0x54);
		mpu_write_reg(0xD314, 0x01);
		mpu_write_reg(0xD315, 0x82);
		mpu_write_reg(0xD316, 0x01);
		mpu_write_reg(0xD317, 0xCA);
		mpu_write_reg(0xD318, 0x02);
		mpu_write_reg(0xD319, 0x00);
		mpu_write_reg(0xD31A, 0x02);
		mpu_write_reg(0xD31B, 0x01);
		mpu_write_reg(0xD31C, 0x02);
		mpu_write_reg(0xD31D, 0x34);
		mpu_write_reg(0xD31E, 0x02);
		mpu_write_reg(0xD31F, 0x67);
		mpu_write_reg(0xD320, 0x02);
		mpu_write_reg(0xD321, 0x84);
		mpu_write_reg(0xD322, 0x02);
		mpu_write_reg(0xD323, 0xA4);
		mpu_write_reg(0xD324, 0x02);
		mpu_write_reg(0xD325, 0xB7);
		mpu_write_reg(0xD326, 0x02);
		mpu_write_reg(0xD327, 0xCF);
		mpu_write_reg(0xD328, 0x02);
		mpu_write_reg(0xD329, 0xDE);
		mpu_write_reg(0xD32A, 0x02);
		mpu_write_reg(0xD32B, 0xF2);
		mpu_write_reg(0xD32C, 0x02);
		mpu_write_reg(0xD32D, 0xFE);
		mpu_write_reg(0xD32E, 0x03);
		mpu_write_reg(0xD32F, 0x10);
		mpu_write_reg(0xD330, 0x03);
		mpu_write_reg(0xD331, 0x33);
		mpu_write_reg(0xD332, 0x03);
		mpu_write_reg(0xD333, 0x6D);
		mpu_write_reg(0xD400, 0x00);
		mpu_write_reg(0xD401, 0x33);
		mpu_write_reg(0xD402, 0x00);
		mpu_write_reg(0xD403, 0x34);
		mpu_write_reg(0xD404, 0x00);
		mpu_write_reg(0xD405, 0x3A);
		mpu_write_reg(0xD406, 0x00);
		mpu_write_reg(0xD407, 0x4A);
		mpu_write_reg(0xD408, 0x00);
		mpu_write_reg(0xD409, 0x5C);
		mpu_write_reg(0xD40A, 0x00);
		mpu_write_reg(0xD40B, 0x81);
		mpu_write_reg(0xD40C, 0x00);
		mpu_write_reg(0xD40D, 0xA6);
		mpu_write_reg(0xD40E, 0x00);
		mpu_write_reg(0xD40F, 0xE5);
		mpu_write_reg(0xD410, 0x01);
		mpu_write_reg(0xD411, 0x13);
		mpu_write_reg(0xD412, 0x01);
		mpu_write_reg(0xD413, 0x54);
		mpu_write_reg(0xD414, 0x01);
		mpu_write_reg(0xD415, 0x82);
		mpu_write_reg(0xD416, 0x01);
		mpu_write_reg(0xD417, 0xCA);
		mpu_write_reg(0xD418, 0x02);
		mpu_write_reg(0xD419, 0x00);
		mpu_write_reg(0xD41A, 0x02);
		mpu_write_reg(0xD41B, 0x01);
		mpu_write_reg(0xD41C, 0x02);
		mpu_write_reg(0xD41D, 0x34);
		mpu_write_reg(0xD41E, 0x02);
		mpu_write_reg(0xD41F, 0x67);
		mpu_write_reg(0xD420, 0x02);
		mpu_write_reg(0xD421, 0x84);
		mpu_write_reg(0xD422, 0x02);
		mpu_write_reg(0xD423, 0xA4);
		mpu_write_reg(0xD424, 0x02);
		mpu_write_reg(0xD425, 0xB7);
		mpu_write_reg(0xD426, 0x02);
		mpu_write_reg(0xD427, 0xCF);
		mpu_write_reg(0xD428, 0x02);
		mpu_write_reg(0xD429, 0xDE);
		mpu_write_reg(0xD42A, 0x02);
		mpu_write_reg(0xD42B, 0xF2);
		mpu_write_reg(0xD42C, 0x02);
		mpu_write_reg(0xD42D, 0xFE);
		mpu_write_reg(0xD42E, 0x03);
		mpu_write_reg(0xD42F, 0x10);
		mpu_write_reg(0xD430, 0x03);
		mpu_write_reg(0xD431, 0x33);
		mpu_write_reg(0xD432, 0x03);
		mpu_write_reg(0xD433, 0x6D);
		mpu_write_reg(0xD500, 0x00);
		mpu_write_reg(0xD501, 0x33);
		mpu_write_reg(0xD502, 0x00);
		mpu_write_reg(0xD503, 0x34);
		mpu_write_reg(0xD504, 0x00);
		mpu_write_reg(0xD505, 0x3A);
		mpu_write_reg(0xD506, 0x00);
		mpu_write_reg(0xD507, 0x4A);
		mpu_write_reg(0xD508, 0x00);
		mpu_write_reg(0xD509, 0x5C);
		mpu_write_reg(0xD50A, 0x00);
		mpu_write_reg(0xD50B, 0x81);
		mpu_write_reg(0xD50C, 0x00);
		mpu_write_reg(0xD50D, 0xA6);
		mpu_write_reg(0xD50E, 0x00);
		mpu_write_reg(0xD50F, 0xE5);
		mpu_write_reg(0xD510, 0x01);
		mpu_write_reg(0xD511, 0x13);
		mpu_write_reg(0xD512, 0x01);
		mpu_write_reg(0xD513, 0x54);
		mpu_write_reg(0xD514, 0x01);
		mpu_write_reg(0xD515, 0x82);
		mpu_write_reg(0xD516, 0x01);
		mpu_write_reg(0xD517, 0xCA);
		mpu_write_reg(0xD518, 0x02);
		mpu_write_reg(0xD519, 0x00);
		mpu_write_reg(0xD51A, 0x02);
		mpu_write_reg(0xD51B, 0x01);
		mpu_write_reg(0xD51C, 0x02);
		mpu_write_reg(0xD51D, 0x34);
		mpu_write_reg(0xD51E, 0x02);
		mpu_write_reg(0xD51F, 0x67);
		mpu_write_reg(0xD520, 0x02);
		mpu_write_reg(0xD521, 0x84);
		mpu_write_reg(0xD522, 0x02);
		mpu_write_reg(0xD523, 0xA4);
		mpu_write_reg(0xD524, 0x02);
		mpu_write_reg(0xD525, 0xB7);
		mpu_write_reg(0xD526, 0x02);
		mpu_write_reg(0xD527, 0xCF);
		mpu_write_reg(0xD528, 0x02);
		mpu_write_reg(0xD529, 0xDE);
		mpu_write_reg(0xD52A, 0x02);
		mpu_write_reg(0xD52B, 0xF2);
		mpu_write_reg(0xD52C, 0x02);
		mpu_write_reg(0xD52D, 0xFE);
		mpu_write_reg(0xD52E, 0x03);
		mpu_write_reg(0xD52F, 0x10);
		mpu_write_reg(0xD530, 0x03);
		mpu_write_reg(0xD531, 0x33);
		mpu_write_reg(0xD532, 0x03);
		mpu_write_reg(0xD533, 0x6D);
		mpu_write_reg(0xD600, 0x00);
		mpu_write_reg(0xD601, 0x33);
		mpu_write_reg(0xD602, 0x00);
		mpu_write_reg(0xD603, 0x34);
		mpu_write_reg(0xD604, 0x00);
		mpu_write_reg(0xD605, 0x3A);
		mpu_write_reg(0xD606, 0x00);
		mpu_write_reg(0xD607, 0x4A);
		mpu_write_reg(0xD608, 0x00);
		mpu_write_reg(0xD609, 0x5C);
		mpu_write_reg(0xD60A, 0x00);
		mpu_write_reg(0xD60B, 0x81);
		mpu_write_reg(0xD60C, 0x00);
		mpu_write_reg(0xD60D, 0xA6);
		mpu_write_reg(0xD60E, 0x00);
		mpu_write_reg(0xD60F, 0xE5);
		mpu_write_reg(0xD610, 0x01);
		mpu_write_reg(0xD611, 0x13);
		mpu_write_reg(0xD612, 0x01);
		mpu_write_reg(0xD613, 0x54);
		mpu_write_reg(0xD614, 0x01);
		mpu_write_reg(0xD615, 0x82);
		mpu_write_reg(0xD616, 0x01);
		mpu_write_reg(0xD617, 0xCA);
		mpu_write_reg(0xD618, 0x02);
		mpu_write_reg(0xD619, 0x00);
		mpu_write_reg(0xD61A, 0x02);
		mpu_write_reg(0xD61B, 0x01);
		mpu_write_reg(0xD61C, 0x02);
		mpu_write_reg(0xD61D, 0x34);
		mpu_write_reg(0xD61E, 0x02);
		mpu_write_reg(0xD61F, 0x67);
		mpu_write_reg(0xD620, 0x02);
		mpu_write_reg(0xD621, 0x84);
		mpu_write_reg(0xD622, 0x02);
		mpu_write_reg(0xD623, 0xA4);
		mpu_write_reg(0xD624, 0x02);
		mpu_write_reg(0xD625, 0xB7);
		mpu_write_reg(0xD626, 0x02);
		mpu_write_reg(0xD627, 0xCF);
		mpu_write_reg(0xD628, 0x02);
		mpu_write_reg(0xD629, 0xDE);
		mpu_write_reg(0xD62A, 0x02);
		mpu_write_reg(0xD62B, 0xF2);
		mpu_write_reg(0xD62C, 0x02);
		mpu_write_reg(0xD62D, 0xFE);
		mpu_write_reg(0xD62E, 0x03);
		mpu_write_reg(0xD62F, 0x10);
		mpu_write_reg(0xD630, 0x03);
		mpu_write_reg(0xD631, 0x33);
		mpu_write_reg(0xD632, 0x03);
		mpu_write_reg(0xD633, 0x6D);
		mpu_write_reg(0xF000, 0x55);
		mpu_write_reg(0xF001, 0xAA);
		mpu_write_reg(0xF002, 0x52);
		mpu_write_reg(0xF003, 0x08);
		mpu_write_reg(0xF004, 0x00);
		mpu_write_reg(0xB100, 0xCC);
		mpu_write_reg(0xB101, 0x00);
		mpu_write_reg(0xB600, 0x05);
		mpu_write_reg(0xB700, 0x70);
		mpu_write_reg(0xB701, 0x70);
		mpu_write_reg(0xB800, 0x01);
		mpu_write_reg(0xB801, 0x03);
		mpu_write_reg(0xB802, 0x03);
		mpu_write_reg(0xB803, 0x03);
		mpu_write_reg(0xBC00, 0x02);
		mpu_write_reg(0xBC01, 0x00);
		mpu_write_reg(0xBC02, 0x00);
		mpu_write_reg(0xC900, 0xD0);
		mpu_write_reg(0xC901, 0x02);
		mpu_write_reg(0xC902, 0x50);
		mpu_write_reg(0xC903, 0x50);
		mpu_write_reg(0xC904, 0x50);
		mpu_write_reg(0x3500, 0x00);
		mpu_write_reg(0x3A00, 0x55);
		mpu_write_cmd(0x1100);
		delay_ms(1);
		mpu_write_cmd(0x2900);
	}
	mpu_write_reg(0x3600, 0x00A0);
}



void set_display_on(void)
{
   mpu_write_cmd(0x2900);
}

void lcd_fill(uint16_t xs, uint16_t ys, uint16_t xe, uint16_t ye, uint16_t color)
{
    uint16_t x_index;
    uint16_t y_index;
    
    set_column_address(xs, xe);
    set_row_address(ys, ye);
    start_write_memory();
    for (y_index=ys; y_index<=ye; y_index++)
    {
        for (x_index=xs; x_index<= xe; x_index++)
        {
            mpu_write_data(color);
        }
    }
}


void lcd_clear(uint16_t color)
{
   lcd_fill(0, 0, LCD_WIDTH - 1, LCD_HEIGHT - 1, color);
}


void lcd_draw_point(uint16_t x, uint16_t y, uint16_t color)
{
    set_column_address(x, x);
    set_row_address(y, y);
    start_write_memory();
    mpu_write_data(color);
}

uint16_t lcd_read_point(uint16_t x, uint16_t y)
{
    uint16_t color;
    uint8_t color_r;
    uint8_t color_g;
    uint8_t color_b;
    
    if ((x >= LCD_WIDTH) || (y >= LCD_HEIGHT))
    {
        return 0;
    }
    
    set_column_address(x, x);
    set_row_address(y, y);
    start_read_memory();
    
    color = mpu_read_data(); /* Dummy */
    color = mpu_read_data(); /* [15:11]: R, [7:2]:G */
    color_r = (uint8_t)(color >> 11) & 0x1F;
    color_g = (uint8_t)(color >> 2) & 0x3F;
    color = mpu_read_data(); /* [15:11]: B */
    color_b = (uint8_t)(color >> 11) & 0x1F;
    
    return (uint16_t)(color_r << 11) | (color_g << 5) | color_b;
}


void lcd_draw_line(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint16_t color)
{
	uint16_t t;
	int xerr=0,yerr=0,delta_x,delta_y,distance;
	int incx,incy,uRow,uCol;
	
	//越界判断
	if(x1 > LCD_WIDTH)
		x1 = LCD_WIDTH;
	if(x2 > LCD_WIDTH)
		x2 = LCD_WIDTH;
	if(y1 > LCD_HEIGHT)
		y1 = LCD_HEIGHT;
	if(y2 > LCD_HEIGHT)
		y2 = LCD_HEIGHT;
	
	delta_x=x2-x1; //计算坐标增量
	delta_y=y2-y1;
	uRow=x1;
	uCol=y1;
	if(delta_x>0)
		incx=1;  //设置单步方向
	else if(delta_x==0)
		incx=0;  //垂直线
	else {incx=-1;delta_x=-delta_x;}
	if(delta_y>0)
		incy=1;
	else if(delta_y==0)
		incy=0;  //水平线
	else {incy=-1;delta_y=-delta_y;}
	if(delta_x>delta_y)
		distance=delta_x;         //选取基本增量坐标轴
	else distance=delta_y;
	for(t=0;t<=distance+1;t++ )    //画线输出
	{
		lcd_draw_point(uRow,uCol,color); //画点
		xerr+=delta_x ;
		yerr+=delta_y ;
		if(xerr>distance){
			 xerr-=distance;
			 uRow+=incx;
		}
		if(yerr>distance){
			 yerr-=distance;
			 uCol+=incy;
		}
	}
}

void lcd_draw_bline(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint16_t color)
{
	uint16_t i,j;
	uint8_t LWidth = 3;	//线条宽度

	for(i=0;i<2*LWidth;i++) {
		for(j=0;j<2*LWidth;j++) {
			if((pow(j-LWidth,2) + pow(i-LWidth,2) - pow(LWidth,2)) < 0) {
					lcd_draw_line(x1-LWidth+j,y1-LWidth+i,x2-LWidth+j,y2-LWidth+i, color);
			}
		}
	}
}

void lcd_draw_rectangle(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint16_t color)
{
    lcd_draw_line(x1, y1, x2, y1, color);
    lcd_draw_line(x1, y1, x1, y2, color);
    lcd_draw_line(x1, y2, x2, y2, color);
    lcd_draw_line(x2, y1, x2, y2, color);
}

void lcd_show_pic(uint16_t x, uint16_t y, uint16_t width, uint16_t height, uint16_t *pic)
{
    uint16_t x_index;
    uint16_t y_index;
    
    if ((x + width > LCD_WIDTH) || (y + height > LCD_HEIGHT))
    {
        return;
    }
    
    set_column_address(x, x + width - 1);
    set_row_address(y, y + height - 1);
    start_write_memory();
    for (y_index=y; y_index<=(y + height - 1); y_index++)
    {
        for (x_index=x; x_index<=(x + width - 1); x_index++)
        {
            mpu_write_data(*pic);
            pic++;
        }
    }
}


void lcd_show_char(uint16_t x, uint16_t y, char ch, uint8_t size)
{
    const uint8_t *ch_code;
    uint8_t ch_width;
    uint8_t ch_height;
    uint8_t ch_size;
    uint8_t ch_offset;
    uint8_t byte_index;
    uint8_t byte_code;
    uint8_t bit_index;
    uint8_t width_index = 0;
    uint8_t height_index = 0;
    
    ch_offset = ch - ' ';
    
    switch (size)
    {
        case 12:
        {
            ch_code = asc2_1206[ch_offset];
            ch_width = 6;
            ch_height = 12;
            ch_size = 12;
            break;
        }
        case 16:
        {
            ch_code = asc2_1608[ch_offset];
            ch_width = 8;
            ch_height = 16;
            ch_size = 16;
            break;
        }
        case 24:
        {
            ch_code = asc2_2412[ch_offset];
            ch_width = 12;
            ch_height = 24;
            ch_size = 48;
            break;
        }
        case 32:
        {
            ch_code = asc2_3216[ch_offset];
            ch_width = 16;
            ch_height = 32;
            ch_size = 64;
            break;
        }
        default:
        {
            return;
        }
    }
    
    if ((x + ch_width > LCD_WIDTH) || (y + ch_height > LCD_HEIGHT))
    {
        return;
    }
    
	set_column_address(x, x + ch_width-1);
	set_row_address(y, y + ch_height-1);
	start_write_memory();
	
    for (byte_index=0; byte_index<ch_size; byte_index++)
    {
        byte_code = ch_code[byte_index];

        for (bit_index=0; bit_index<8; bit_index++)
        {
            if ((byte_code & 0x80) != 0)
            {
                mpu_write_data(brush_color);
            } else {
								mpu_write_data(back_color);
			}
            width_index++;
            if (width_index == ch_width)
            {
                width_index = 0;
                height_index++;
                break;
            }
            byte_code <<= 1;
        }
    }
}


void lcd_show_string(uint16_t x, uint16_t y, uint16_t width, uint16_t height, char *str, uint8_t size)
{
    uint8_t ch_width;
    uint8_t ch_height;
    uint16_t x_raw;
    uint16_t y_raw;
    uint16_t x_limit;
    uint16_t y_limit;
    
    switch (size)
    {
        case 12:
        {
            ch_width = 6;
            ch_height = 12;
            break;
        }
        case 16:
        {
            ch_width = 8;
            ch_height = 16;
            break;
        }
        case 24:
        {
            ch_width = 12;
            ch_height = 24;
            break;
        }
        case 32:
        {
            ch_width = 16;
            ch_height = 32;
            break;
        }
        default:
        {
            return;
        }
    }
    
    x_raw = x;
    y_raw = y;
    x_limit = ((x + width + 1) > LCD_WIDTH) ? LCD_WIDTH : (x + width + 1);
    y_limit = ((y + height + 1) > LCD_HEIGHT) ? LCD_HEIGHT : (y + height + 1);
    
    while ((*str >= ' ') && (*str <= '~'))
    {
        if (x + ch_width >= x_limit)
        {
            x = x_raw;
            y += ch_height;
        }
        
        if (y + ch_height >= y_limit)
        {
            y = x_raw;
            x = y_raw;
        }
        
        lcd_show_char(x, y, *str, size);
        
        x += ch_width;
        str++;
    }
}
