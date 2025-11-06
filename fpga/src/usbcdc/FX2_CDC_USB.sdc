# =====================================================================
# File: FX2_CDC_USB.sdc (v6 - 最终修复版)
# 描述: PnR 报告显示工具推断了多个 "垃圾" 时钟.
#       我们将所有来自这些垃圾时钟的路径设为伪路径.
# =====================================================================

# --- 1. 定义板载 50MHz 系统时钟 ---
create_clock -name clk -period 20.0 [get_ports {clk}]

# --- 2. 定义来自 FX2 的 48MHz 接口时钟 ---
create_clock -name usb_ifclk -period 20.833 [get_ports {usb_ifclk}]

# --- 3. 定义 25MHz CAN 生成时钟 ---
# (我们再次尝试使用 create_generated_clock. 
#  PnR 报告 确认了 u_can_wrapper/canclk_div 的名字, 这次应该会成功)
create_generated_clock -name canclk_div_25M -source [get_ports {clk}] -divide_by 2 [get_nets {u_can_wrapper/canclk_div}]

# --- 4. (关键!) 将 *真实* 时钟域设置为异步 ---
# 我们只关心这 3 个真实时钟之间的关系
set_clock_groups -asynchronous -group [get_clocks {clk}] -group [get_clocks {usb_ifclk}] -group [get_clocks {canclk_div_25M}]

# --- 5. 将异步复位信号 rst_n (输入端口) 设置为伪路径 ---
set_false_path -from [get_ports {rst_n}]

# --- 6. (关键修复!) 禁用所有来自 "垃圾" 时钟的路径 ---
# PnR 报告 显示工具错误地将这些内部网线推断为了主时钟.
# 我们不关心任何 *来自* 这些信号的时序分析.

set_false_path -from [get_nets {u_can_wrapper/u_can_core/u_canc_top/n981_5}]
set_false_path -from [get_nets {u_can_wrapper/u_can_core/u_canc_top/u_canc_0/ponrst_cclk_2_n}]
set_false_path -from [get_nets {gw_gao_inst_0/control0[0]}]


