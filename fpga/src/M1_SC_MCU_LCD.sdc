//Copyright (C)2014-2025 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.9 (64-bit) 
//Created Time: 2025-10-26 17:39:11
//create_clock -name acm2108_AD0_CLK -period 40 -waveform {0 20} [get_ports {AD0_CLK}]
//create_clock -name acm2108_clk_ddr_ref -period 5 -waveform {0 2.5} [get_nets {u_acm2108/clk_ddr_ref}]
create_clock -name rgmii_rx_clk_i -period 8 -waveform {0 4} [get_ports {rgmii_rx_clk_i}]
//create_clock -name acm2108_clk_50M -period 20 -waveform {0 10} [get_nets {u_acm2108/clk_50M}]


create_clock -name usb_ifclk -period 20.833 [get_ports {usb_ifclk}]

# --- 3. 定义 25MHz CAN 生成时钟 ---
# (我们再次尝试使用 create_generated_clock. 
#  PnR 报告 确认了 u_can_wrapper/canclk_div 的名字, 这次应该会成功)





