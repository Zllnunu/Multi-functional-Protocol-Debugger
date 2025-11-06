#include "main.h"
#include "event_handler.h"
#include "fpga_registers.h"
#include "PageDesign.h"
#include "Touch.h"
#include "ui_design_handler.h"

// 引入所有UI元素的定义
#include "Create_Features.h"
#include "wave_output_features.h"
#include "analog_input_features.h"
#include "digital_input_features.h"
#include "usb_cdc_features.h"

// ============================================================================
//  本文件包含了所有UI页面的具体事件处理逻辑。
//  当用户触摸屏幕时，这里的代码将被执行。
// ============================================================================

// 为模拟输入页面创建一个本地的数据缓冲区
static uint8_t waveform_buffer[WAVEFORM_POINTS];

#define CAPTURE_POINTS 1024
static uint8_t capture_buffer[CAPTURE_POINTS];
volatile uint32_t g_debug_word;
// --- 主菜单页面处理 ---
void Handle_Main_Page(void)
{
    static uint8_t touch_processed = 0;
    GT1151_Scan(&Touch_LCD, 1);

    if (Touch_LCD.Touch_Num > 0 && !touch_processed)
    {
        // 1. 波形输出按钮
        if (Judge_TpXY(Touch_LCD, Wave_Generate.Box)) {
            currentPage = PAGE_WAVE_OUTPUT;
            MODE_SELECT_REG = MODE_WAVEFORM_OUTPUT;
            Display_Wave_out();
        }
        // 2. 模拟输入按钮
        else if (Judge_TpXY(Touch_LCD, Analog_Input.Box)) {
            currentPage = PAGE_ANALOG_INPUT;
            MODE_SELECT_REG = MODE_ANALOG_INPUT;
            Display_Analog_in();
        }
        // 3. 数字输入按钮
        else if (Judge_TpXY(Touch_LCD, Digital_Input.Box)) {
            currentPage = PAGE_DIGITAL_INPUT;
            MODE_SELECT_REG = MODE_DIGITAL_INPUT;
            Display_Digital_in();
        }
        // 4. USB CDC 按钮 (功能待定)
        else if (Judge_TpXY(Touch_LCD, USB_CDC.Box)) {
                        // 1. 设置状态和FPGA模式
            currentPage = PAGE_USB_CDC;
            MODE_SELECT_REG = MODE_USB_CDC;           
            // 2. (新) 显示加载动画
            Display_Loading_Screen("USB CDC Module");           
            // 3. (新) 软件延时 (等待 1000ms)
            mcu_sw_delay_ms(1000);            
            // 4. (新) 绘制最终的子页面
            Display_USB_CDC();
        }
        touch_processed = 1;
    }
    else if(Touch_LCD.Touch_Num == 0) {
        touch_processed = 0;
    }
}


// --- 波形输出页面处理  ---
void Handle_Wave_Out_Page(void)
{
    static uint8_t touch_processed = 0;
    
    // 使用静态变量保存参数状态
    static uint32_t wave_type = WAVE_TYPE_SINE;
    static uint32_t freq_code = FREQ_1_25K;
    static uint32_t amp_code  = AMP_100_PERCENT;
    static uint32_t duty_code = DUTY_50_PERCENT;
    
    // 运行状态标志，0=停止, 1=运行
    static uint8_t is_running = 0;

    GT1151_Scan(&Touch_LCD, 1);

    if (Touch_LCD.Touch_Num > 0 && !touch_processed)
    {
        // --- 优先处理高优先级按钮 ---
        if (Judge_TpXY(Touch_LCD, Out_Exit.Box)) {
            is_running = 0; // 退出时重置状态
            currentPage = PAGE_MAIN;
            MODE_SELECT_REG = MODE_EXIT_TO_MAIN;
            Display_Main_board();
            touch_processed = 1; // 在返回前设置标志
            return;
        }
        
        // --- Start/Stop 状态切换按钮 ---
        else if (Judge_TpXY(Touch_LCD, Output_Start.Box)) {
            if (!is_running) { // 仅在停止状态下才响应
                is_running = 1;
                // 1. 立即重绘按钮以显示新状态
                Draw_Button_Effect(Output_Start);
                Draw_Normal_Button(Output_Stop);
                // 2. 发送当前的启动命令
                uint32_t reg_val = 0;
                reg_val |= (wave_type << DDS_WAVE_TYPE_Pos);
                reg_val |= (freq_code << DDS_FREQ_SELECT_Pos);
                reg_val |= (amp_code  << DDS_AMP_SELECT_Pos);
                reg_val |= (duty_code << DDS_DUTY_SELECT_Pos);
                DDS_CONTROL_REG = reg_val;
            }
        }
        else if (Judge_TpXY(Touch_LCD, Output_Stop.Box)) {
            if (is_running) { // 仅在运行状态下才响应
                is_running = 0;
                // 1. 立即重绘按钮以显示新状态
                Draw_Normal_Button(Output_Start);
                Draw_Button_Effect(Output_Stop);
                // 2. 直接发送暂停命令
                DDS_CONTROL_REG = 0xFFFFFFFF;
            }
        }
        
        // --- 参数调节按钮 ---
        else 
        {
            uint8_t settings_changed = 0; // 仅用于标记参数是否变动
            if (Judge_TpXY(Touch_LCD, Wave_Switch.Box)) {
                wave_type = (wave_type + 1) % (WAVE_TYPE_MAX + 1);
                settings_changed = 1;
            }
            else if (Judge_TpXY(Touch_LCD, Frequency_up.Box)) {
                if (freq_code < FREQ_MAX_CODE) freq_code++;
                settings_changed = 1;
            }
            else if (Judge_TpXY(Touch_LCD, Frequency_down.Box)) {
                if (freq_code > 0) freq_code--;
                settings_changed = 1;
            }
            else if (Judge_TpXY(Touch_LCD, Voltage_up.Box)) {
                if (amp_code > 0) amp_code--;
                settings_changed = 1;
            }
            else if (Judge_TpXY(Touch_LCD, Voltage_down.Box)) {
                if (amp_code < AMP_MAX_CODE) amp_code++;
                settings_changed = 1;
            }
            else if (Judge_TpXY(Touch_LCD, PWM_up.Box)) {
                if (duty_code > 0) duty_code--;
                settings_changed = 1;
            }
            else if (Judge_TpXY(Touch_LCD, PWM_down.Box)) {
                if (duty_code < DUTY_MAX_CODE) duty_code++;
                settings_changed = 1;
            }

            // 如果参数被更改
            if (settings_changed) {
                // 1. 总是更新UI显示
                Update_Waveform_Display(wave_type, freq_code, amp_code, duty_code);
                
                // 2. 只有在“运行”状态下，才向FPGA发送更新后的控制字
                if (is_running) {
                    uint32_t reg_val = 0;
                    reg_val |= (wave_type << DDS_WAVE_TYPE_Pos);
                    reg_val |= (freq_code << DDS_FREQ_SELECT_Pos);
                    reg_val |= (amp_code  << DDS_AMP_SELECT_Pos);
                    reg_val |= (duty_code << DDS_DUTY_SELECT_Pos);
                    DDS_CONTROL_REG = reg_val;
                }
            }
        }

        touch_processed = 1;
    }
    else if (Touch_LCD.Touch_Num == 0) {
        touch_processed = 0;
    }
}



/* --- 模拟输入页面处理 --- */


// T/Div 显示值 (单位: us)
const uint32_t time_div_options_us[] = {
    10, 20, 50, 100, 200, 500,       // us 档位
    1000, 2000, 5000, 10000, 20000   // us (代表 1ms, 2ms, 5ms, 10ms, 20ms)
};
// 对应的 FPGA 降采样计数值 (cnt)
const uint32_t time_div_decim_cnt[] = {
    5, 10, 25, 50, 100, 250,         // 对应 us 档位
    500, 1000, 2500, 5000, 10000     // 对应 ms 档位 (10000 对应 20ms/div)
};
// 最大索引
const int time_div_max_index = (sizeof(time_div_options_us)/sizeof(uint32_t)) - 1;

const uint16_t v_div_options_mv[]  = {100, 200, 500, 1000, 2000}; // 100mV, 200mV, 500mV, 1V, 2V


void Handle_Analog_In_Page(void)
{
    static uint8_t is_running = 0;
    static uint8_t touch_processed = 0;
    static uint8_t buffer_is_valid = 0;

    static int v_div_index = 3; // 默认档位 1000mV (1.0V)/div
    static int time_div_index = 6; // ★ 默认档位 1ms/div (cnt=500)

    GT1151_Scan(&Touch_LCD, 1);
    if (Touch_LCD.Touch_Num > 0 && !touch_processed)
    {
        uint8_t settings_changed = 0;

        if (Judge_TpXY(Touch_LCD, Analog_Exit.Box)) {
            is_running = 0;
            ANALOG_CONTROL_REG = 0;
            currentPage = PAGE_MAIN;
            MODE_SELECT_REG = MODE_EXIT_TO_MAIN;
            Display_Main_board();
        }
        else if (Judge_TpXY(Touch_LCD, Analog_Start.Box)) {
            if (!is_running) {
                is_running = 1;
								// ★ 新增：启动时必须写入当前时基值 ★
                ANALOG_DECIM_REG = time_div_decim_cnt[time_div_index];
                ANALOG_CONTROL_REG = (1U << ANALOG_CTRL_START_STOP_Pos);
                Draw_Button_Effect(Analog_Start);
                Draw_Normal_Button(Analog_Stop);
            }
        }
        else if (Judge_TpXY(Touch_LCD, Analog_Stop.Box)) {
            if (is_running) {
                is_running = 0;
                ANALOG_CONTROL_REG = 0;
                Draw_Normal_Button(Analog_Start);
                Draw_Button_Effect(Analog_Stop);
            }
        }
        else if (Judge_TpXY(Touch_LCD, Analog_V_up.Box)) {
            if (v_div_index > 0) v_div_index--;
            settings_changed = 1;
        }
        else if (Judge_TpXY(Touch_LCD, Analog_V_down.Box)) {
            if (v_div_index < V_DIV_LEVELS - 1) v_div_index++;
            settings_changed = 1;
        }
				        // ★★★ 新增：时基调节按钮处理 ★★★
        else if (Judge_TpXY(Touch_LCD, Analog_Freq_up.Box)) { // "Time+" 按钮
            if (time_div_index > 0) time_div_index--; // T/Div 减小 (采样加快)
            settings_changed = 1;
        }
        else if (Judge_TpXY(Touch_LCD, Analog_Freq_down.Box)) { // "Time-" 按钮
            if (time_div_index < time_div_max_index) time_div_index++; // T/Div 增大 (采样减慢)
            settings_changed = 1;
        }
        else if (Judge_TpXY(Touch_LCD, Analog_Reset.Box)) {
            v_div_index = 3;
            time_div_index = 6; // 恢复默认 1ms/div
            settings_changed = 1;
        }

        if (settings_changed) {
						// ★ 新增：只要设置变化，就写入新的时基值 ★
            ANALOG_DECIM_REG = time_div_decim_cnt[time_div_index];
					
            Update_Analog_Display(v_div_options_mv[v_div_index], time_div_options_us[time_div_index]);

            if (buffer_is_valid) {
                Draw_Scope_Grid(Analog_WaveBoard);
                Draw_Scope_Waveform(waveform_buffer, WAVEFORM_POINTS, Analog_WaveBoard, v_div_options_mv[v_div_index]);
            }
        }

        touch_processed = 1;
    }
    else if (Touch_LCD.Touch_Num == 0) {
        touch_processed = 0;
    }

		// ===================================================================
    // ★★★ 核心修改：软件自动重启轮询 ★★★
    // ===================================================================
    if (is_running)
    {
        // 轮询，等待FPGA数据就绪
        if (ANALOG_STATUS_REG & ANALOG_STATUS_DATA_READY_Msk)
        {
            // 1) 读出 512 个点（0..511）
            for (int i = 0; i < WAVEFORM_POINTS; i++) {
                waveform_buffer[i] = ANALOG_DATA_BUFFER[i];
            }

            // 2) ★ 简化版握手：START|ACK → START ★
            //    我们仍然执行这个握手，因为它在“第一帧”是有效的，
            //    并且能清除掉 READY 信号。
            #if defined(__arm__) || defined(__ARM_ARCH)
            uint32_t __primask = __get_PRIMASK();
            __disable_irq();               // 保持临界区，确保两次写入不会被中断打断
            #endif

            // 第一次写：START|ACK
            ANALOG_CONTROL_REG =
                (1U << ANALOG_CTRL_START_STOP_Pos) |
                (1U << ANALOG_CTRL_ACK_DATA_Pos);
            
            // 架构屏障（可选，但保留）
            #if defined(__arm__) || defined(__ARM_ARCH)
            __DSB(); __ISB();
            #endif

            // 第二次写：仅 START（ACK 归 0）
            ANALOG_CONTROL_REG = (1U << ANALOG_CTRL_START_STOP_Pos);

            #if defined(__arm__) || defined(__ARM_ARCH)
            if (!__primask) __enable_irq();
            #endif


            // 3) 等 READY 被硬件清 0（确认 FPGA 吃到 ACK）
            {
                uint32_t spin = 0;
                const uint32_t SPIN_MAX = 200000;   
                while ((ANALOG_STATUS_REG & ANALOG_STATUS_DATA_READY_Msk) && (spin++ < SPIN_MAX)) {
                    // 自旋等待 READY 信号被（希望是）ACK清除
                }
            }
            
            // 4) 刷新显示 (在ACK之后)
            Draw_Scope_Grid(Analog_WaveBoard);
            Draw_Scope_Waveform(
                waveform_buffer,
                WAVEFORM_POINTS,
                Analog_WaveBoard,
                v_div_options_mv[v_div_index]
            );
            buffer_is_valid = 1;


            // ================================================================
            // ★ 新增：软件“自动重启”方案 ★
            // 无论上面的ACK握手是否成功复位了FPGA的wptr,
            // 我们都在这里强制模拟一次 STOP -> START 周期。
            // 这将利用发现的“START/STOP能刷新”的现象来确保下一帧被触发。
            // ================================================================

            // 步骤1: 模拟按下 "STOP"
            ANALOG_CONTROL_REG = 0;

            // 步骤2: 模拟按下 "START"
            // (这会重新触发FPGA开始采集。is_running 标志位仍然为1,
            // 所以下一次轮询会等待这个新采集的帧)
						ANALOG_DECIM_REG = time_div_decim_cnt[time_div_index];
            ANALOG_CONTROL_REG = (1U << ANALOG_CTRL_START_STOP_Pos);
        }
    }
}



// --- 数字输入页面处理  ---
void Handle_Digital_In_Page(void)
{
	
    static uint8_t touch_processed = 0;
    static uint8_t is_measuring = 0;
    static DigitalMode_t current_mode = DIGITAL_MODE_MEASURE;
	
    static uint8_t current_freq_code = 1; // 默认 50k
    static uint8_t current_baud_code = 0; // 默认 9600 (索引 0)
	
    static EncodingType_t current_encoding = ENCODE_NRZ_L; 

    GT1151_Scan(&Touch_LCD, 1);
    
    // --- 1. 触摸处理逻辑 ---
    if (Touch_LCD.Touch_Num > 0 && !touch_processed)
    {
        // --- 1.1 退出与模式切换 (无修改) ---
        if (Judge_TpXY(Touch_LCD, Digital_Exit.Box)) {
            is_measuring = 0;
            if (current_mode == DIGITAL_MODE_MEASURE) {
                DIGITAL_CONTROL_REG = 0;
            } else {
                DIGITAL_CAPTURE_CONTROL_REG = 0;
            }
            currentPage = PAGE_MAIN;
            MODE_SELECT_REG = MODE_EXIT_TO_MAIN;
            Display_Main_board();
            touch_processed = 1; 
            return;
        }
        else if (Judge_TpXY(Touch_LCD, Digital_Mode_Measure.Box)) {
            if (current_mode != DIGITAL_MODE_MEASURE) {
                current_mode = DIGITAL_MODE_MEASURE;
                is_measuring = 0; 
                DIGITAL_CAPTURE_CONTROL_REG = 0; 
                Display_Digital_in_MeasureMode();
            }
        }
        else if (Judge_TpXY(Touch_LCD, Digital_Mode_Analyze.Box)) {
            if (current_mode != DIGITAL_MODE_ANALYZE) {
                current_mode = DIGITAL_MODE_ANALYZE;
                is_measuring = 0; 
                DIGITAL_CONTROL_REG = 0; 
                Display_Digital_in_AnalyzeMode();
            }
        }
        // --- 1.2 控制按钮 ---
        else {
            if (current_mode == DIGITAL_MODE_MEASURE) {
                // ... (测量模式的 RUN/STOP 逻辑不变) ...
                if (Judge_TpXY(Touch_LCD, Digital_Start.Box)) {
                    if (!is_measuring) {
                        is_measuring = 1;
                        DIGITAL_CONTROL_REG = (1U << DIGITAL_CTRL_START_STOP_Pos);
                        Draw_Button_Effect(Digital_Start);
                        Draw_Normal_Button(Digital_Pause);
                    }
                }
                else if (Judge_TpXY(Touch_LCD, Digital_Pause.Box)) {
                    if (is_measuring) {
                        is_measuring = 0;
                        DIGITAL_CONTROL_REG = 0;
                        Draw_Normal_Button(Digital_Start);
                        Draw_Button_Effect(Digital_Pause);
                    }
                }
            } else { // current_mode == DIGITAL_MODE_ANALYZE
							
                // --- "分析模式"的按钮逻辑 ---                
                // ** 核心 2: 编码选择按钮 (智能化 UI) **
                if (Judge_TpXY(Touch_LCD, Encoding_Select_Button.Box)) {
                     current_encoding = (EncodingType_t)((current_encoding + 1) % ENCODE_TYPE_COUNT);
                     sprintf(Encoding_Select_Button.Text[0], "%s", ENCODING_NAMES[current_encoding]); 
                     Draw_Normal_Button(Encoding_Select_Button);
                     
                     // ** 智能切换 Freq/Baud 按钮的显示 **
                     if (current_encoding == ENCODE_UART) {
                         sprintf(Freq_Select_Button.Text[0], "%s", UART_BAUD_NAMES[current_baud_code]);
                     } else {
                         sprintf(Freq_Select_Button.Text[0], "%s", FREQ_NAMES[current_freq_code]);
                     }
                     Draw_Normal_Button(Freq_Select_Button);
                }
                
                // ** 核心 3: 频率/波特率选择按钮 (智能化) **
                else if (Judge_TpXY(Touch_LCD, Freq_Select_Button.Box)) {
                    // (A) 如果是 UART 模式, 循环波特率
                    if (current_encoding == ENCODE_UART) {
                        current_baud_code = (current_baud_code + 1) % UART_BAUD_LEVELS;
                        sprintf(Freq_Select_Button.Text[0], "%s", UART_BAUD_NAMES[current_baud_code]);
                    } 
                    // (B) 否则, 循环频率
                    else {
                        current_freq_code = (current_freq_code + 1) % FREQ_LEVELS;
                        sprintf(Freq_Select_Button.Text[0], "%s", FREQ_NAMES[current_freq_code]);
                    }
                     Draw_Normal_Button(Freq_Select_Button);
                }
                
                // (3) 处理 Start 按钮 (无修改)
                else if (Judge_TpXY(Touch_LCD, Digital_Start.Box)) {
                    if (!is_measuring) {
                        is_measuring = 1;
                        DIGITAL_CAPTURE_CONTROL_REG = (1U << CAPTURE_CTRL_ACK_Pos);
                        DIGITAL_CAPTURE_CONTROL_REG = 0;
                        DIGITAL_CAPTURE_CONTROL_REG = (1U << CAPTURE_CTRL_START_STOP_Pos);
                        
                        Draw_Button_Effect(Digital_Start);
                        Draw_Normal_Button(Digital_Pause);
                        Draw_Text_Boundary(Digital_Analyze_Result, " Analyzing... (Waiting for signal)");
                    }
                }
                // (4) 处理 Stop 按钮 (无修改)
                else if (Judge_TpXY(Touch_LCD, Digital_Pause.Box)) {
                    if (is_measuring) {
                        is_measuring = 0;
                        DIGITAL_CAPTURE_CONTROL_REG = 0; 
                        Draw_Normal_Button(Digital_Start);
                        Draw_Button_Effect(Digital_Pause);
                        Draw_Text_Boundary(Digital_Analyze_Result, " Ready to analyze...");
                    }
                }
            }
        }
        touch_processed = 1; 
    }
    // --- 1.3 触摸释放 (无修改) ---
    else if(Touch_LCD.Touch_Num == 0) {
        touch_processed = 0;
    }

    // --- 2. 轮询逻辑 (Polling Logic) (无修改) ---
    if (is_measuring) {
        if (current_mode == DIGITAL_MODE_MEASURE) {
            // ... (测量模式轮询不变) ...
            if (DIGITAL_STATUS_REG & DIGITAL_STATUS_READY_Msk)
            {
                uint32_t period_raw = DIGITAL_PERIOD_REG;
                uint32_t high_time_raw = DIGITAL_HIGH_TIME_REG;

                DIGITAL_CONTROL_REG = (1U << DIGITAL_CTRL_START_STOP_Pos) | (1U << DIGITAL_CTRL_ACK_Pos);
                DIGITAL_CONTROL_REG = (1U << DIGITAL_CTRL_START_STOP_Pos);

                uint32_t frequency_hz = 0;
                uint32_t duty_percent = 0;
                uint32_t high_time_ns = 0;
                uint32_t low_time_ns = 0;

                if (period_raw > 0) {
                    frequency_hz = 50000000 / period_raw;
                    duty_percent = (uint64_t)high_time_raw * 100 / period_raw;
                    high_time_ns = high_time_raw * 20;
                    low_time_ns  = (period_raw - high_time_raw) * 20;
                }
                
                Update_Digital_Display(frequency_hz, duty_percent, high_time_ns, low_time_ns);
            }
        } else { 
			// --- “分析模式”的数据轮询 (无修改) ---
            if (DIGITAL_CAPTURE_STATUS_REG & CAPTURE_STATUS_READY_Msk) {
                
                volatile uint32_t* bram_ptr = (volatile uint32_t*)DIGITAL_CAPTURE_BUFFER;

                for (int i = 0; i < CAPTURE_POINTS / 32; i++) {
                    volatile uint32_t word = bram_ptr[i];
                     g_debug_word = word; 
                    for (int j = 0; j < 32; j++) {
                        capture_buffer[i * 32 + j] = (word >> j) & 0x01;
                    }
                }
                
                DIGITAL_CAPTURE_CONTROL_REG = (1U << CAPTURE_CTRL_ACK_Pos);
                DIGITAL_CAPTURE_CONTROL_REG = 0; 
                
                Analyze_and_Display_Signal(capture_buffer, CAPTURE_POINTS, current_freq_code, current_baud_code, current_encoding);

                is_measuring = 0; 
                Draw_Normal_Button(Digital_Start);
                Draw_Button_Effect(Digital_Pause);
            }
        }
    }
}

// --- USB_CDC页面处理  ---
void Handle_USB_CDC_Page(void)
{
    static uint8_t is_running = 0; // 0=Stop, 1=Start
    static uint8_t touch_processed = 0;

    GT1151_Scan(&Touch_LCD, 1);
    if (Touch_LCD.Touch_Num > 0 && !touch_processed)
    {
        // 1. 退出按钮
        if (Judge_TpXY(Touch_LCD, USB_CDC_Exit.Box)) {
            is_running = 0;
            USB_CDC_CONTROL_REG = 0; // 确保退出时关闭
            currentPage = PAGE_MAIN;
            MODE_SELECT_REG = MODE_EXIT_TO_MAIN;
            Display_Main_board();
        }
        // 2. Start 按钮
        else if (Judge_TpXY(Touch_LCD, USB_CDC_Start.Box)) {
            if (!is_running) {
                is_running = 1;
                // 告诉FPGA，M1
                // 允许 CDC 模块工作
                USB_CDC_CONTROL_REG = (1U << USB_CDC_CTRL_START_STOP_Pos);
                // 更新按钮UI
                Draw_Button_Effect(USB_CDC_Start);
                Draw_Normal_Button(USB_CDC_Stop);
            }
        }
        // 3. Stop 按钮
        else if (Judge_TpXY(Touch_LCD, USB_CDC_Stop.Box)) {
            if (is_running) {
                is_running = 0;
                // 告诉FPGA，M1
                // 停止 CDC 模块
                USB_CDC_CONTROL_REG = 0;
                // 更新按钮UI
                Draw_Normal_Button(USB_CDC_Start);
                Draw_Button_Effect(USB_CDC_Stop);
            }
        }
        
        touch_processed = 1;
    }
    else if(Touch_LCD.Touch_Num == 0) {
        touch_processed = 0;
    }

    // (注意：此页面没有轮询逻辑，因为M1不参与数据传输)
}

