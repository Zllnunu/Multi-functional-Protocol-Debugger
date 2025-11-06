`resetall

// ============================================================================
// Module: M1SC_MCU_LCD.v
// Description:
//   项目顶层模块，集成了M1软核、AHB1总线上的LCD控制器以及AHB2总线
//   上的SoC功能接口。
//   **已更新**: 重新集成了 adc_preview_test 模块以进行静态波形显示测试。
// ============================================================================
module M1SC_MCU_LCD(
    // M1 Core General I/O
    output        LOCKUP,
    output        HALTED,
    inout  [15:0] GPIO,
    inout         SWDIO,
    inout         SWCLK,
    input         HCLK,      // Global System Clock
    input         hwRstn,    // Global System Reset (active-low)

    // Touch Interface
    inout         SCL,
    inout         SDA,

    // LCD Interface
    output        LCD_CSn,
    output        LCD_RS,
    output        LCD_WRn,
    output        LCD_RDn,
    output        LCD_RSTn,
    output        LCD_BL,
    inout  [15:0] LCD_DATA,

    // UART 调试输出引脚
    output        uart_debug_tx_pin,

    // 数字信号输入的物理引脚
    input         digital_signal_in,

    output [2:0] debug_pins,

  //acm2108

  output [7:0]led,

  //按键切换波形
  input   key_in,
//  input   [7:0] switch,
//    output wire [3:0]  main_mode_select,
//    output wire [11:0] MODE_DDS,

  //ACM2108
  input  [7:0] AD0,
  input  [7:0] AD1,
  output       AD0_CLK,
  output       AD1_CLK,
  output [7:0] DA0_Data, 
  output [7:0] DA1_Data,
  output       DA0_Clk,
  output       DA1_Clk,
	
  //ddr
  output [13:0] O_ddr_addr,
  output [2:0]  O_ddr_ba,
  output        O_ddr_cs_n,
  output        O_ddr_ras_n,
  output        O_ddr_cas_n,
  output        O_ddr_we_n,
  output        O_ddr_clk,
  output        O_ddr_clk_n,
  output        O_ddr_cke,
  output        O_ddr_odt,
  output        O_ddr_reset_n,
  output [1:0]  O_ddr_dqm,
  inout  [15:0] IO_ddr_dq,
  inout  [1:0]  IO_ddr_dqs,
  inout  [1:0]  IO_ddr_dqs_n,
  
  //eth_rx
  input         rgmii_rx_clk_i,
  input  [3:0]  rgmii_rxd,
  input         rgmii_rxdv,
  output        eth_rst_n,
  output        eth_mdc,
  output        eth_mdio,

  //eth_tx

  output    HCLK_out,
  output    clk_50M,
  output    AD_Clk,

  output        rgmii_tx_clk,
  output  [3:0] rgmii_txd,
  output        rgmii_txen





);

wire clk_50M;
wire AD_Clk;

wire HCLK_out = HCLK;

    // **新增: 用于连接调试信号的wire**
    wire [2:0] state_debug_wire;

    // ========================================================================
    // AHB1 Bus Wires (for LCD Controller)
    // ========================================================================
    wire [31:0] AHB1HRDATA;
    wire        AHB1HREADYOUT;
    wire [1:0]  AHB1HRESP;
    wire [1:0]  AHB1HTRANS;
    wire [2:0]  AHB1HBURST;
    wire [3:0]  AHB1HPROT;
    wire [2:0]  AHB1HSIZE;
    wire        AHB1HWRITE;
    wire        AHB1HREADYMUX;
    wire [3:0]  AHB1HMASTER;
    wire        AHB1HMASTLOCK;
    wire [31:0] AHB1HADDR;
    wire [31:0] AHB1HWDATA;
    wire        AHB1HSEL;
    wire        AHB1HCLK;
    wire        AHB1HRESET;

    // ========================================================================
    // AHB2 Bus Wires (for SoC Interface)
    // ========================================================================
    wire [31:0] AHB2HRDATA;
    wire        AHB2HREADY;
    wire [1:0]  AHB2HRESP;
    wire [1:0]  AHB2HTRANS;
    wire [2:0]  AHB2HBURST;
    wire [3:0]  AHB2HPROT;
    wire [2:0]  AHB2HSIZE;
    wire        AHB2HWRITE;
    wire        AHB2HREADYMUX;
    wire [3:0]  AHB2HMASTER;
    wire        AHB2HMASTLOCK;
    wire [31:0] AHB2HADDR;
    wire [31:0] AHB2HWDATA;
    wire        AHB2HSEL;
    wire        AHB2HCLK;
    wire        AHB2HRESET;
    wire        AHB2HREADYOUT;
    assign AHB2HREADYOUT = AHB2HREADY;
    
    // ========================================================================
    // Wires for Inter-Module Connection
    // ========================================================================
    wire [3:0]  main_mode_select_wire;
    wire [11:0] mode_dds_wire;
    wire [31:0] digital_in_data_wire;
    wire        uart_tx_debug_wire;
    
    // --- 连接 Analog Preview Test 模块的信号线 ---
    wire [8:0]  analog_bram_addr_wire;
    wire [7:0]  analog_bram_dout_wire;
    wire        analog_data_ready_wire;
    wire [15:0] decim_control_wire;  //新增的时基调节连接线

      // --- 数字输入链路的信号线 ---
    //wire        test_signal_out_wire;
    wire        digital_meas_start_wire;
    wire        digital_meas_ack_wire;
    wire        digital_meas_ready_wire;
    wire [31:0] digital_period_wire;
    wire [31:0] digital_hightime_wire;

    // --- 数字捕获 (拓展) 链路 ---
    wire        digital_capture_start_wire;
    wire        digital_capture_ack_wire;
    wire        digital_capture_ready_wire; // <-- 现在连接到真实的硬件信号
    wire [4:0]  capture_bram_waddr;
    wire        capture_bram_we;
    wire [31:0] capture_bram_wdata;
    wire [4:0]  capture_bram_raddr;
    wire [31:0] capture_bram_rdata;


    // ========================================================================
    // M1 Soft Core Instantiation
    // ========================================================================
    Gowin_EMPU_M1_Top u_Gowin_EMPU_M1_Top(
        .LOCKUP        (LOCKUP),
        .HALTED        (HALTED),
        .GPIO          (GPIO),
        .JTAG_7        (SWDIO),
        .JTAG_9        (SWCLK),
        .UART0RXD      (1'b0),
        .UART0TXD      (),
        .TIMER0EXTIN   (1'b0),
        .AHB1HRDATA    (AHB1HRDATA),
        .AHB1HREADYOUT (AHB1HREADYOUT),
        .AHB1HRESP     (AHB1HRESP),
        .AHB1HTRANS    (AHB1HTRANS),
        .AHB1HBURST    (AHB1HBURST),
        .AHB1HPROT     (AHB1HPROT),
        .AHB1HSIZE     (AHB1HSIZE),
        .AHB1HWRITE    (AHB1HWRITE),
        .AHB1HREADYMUX (AHB1HREADYMUX),
        .AHB1HMASTER   (AHB1HMASTER),
        .AHB1HMASTLOCK (AHB1HMASTLOCK),
        .AHB1HADDR     (AHB1HADDR),
        .AHB1HWDATA    (AHB1HWDATA),
        .AHB1HSEL      (AHB1HSEL),
        .AHB1HCLK      (AHB1HCLK),
        .AHB1HRESET    (AHB1HRESET),
        .AHB2HRDATA    (AHB2HRDATA),
        .AHB2HREADYOUT (AHB2HREADYOUT),
        .AHB2HRESP     (AHB2HRESP),
        .AHB2HTRANS    (AHB2HTRANS),
        .AHB2HBURST    (AHB2HBURST),
        .AHB2HPROT     (AHB2HPROT),
        .AHB2HSIZE     (AHB2HSIZE),
        .AHB2HWRITE    (AHB2HWRITE),
        .AHB2HREADYMUX (AHB2HREADYMUX),
        .AHB2HMASTER   (AHB2HMASTER),
        .AHB2HMASTLOCK (AHB2HMASTLOCK),
        .AHB2HADDR     (AHB2HADDR),
        .AHB2HWDATA    (AHB2HWDATA),
        .AHB2HSEL      (AHB2HSEL),
        .AHB2HCLK      (AHB2HCLK),
        .AHB2HRESET    (AHB2HRESET),
        .HCLK          (HCLK),
        .hwRstn        (hwRstn),
        .SCL           (SCL),
        .SDA           (SDA)
    );

    // ========================================================================
    // AHB1 Slave Instantiation (LCD Controller)
    // ========================================================================
    AHB_LCD_Controller u_AHB_LCD_Controller (
        .AHB_HRDATA    (AHB1HRDATA),
        .AHB_HREADY    (AHB1HREADYOUT),
        .AHB_HRESP     (AHB1HRESP),
        .AHB_HTRANS    (AHB1HTRANS),
        .AHB_HBURST    (AHB1HBURST),
        .AHB_HPROT     (AHB1HPROT),
        .AHB_HSIZE     (AHB1HSIZE),
        .AHB_HWRITE    (AHB1HWRITE),
        .AHB_HMASTLOCK (AHB1HMASTLOCK),
        .AHB_HMASTER   (AHB1HMASTER),
        .AHB_HADDR     (AHB1HADDR),
        .AHB_HWDATA    (AHB1HWDATA),
        .AHB_HSEL      (AHB1HSEL),
        .AHB_HCLK      (HCLK),
        .AHB_HRESETn   (hwRstn),
        .LCD_CSn       (LCD_CSn),
        .LCD_RS        (LCD_RS),
        .LCD_WRn       (LCD_WRn),
        .LCD_RDn       (LCD_RDn),
        .LCD_RSTn      (LCD_RSTn),
        .LCD_BL        (LCD_BL),
        .LCD_DATA      (LCD_DATA)
    );

    wire analog_preview_start_wire;
    wire analog_data_ack_wire;


    // ========================================================================
    // AHB2 Slave Instantiation (SoC Interface Module)
    // ========================================================================
    AHB2_SoC_Interface u_AHB2_SoC_Interface(
        .HCLK                 (HCLK),
        .AHB2HRESETn          (hwRstn),
        .AHB2HSEL             (AHB2HSEL),
        .AHB2HADDR            (AHB2HADDR),
        .AHB2HTRANS           (AHB2HTRANS),
        .AHB2HWRITE           (AHB2HWRITE),
        .AHB2HWDATA           (AHB2HWDATA),
        .AHB2HRDATA           (AHB2HRDATA),
        .AHB2HREADY           (AHB2HREADY),
        .AHB2HRESP            (AHB2HRESP),
        
        .main_mode_select     (main_mode_select_wire),
        .MODE_DDS             (mode_dds_wire),
        .analog_preview_start (analog_preview_start_wire),
        .analog_data_ready    (analog_data_ready_wire),
        .analog_data_ack      (analog_data_ack_wire),
        .analog_bram_dout     (analog_bram_dout_wire),
        .analog_bram_addr     (analog_bram_addr_wire),
        .analog_decim_val     (decim_control_wire),   //新增的时基调节端口
        .digital_meas_start   (digital_meas_start_wire),
        .digital_meas_ack     (digital_meas_ack_wire),
        .digital_meas_ready   (digital_meas_ready_wire),
        .digital_period_in    (digital_period_wire),
        .digital_hightime_in  (digital_hightime_wire),
        .digital_capture_start(digital_capture_start_wire),
        .digital_capture_ack  (digital_capture_ack_wire),
        .digital_capture_ready(digital_capture_ready_wire), // <-- 不再使用伪造信号
        .capture_bram_raddr   (capture_bram_raddr),
        .capture_bram_rdata   (capture_bram_rdata),
        .digital_in_data      (32'h0),
        .usb_cdc_start   (),
        .uart_tx_debug        (uart_tx_debug_wire)
    );
    


    // ========================================================================
    // Analog Preview Test Module Instantiation
    // ========================================================================
//    adc_preview_test u_adc_preview_test(
//        .clk        (HCLK),
//        .reset_n    (hwRstn),
//        .bram_addr  (analog_bram_addr_wire),
//        .bram_dout  (analog_bram_dout_wire),
//        .data_ready (analog_data_ready_wire)
//    );

assign led[0] = analog_preview_start_wire;
// 原来的：
// 把“任意一次上升沿就点亮”改为“累计两次上升沿才点亮”

// 原直连：
// assign led[1] = analog_data_ack_wire;
// assign led[2] = analog_data_ready_wire;

reg        led1_latch, led2_latch;
reg        ack_d, ready_d;               // 上一拍采样
reg [1:0]  ack_edge_cnt, ready_edge_cnt; // 上升沿计数（饱和计数）

assign led[1] = led1_latch;
assign led[2] = led2_latch;

always @(posedge HCLK or negedge hwRstn) begin
    if (!hwRstn) begin
        ack_d          <= 1'b0;
        ready_d        <= 1'b0;
        led1_latch     <= 1'b0;
        led2_latch     <= 1'b0;
        ack_edge_cnt   <= 2'd0;
        ready_edge_cnt <= 2'd0;
    end else begin
        // 保存上一拍
        ack_d   <= analog_data_ack_wire;
        ready_d <= analog_data_ready_wire;

        // 上升沿检测
        if (analog_data_ack_wire & ~ack_d) begin
            // 第二次上升沿时点亮
            if (ack_edge_cnt == 2'd1)
                led1_latch <= 1'b1;
            // 计数饱和到2，避免溢出
            if (ack_edge_cnt != 2'd2)
                ack_edge_cnt <= ack_edge_cnt + 2'd1;
        end

        if (analog_data_ready_wire & ~ready_d) begin
            if (ready_edge_cnt == 2'd1)
                led2_latch <= 1'b1;
            if (ready_edge_cnt != 2'd2)
                ready_edge_cnt <= ready_edge_cnt + 2'd1;
        end
    end
end

assign led[3] = analog_bram_addr_wire;
assign led[4] = analog_bram_dout_wire;
assign led[5] = 0;
assign led[6] = 0;
assign led[7] = 0;

  acm2108 u_acm2108 (
  // 时钟复位（与 AHB2/M1 域一致）
  .HCLK    (HCLK),
  .reset_n (hwRstn),

  // ADC 物理口（你顶层已声明）
  .AD0     (AD0),
  .AD1     (AD1),
  .AD0_CLK (AD0_CLK),
  .AD1_CLK (AD1_CLK),

  // 以太网 RGMII 物理口（保持你现有连法）
  .rgmii_rx_clk_i (rgmii_rx_clk_i),
  .rgmii_rxd      (rgmii_rxd),
  .rgmii_rxdv     (rgmii_rxdv),
  .rgmii_tx_clk   (rgmii_tx_clk),
  .rgmii_txd      (rgmii_txd),
  .rgmii_txen     (rgmii_txen),
  .eth_rst_n      (eth_rst_n),
  .eth_mdc        (eth_mdc),
  .eth_mdio       (eth_mdio),

  // DDR3 物理口（如你现有设计仍需暴露，保持贯通）
  .O_ddr_addr     (O_ddr_addr),
  .O_ddr_ba       (O_ddr_ba),
  .O_ddr_cs_n     (O_ddr_cs_n),
  .O_ddr_ras_n    (O_ddr_ras_n),
  .O_ddr_cas_n    (O_ddr_cas_n),
  .O_ddr_we_n     (O_ddr_we_n),
  .O_ddr_clk       (O_ddr_clk),
  .O_ddr_clk_n     (O_ddr_clk_n),
  .O_ddr_cke      (O_ddr_cke),
  .O_ddr_odt      (O_ddr_odt),
  .O_ddr_reset_n  (O_ddr_reset_n),
  .O_ddr_dqm      (O_ddr_dqm),
  .IO_ddr_dq      (IO_ddr_dq),
  .IO_ddr_dqs     (IO_ddr_dqs),
  .IO_ddr_dqs_n   (IO_ddr_dqs_n),

  // DAC 物理口（按你要求，仅靠两条控制线驱动 DDS）
  .DA0_Data (DA0_Data),
  .DA1_Data (DA1_Data),
  .DA0_Clk  (DA0_Clk),
  .DA1_Clk  (DA1_Clk),

  // —— 关键：与 AHB2 握手 + 数据窗口直连 ——
  .main_mode_select     (main_mode_select_wire),
  .MODE_DDS             (mode_dds_wire),
  .analog_preview_start (analog_preview_start_wire),
  .analog_data_ack      (analog_data_ack_wire),
  .analog_data_ready    (analog_data_ready_wire),
  .analog_bram_addr     (analog_bram_addr_wire),
  .analog_bram_dout     (analog_bram_dout_wire),
  .decim_control_wire   (decim_control_wire),
  .clk_50M  (clk_50M),
  .AD_Clk   (AD_Clk),

  // 降频通道选择按键（若顶层无按键，先暂时固定为 0）
  .key0 (key_in)
);


//assign analog_data_ready_wire = 1;

    // ========================================================================
    // Digital Measurement (Basic) Module Instantiation
    // ========================================================================
    digital_measurement_unit u_digital_meas (
        .clk                 (HCLK),
        .reset_n             (hwRstn),
        .start_stop          (digital_meas_start_wire),
        .ack                 (digital_meas_ack_wire),
        .signal_in           (digital_signal_in),
        .measurement_ready   (digital_meas_ready_wire),
        .period_count_out    (digital_period_wire),
        .high_time_count_out (digital_hightime_wire)
    );
    
    
    // ========================================================================
    // **新增**: 数字分析(协议解析)功能模块
    // ========================================================================
    // 1. 实例化“录像机”

    digital_capture_unit u_digital_capture (
        .clk           (HCLK),
        .reset_n       (hwRstn),
        .start_capture (digital_capture_start_wire),
        .ack           (digital_capture_ack_wire),
        .signal_in     (digital_signal_in),
        .capture_ready (digital_capture_ready_wire), 
        .bram_waddr    (capture_bram_waddr),
        .bram_we       (capture_bram_we),
        .bram_wdata    (capture_bram_wdata),
        .debug_state_out (state_debug_wire) 
    );



        // 2. 实例化用于捕获的 BRAM 
    Gowin_DPB capture_bram_dp_instance (
        // --- **核心修正 1**: Port A (Write Port) 连接到 digital_capture_unit ---
        .clka   (HCLK),
        .reseta (~hwRstn),
        .cea    (1'b1),               // Chip Enable for Port A (always on)
        .ocea   (1'b1),               // Output Clock Enable (not critical for write)
        .wrea   (capture_bram_we),    // Write Enable from capture unit
        .ada    (capture_bram_waddr), // Write Address from capture unit
        .dina   (capture_bram_wdata), // Write Data from capture unit
        .douta  (),                   // Write port's output is not used

        // Port B: Read Port (由 AHB2_SoC_Interface 控制)
        .clkb   (HCLK),
        .resetb (~hwRstn),
        .ceb    (1'b1),
        .oceb   (1'b1),
        .wreb   (1'b0), // Read port's write enable must be grounded
        .adb    (capture_bram_raddr),
        .dinb   (32'b0),
        .doutb  (capture_bram_rdata)
    );

    assign uart_debug_tx_pin = uart_tx_debug_wire;

    assign debug_pins = state_debug_wire;

endmodule