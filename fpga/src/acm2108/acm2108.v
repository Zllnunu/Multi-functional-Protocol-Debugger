// ============================================================================
// acm2108.v  —  顶层（集成降频采样 → 512x8 BRAM → AHB2），不接 DDR3
// 要点：
//  1) ADC 统一用 25MHz@270° 采样时钟（由 pll_decim 产生）
//  2) 降频模块独立，输出直接连 AHB2（START/READY/ACK + 512B 窗口）
//  3) 以太网链保持原逻辑（你后续把它的 ADC 时钟也接到 25MHz@270°）
//  4) 降频通道选择：使用按键 key0（不改 M1，不改 AHB2）
//  5) 不经 DDR3，避免时序干扰
//
// 使用说明：
//  - 以 // [HOOK] 标注的地方，用你的原始信号名替换；
//  - 以 // [NEW] 标注的地方为新增代码；
//  - “ADC前端输出形态”三选一（见 [A/B/C]）——把与你工程一致的那段取消注释，其余注释掉。
// ============================================================================

`timescale 1ns/1ps
module acm2108 (
    // ====== 系统/外设时钟复位 ======
    input  wire        HCLK,           // 系统时钟（M1/AHB2域）
    input  wire        reset_n,        // 全局复位，低有效

    // ====== ADC 芯片接口 ======
    input  wire [7:0]  AD0,            // [HOOK] 如你原来使用 8位并行ADC输入
    input  wire [7:0]  AD1,            // [HOOK]
    output wire        AD0_CLK,        // ADC 时钟输出给芯片（25MHz@270°）
    output wire        AD1_CLK,        // 同上

    // ====== 以太网/RGMII（保持原连接）======
    input  wire        rgmii_rx_clk_i, // [HOOK] 你的以太网既有端口，原封不动
    input  wire [3:0]  rgmii_rxd,
    input  wire        rgmii_rxdv,
    output wire        rgmii_tx_clk,
    output wire [3:0]  rgmii_txd,
    output wire        rgmii_txen,
    output wire        eth_rst_n,
    output wire        eth_mdc,
    inout  wire        eth_mdio,

    // ====== DDR3（保持原连接）======
    output wire [13:0] O_ddr_addr,     // [HOOK] 原样保留
    output wire [2:0]  O_ddr_ba,
    output wire        O_ddr_cs_n,
    output wire        O_ddr_ras_n,
    output wire        O_ddr_cas_n,
    output wire        O_ddr_we_n,
    output wire        O_ddr_clk,
    output wire        O_ddr_clk_n,
    output wire        O_ddr_cke,
    output wire        O_ddr_odt,
    output wire        O_ddr_reset_n,
    output wire [1:0]  O_ddr_dqm,
    inout  wire [15:0] IO_ddr_dq,
    inout  wire [1:0]  IO_ddr_dqs,
    inout  wire [1:0]  IO_ddr_dqs_n,

    // ====== DAC（若有则保留）======
    output wire [7:0]  DA0_Data,       // [HOOK] 你之前已接好的 DAC 口
    output wire [7:0]  DA1_Data,
    output wire        DA0_Clk,
    output wire        DA1_Clk,

    // ====== AHB2 / M1 侧寄存器口（关键：降频桥直连）======
    input  wire [3:0]  main_mode_select,       // 模式选择，M1 写
    input  wire [11:0] MODE_DDS,               // DDS 配置，M1 写（保持原用）
    input  wire        analog_preview_start,   // START（ANALOG_CONTROL bit0）
    input  wire        analog_data_ack,        // ACK   （ANALOG_CONTROL bit1）
    output wire        analog_data_ready,      // READY （ANALOG_STATUS bit0）
    input  wire [8:0]  analog_bram_addr,       // DATA BUFFER 地址 0..511
    output wire [7:0]  analog_bram_dout,       // DATA BUFFER 读数据
    input  wire [15:0] decim_control_wire,

    output clk_50M,
    output AD_Clk,

    // ====== 按键/LED（用于降频通道选择）======
    input  wire        key0                   // [NEW] 降频通道选择按键
    // output wire [7:0]  led                     // [HOOK] 仍可作为调试
);
    // =========================================================================
    // 0) 25MHz@270° 采样时钟 —— 供 ADC 芯片 + 前端链路 + 降频链路统一使用
    //    你已提供 pll_decim 的模板，这里实例化并输出到 AD0_CLK/AD1_CLK
    // =========================================================================
    wire pll_lock_decim;
    wire adc_clk_25m;       // 25MHz@270°
    // [HOOK] 参考时钟与复位，如无独立参考，可以用 HCLK/上电复位
    wire pll_ref_clk = HCLK;          // 或者板载 50MHz/25MHz 参考
    wire pll_reset_n = reset_n;
    wire pll_enclk0  = 1'b1;
    wire Clk = HCLK;
    wire clk = HCLK;
    wire HRESETn = reset_n;
//        pll_decim u_pll_decim (
//        .lock   (pll_lock_decim),     // output
//        .clkout0(adc_clk_25m),        // output 25MHz（在 IP 里配置 270° 相位）
//        .clkin  (pll_ref_clk),        // input
//        .reset  (~pll_reset_n),       // input (高有效)
//        .enclk0 (pll_enclk0)          // input
//    );
  

  //Set IMAGE Size  
  parameter LOCAL_MAC  = 48'h00_0a_35_01_fe_c0;
  parameter LOCAL_IP   = 32'hc0_a8_00_02;
  parameter LOCAL_PORT = 16'd5000;
  
  // -------------------- 内部连线 --------------------
  // eth_rx
  wire          rgmii_rx_clk;
  wire          gmii_rx_clk;
  wire  [7:0]   gmii_rxd;
  wire          gmii_rxdv;
  wire          clk125m_o;
  wire  [7:0]   payload_dat_o;
  wire          payload_valid_o;
  wire          one_pkt_done;

  // fifo_rx
  wire          rx_empty;
  wire          fifo_rd_req;
  wire  [7:0]   rxdout;

  // rxcmd
  wire          cmdvalid_0;
  wire  [7:0]   address_0;
  wire  [31:0]  cmd_data_0; 

  wire  [7:0]   ChannelSel;
  wire  [31:0]  DataNum;
  wire  [31:0]  ADC_Speed_Set;   
  wire          RestartReq;

  // fifotx
  wire          rdfifo_empty;
  wire          eth_fifo_wrreq;
  wire  [15:0]  eth_fifo_wrdata;
  wire          eth_fifo_tx_empty;
  wire  [10:0]  eth_fifo_usedw;
  wire  [14:0]  rd_data_count;
  wire          payload_req_o;
  wire  [7:0]   dout;

  // eth_tx
  wire          tx_done;
  wire          tx_en_pulse;
  wire  [15:0]  lenth_val;
  wire          gmii_tx_clk;
  wire  [7:0]   gmii_txd;
  wire          gmii_txen;

  // clocks & resets
  wire          clk_50M;       // 除 DDR3 以外模块的时钟
  wire          pll_locked;    // 系统 PLL 锁
  wire          g_reset_50M;
  wire          g_reset_125M;
  wire          g_reset_200M;


  wire  [15:0]  ad_out;
  wire          ad_out_valid;

  wire          ddr3_init_done;
  wire          wrfifo_clr;
  wire          wrfifo_full;
  wire          ad_sample_en;
  wire          rdfifo_clr;
  wire          rdfifo_rden;
  wire  [15:0]  rdfifo_dout;

  assign eth_rst_n = 1'b1;
  assign eth_mdc   = 1'b1;
  assign eth_mdio  = 1'b1;

  // ============================================================================
// [NEW] 预览支路：域内复位、按键通道选择、通道选择到降频模块
// ============================================================================

// 1) 采样域时钟（Front-End）：用你给 ADC 芯片的那颗 25MHz@270°
wire adc_clk_fe /* synthesis keep */;
// 如果你的前端时钟网名就是 AD0_CLK/AD1_CLK 的来源，可直接用它；
// 下面默认用 AD0_CLK 这根网（两路同相同频，不影响）
assign adc_clk_fe = AD0_CLK;  // ← 若你的采样域时钟名不同，请替换

// 2) 采样域复位（把系统复位 HRESETn 同步到 adc_clk_fe）
reg rst_adc_ff1, rst_adc_ff2;
wire rst_adc_n /* synthesis keep */;  // 高有效
always @(posedge adc_clk_fe or negedge HRESETn) begin
  if(!HRESETn) begin
    rst_adc_ff1 <= 1'b0;
    rst_adc_ff2 <= 1'b0;
  end else begin
    rst_adc_ff1 <= 1'b1;
    rst_adc_ff2 <= rst_adc_ff1;
  end
end
assign rst_adc_n = rst_adc_ff2;

// 3) key0 在 HCLK 域去抖 → 翻转通道选择位 → 同步到采样域
wire key_flag, key_state;
key_filter u_key0 (
  .Clk      (HCLK),       // 你模块标注“50M”，HCLK域即可
  .Rst_n    (HRESETn),
  .key_in   (key0),
  .key_flag (key_flag),
  .key_state(key_state)
);

// HCLK 域通道选择位：0=CH0(高8位)，1=CH1(低8位)
reg ch_sel_sys;
always @(posedge HCLK or negedge HRESETn) begin
  if(!HRESETn) ch_sel_sys <= 1'b0;
  else if (key_flag) ch_sel_sys <= ~ch_sel_sys;  // 每次按键事件翻转
end

// 同步到采样域
reg ch_sel_a_d1, ch_sel_a_d2;
always @(posedge adc_clk_fe or negedge rst_adc_n) begin
  if(!rst_adc_n) begin
    ch_sel_a_d1 <= 1'b0;
    ch_sel_a_d2 <= 1'b0;
  end else begin
    ch_sel_a_d1 <= ch_sel_sys;
    ch_sel_a_d2 <= ch_sel_a_d1;
  end
end
wire ch_sel_adc = ch_sel_a_d2;

// 4) 预览链路的数据与有效（与以太网完全解耦）
wire ch_sel_preview = (ChannelSel[1:0] == 2'b10) ? 1'b1 : 1'b0; // 1:AD1, 0:AD0
wire [7:0] adc_preview_data = ch_sel_preview ? AD1 : AD0;

// 预览期间在 ADC 域恒为 1，由 dpb 内 decim_cnt 负责抽取
reg allow_prev_a_d1, allow_prev_a_d2;
always @(posedge adc_clk_fe or negedge rst_adc_n) begin
  if(!rst_adc_n) begin
    allow_prev_a_d1 <= 1'b0;
    allow_prev_a_d2 <= 1'b0;
  end else begin
    allow_prev_a_d1 <= allow_preview;   // HCLK 域 preview_active 同步
    allow_prev_a_d2 <= allow_prev_a_d1;
  end
end
wire        adc_valid_25m = allow_prev_a_d2;
wire [7:0]  adc_data_25m  = adc_preview_data;

// 以太网忙门控：由顶层仲裁生成
wire eth_active = eth_in_progress;


  // ================== 时钟生成（系统） ==================
  wire clk125m;
  wire AD_Clk;

  Gowin_PLL u_sys_pll (
    .clkin   (HCLK),
    .clkout0 (clk_50M),  // 50MHz
//    .clkout1 (),         // 未用
    .clkout2 (clk125m),  // 125MHz for ETH
    .clkout3 (AD_Clk),   //25M 270°
    .lock    (pll_locked),
    .reset   (~reset_n)
  );
reg lock_sync1, lock_sync2;
always @(posedge clk_50M or negedge pll_locked) begin
  if (!pll_locked) begin
    lock_sync1 <= 1'b0;
    lock_sync2 <= 1'b0;
  end else begin
    lock_sync1 <= 1'b1;
    lock_sync2 <= lock_sync1;
  end
end

  assign g_reset_50M = ~lock_sync2;
//现在的代码有问题，当连接上以太网的lock和reset信号会导致50M的时钟的时钟只能1.27M
//现在先解决以太网链路问题，然后解决时钟不对的问题，用示波器！！！

//  Gowin_PLL u_sys_pll (
//    .clkin   (HCLK),
//    .clkout0 (clk_50M),  // 50MHz
//    .clkout1 (),         // 未用
//    .clkout2 (clk125m),  // 125MHz for ETH
//    .clkout3 (AD_Clk),   //50M 270°
//    .lock    (pll_locked),
//    .reset   (~reset_n)
//  );
  // ================== 时钟生成（以太网 RX） ==================
  eth_pll u_eth_pll(
    .clkout0 (rgmii_rx_clk),    //125M 270°
    .clkin   (rgmii_rx_clk_i)
  );

reg rst_125M_270_s1, rst_125M_270_s2;
always @(posedge rgmii_rx_clk or posedge g_reset_50M) begin
  if (g_reset_50M) begin
    rst_125M_270_s1 <= 1'b1;
    rst_125M_270_s2 <= 1'b1;
  end else begin
    rst_125M_270_s1 <= 1'b0;
    rst_125M_270_s2 <= rst_125M_270_s1;
  end
end
wire g_reset_125M   = rst_125M_270_s2;

  // ================== DDR 专用 PLL（只有一个 200MHz 输出 → 不门控） ==================
  wire clk_ddr_ref;   // 喂给 DDR3 IP 的参考时钟（200MHz）
  wire ddr_lock;      // DDR PLL 锁（供 IP 使用）
  wire pll_stop;      // 来自 IP 的门控握手（本设计不再用它去关时钟）

  ddr_pll u_ddr_pll(
    .clkin   (clk_50M),
    .enclk0  (1'b1),         // ★ 只有一个输出口，必须常开；不要用 pll_stop 去关
    .clkout0 (clk_ddr_ref),  // ★ 在 IP/PLL 配置里设为 200MHz
    .lock    (ddr_lock),
    .reset   (g_reset_50M)
  );
wire g_reset_200M   = g_reset_50M;
  // ================== 以太网收发（与你原始一致） ==================
  rgmii_to_gmii u_rgmii_to_gmii(
    .reset       (g_reset_125M),
    .rgmii_rx_clk(rgmii_rx_clk),
    .rgmii_rxd   (rgmii_rxd),
    .rgmii_rxdv  (rgmii_rxdv),
    .gmii_rx_clk (gmii_rx_clk),
    .gmii_rxdv   (gmii_rxdv),
    .gmii_rxd    (gmii_rxd),
    .gmii_rxer   ( )
  ); 
    
  eth_udp_rx_gmii u_eth_udp_rx_gmii(
    .reset_p         (g_reset_125M),
    .local_mac       (LOCAL_MAC),
    .local_ip        (LOCAL_IP),
    .local_port      (LOCAL_PORT),
    .clk125m_o       (clk125m_o),   //output
    .exter_mac       (),
    .exter_ip        (),
    .exter_port      (),
    .rx_data_length  (),
    .data_overflow_i (),
    .payload_valid_o (payload_valid_o),
    .payload_dat_o   (payload_dat_o),
    .one_pkt_done    (one_pkt_done),
    .pkt_error       (),
    .debug_crc_check (),
    .gmii_rx_clk     (gmii_rx_clk), //input
    .gmii_rxdv       (gmii_rxdv),
    .gmii_rxd        (gmii_rxd)
  );

  wire g_reset_fifo_rx;
  assign g_reset_fifo_rx = g_reset_125M | g_reset_50M;

  fifo_rx u_fifo_rx(
    .Data   (payload_dat_o),
    .Reset  (g_reset_fifo_rx),
    .WrClk  (clk125m_o),
    .RdClk  (clk_50M),
    .WrEn   (payload_valid_o),
    .RdEn   (fifo_rd_req),
    .Q      (rxdout),
    .Empty  (rx_empty),
    .Full   ()
  );

  eth_cmd u_eth_cmd (
    .clk        (clk_50M),
    .reset_n    (~g_reset_50M),
    .fifo_rd_req(fifo_rd_req),
    .rx_empty   (rx_empty),
    .fifodout   (rxdout),
    .cmdvalid   (cmdvalid_0),
    .address    (address_0),
    .cmd_data   (cmd_data_0)
  );

  cmd_rx u_cmd_rx(
    .clk          (clk_50M),
    .reset_n      (~g_reset_50M),
    .cmdvalid     (cmdvalid_0),
    .cmd_addr     (address_0),
    .cmd_data     (cmd_data_0),
    .ChannelSel   (ChannelSel),
    .DataNum      (DataNum),
    .ADC_Speed_Set(ADC_Speed_Set),
    .RestartReq   (RestartReq)
  );
    
  reg RestartReq_0_d0, RestartReq_0_d1;
  reg [31:0] Number_d0, Number_d1;
  always @(posedge clk125m_o) begin
    Number_d0 <= DataNum;
    Number_d1 <= Number_d0;
    RestartReq_0_d0 <= RestartReq;
    RestartReq_0_d1 <= RestartReq_0_d0;
  end

  wire adc_data_en;
  speed_ctrl u_speed_ctrl(
    .clk         (clk_50M),
    .reset_n     (~g_reset_50M),
    .ad_sample_en(ad_sample_en),
    .adc_data_en (adc_data_en),
    .div_set     (ADC_Speed_Set)
  ); 
  
  
// ========================== PATCH A: 互斥仲裁 + 以太网忙标志 ==========================
// 预览优先：有预览就不允许以太网启动；以太网忙时，预览保持复位&停写。

// 1) 预览活动标志（analog_preview_start 置位，analog_data_ack 清零）
reg prev_start_d, prev_ack_d;
always @(posedge HCLK or negedge HRESETn) begin
  if(!HRESETn) begin
    prev_start_d <= 1'b0;
    prev_ack_d   <= 1'b0;
  end else begin
    prev_start_d <= analog_preview_start;
    prev_ack_d   <= analog_data_ack;
  end
end
wire analog_start_pulse = analog_preview_start & ~prev_start_d;
wire analog_ack_pulse   = analog_data_ack      & ~prev_ack_d;

reg preview_active;
always @(posedge HCLK or negedge HRESETn) begin
  if(!HRESETn) preview_active <= 1'b0;
  else begin
    if (analog_start_pulse) preview_active <= 1'b1;     //analog_start_pulse 降频模块工作
    else if (analog_ack_pulse) preview_active <= 1'b0;  //analog_ack_pulse 以太网工作
                                                        //后面接到start_sample_to_eth信号共同控制
  end
end

// preview_active控制两种状态工作
wire allow_eth     = ~preview_active;
wire allow_preview =  preview_active;

// 2) 以太网真正空闲：不采样、读空、发送 FIFO 空
wire eth_really_idle = (~ad_sample_en) & rdfifo_empty & eth_fifo_tx_empty;

// 3) 以太网 in-progress：启动置位，真正空闲清零
reg eth_in_progress;
always @(posedge HCLK or negedge HRESETn) begin
  if(!HRESETn) eth_in_progress <= 1'b0;
  else begin
    if (start_sample_to_eth)  eth_in_progress <= 1'b1;
    else if (eth_really_idle) eth_in_progress <= 1'b0;
  end
end

// 4) 门控后的以太网启动（直接用你现成的 RestartReq_0_d1）
wire start_sample_to_eth = RestartReq_0_d1 & allow_eth;
// ========================== PATCH A END ==========================
ad_8bit_to_16bit u_ad_8bit_to_16bit(
    .clk         (AD_Clk),
    .ad_sample_en(ad_sample_en),
    .ch_sel      (ChannelSel[1:0]),
    .AD0         (AD0),
    .AD1         (AD1),
    .ad_out      (ad_out),
    .ad_out_valid(ad_out_valid)
  );
  
    // 时钟有问题，先直接连接系统时钟
  assign AD0_CLK = AD_Clk;
  assign AD1_CLK = AD_Clk;
  
  // acm2108_test u_acm2108_test(
  //   .Clk    (clk_50M),
  //   .key_in (key_in),
  //   .AD0    (AD0), 
  //   .AD1    (AD1),
  //   .clk125m(clk125m),
  //   .clk50m (clk_50M),
  //   .AD_Clk (AD_Clk),
  //   .AD0_CLK(AD0_CLK),
  //   .AD1_CLK(AD1_CLK),
  //   .DA0_Data(DA0_Data),
  //   .DA1_Data(DA1_Data),
  //   .DA0_Clk (DA0_Clk),
  //   .DA1_Clk (DA1_Clk)
  // );
       


  state_ctrl u_state_ctrl(
    .clk           (clk_50M),
    .reset         (g_reset_50M),
    .start_sample  (start_sample_to_eth),
    .set_sample_num(DataNum),
    .rdfifo_empty  (rdfifo_empty),
    .rdfifo_dout   (rdfifo_dout),
    .wrfifo_full   (wrfifo_full),
    .adc_data_en   (adc_data_en),
    .wrfifo_clr    (wrfifo_clr),
    .rdfifo_clr    (rdfifo_clr),
    .rdfifo_rden   (rdfifo_rden),
    .ad_sample_en  (ad_sample_en),
    .eth_fifo_wrreq(eth_fifo_wrreq),
    .eth_fifo_wrdata(eth_fifo_wrdata),
	.eth_busy(),
	.eth_done_pulse()
  );

  wire [27:0] app_addr_max = 28'd268435455; // 256MB-1
  wire [7:0]  burst_len    = 8'd128;

  // ================== DDR3 控制器（统一同源接法） ==================
  ddr3_ctrl_2port u_ddr3 (
    .clk                 (clk_50M),
    .pll_lock            (ddr_lock),          // = u_ddr_pll.lock
    .pll_stop            (pll_stop),          // 仅观察；不再去门控 PLL
    .clk_400m            (clk_ddr_ref),       // 实际 200MHz（IP 内部已设 200）
    .sys_rst_n           (ddrdiag_sys_rst_n), // 稳定复位
    .init_calib_complete (ddr3_init_done),

    // 用户接口
    .rd_load             (rdfifo_clr),
    .wr_load             (wrfifo_clr),
    .app_addr_rd_min     (28'd0),
    .app_addr_rd_max     (app_addr_max),
    .rd_bust_len         (burst_len),
    .app_addr_wr_min     (28'd0),
    .app_addr_wr_max     (app_addr_max),
    .wr_bust_len         (burst_len),

    .wr_clk              (clk_50M),
    .wfifo_wren          (ad_out_valid && adc_data_en),
    .wfifo_din           (ad_out),
    .wrfifo_full         (wrfifo_full),

    .rd_clk              (clk_50M),
    .rfifo_rden          (rdfifo_rden),
    .rdfifo_empty        (rdfifo_empty),
    .rfifo_dout          (rdfifo_dout),

    // DDR3 颗粒
    .ddr3_dq             (IO_ddr_dq),
    .ddr3_dqs_n          (IO_ddr_dqs_n),
    .ddr3_dqs_p          (IO_ddr_dqs),
    .ddr3_addr           (O_ddr_addr),
    .ddr3_ba             (O_ddr_ba),
    .ddr3_ras_n          (O_ddr_ras_n),
    .ddr3_cas_n          (O_ddr_cas_n),
    .ddr3_we_n           (O_ddr_we_n),
    .ddr3_reset_n        (O_ddr_reset_n),
    .ddr3_ck_p           (O_ddr_clk),
    .ddr3_ck_n           (O_ddr_clk_n),
    .ddr3_cke            (O_ddr_cke),
    .ddr3_cs_n           (O_ddr_cs_n),
    .ddr3_dm             (O_ddr_dqm),
    .ddr3_odt            (O_ddr_odt)
  );

  // ================== 以太网发送侧 ==================

  wire g_reset_fifo_tx;
  assign g_reset_fifo_tx = g_reset_fifo_rx;


  fifo_tx u_fifo_tx(
    .Data  ({eth_fifo_wrdata[7:0], eth_fifo_wrdata[15:8]}),
    .Reset (g_reset_fifo_tx),
    .WrClk (clk_50M),
    .RdClk (clk125m_o),
    .WrEn  (eth_fifo_wrreq),
    .RdEn  (payload_req_o),
    .Wnum  (eth_fifo_usedw),
    .Rnum  (rd_data_count),
    .Q     (dout),
    .Empty (eth_fifo_tx_empty),
    .Full  ()
  );

  eth_send_ctrl u_eth_send_ctrl(
    .clk125M      (clk125m_o),     
    .reset_n      (~g_reset_125M),
    .eth_tx_done  (tx_done),
    .restart_req  (RestartReq_0_d1),
    .fifo_rd_cnt  (rd_data_count),
    .total_data_num(Number_d1),
    .pkt_tx_en    (tx_en_pulse),
    .pkt_length   (lenth_val)
  ); 

  eth_udp_tx_gmii u_eth_udp_tx_gmii
  (
    .clk125m       (clk125m_o),
    .reset_p       (g_reset_125M),
    .tx_en_pulse   (tx_en_pulse),
    .tx_done       (tx_done),

    .dst_mac       (48'hFF_FF_FF_FF_FF_FF),
    .src_mac       (LOCAL_MAC),
    .dst_ip        (32'hc0_a8_00_03),
    .src_ip        (LOCAL_IP),
    .dst_port      (16'd6102),
    .src_port      (LOCAL_PORT),

    .data_length   (lenth_val),
    .payload_req_o (payload_req_o),
    .payload_dat_i (dout),

    .gmii_tx_clk   (gmii_tx_clk),
    .gmii_txen     (gmii_txen),
    .gmii_txd      (gmii_txd)
  );

  gmii_to_rgmii u_gmii_to_rgmii(
    .reset_n  (~g_reset_125M),
    .gmii_tx_clk(gmii_tx_clk),
    .gmii_txd (gmii_txd),
    .gmii_txen(gmii_txen),
    .gmii_txer(1'b0),
    .rgmii_tx_clk(rgmii_tx_clk),
    .rgmii_txd   (rgmii_txd),
    .rgmii_txen  (rgmii_txen)
  );
  



//降频输出模块
// ============================================================================
// [NEW] 降频预览支路：25MHz 采样域 → 512x8 BRAM → AHB2（M1 显示）
// 说明：
//  - DEFAULT_DECIM=12207  @25MHz → ~2048 Sa/s，512点/帧 → ~4 fps
//  - 直接对接 AHB2 的 analog_* 口；不经过 DDR3
//  - 不影响以太网链路
// ============================================================================

// ---------------- 以太网忙同步到 ADC 域，并高有效复位预览模块 ----------------
// eth_active 打两拍 eth_act_a_d2
reg eth_act_a_d1, eth_act_a_d2;
always @(posedge adc_clk_fe or negedge rst_adc_n) begin
  if(!rst_adc_n) begin
    eth_act_a_d1 <= 1'b0;
    eth_act_a_d2 <= 1'b0;
  end else begin
    eth_act_a_d1 <= eth_active;
    eth_act_a_d2 <= eth_act_a_d1;
  end
end
//wire adc_decim_rstn = rst_adc_n | eth_act_a_d2;
wire adc_decim_rstn = rst_adc_n;
// ----------------------------------------------------------------
adc_decim_dpb #(
  .POINTS        (512),
  .DEFAULT_DECIM (10000) //12207 // 6600 //122
) u_preview (
  // 写口 @ 采样域（25MHz@270°）
  .adc_clk              (AD_Clk),
  .adc_rstn             (adc_decim_rstn),        // 高有效
  .adc_valid            (adc_valid_25m),
  .adc_data             (adc_data_25m),

  // 读口 @ HCLK 域
  .HCLK                 (HCLK),
  .HRESETn              (HRESETn),

  // AHB2 控制/状态（这组信号你原来就在 AHB2_SoC_Interface 里）
  .analog_preview_start (analog_preview_start),
  .analog_data_ack      (analog_data_ack),
  .analog_data_ready    (analog_data_ready),
  .decim_val_in         (decim_control_wire),  //新增的时基调节端口
  // AHB2 数据窗口（0..511）
  .analog_bram_addr     (analog_bram_addr),
  .analog_bram_dout     (analog_bram_dout),
  // 以太网占用门控（若不互斥可恒 0）
  .eth_active           (eth_active)            //input
);




//===================================DA==================================//

  wire DA_en;
  assign DA_en = (main_mode_select == 4'b0001) ? 1'b1 : 1'b0;
	   
    

  acm2108_dac0 u_acm2108_dac0(
    .Clk           (Clk),
    .Rst_n         (reset_n),
	.En			   (DA_en),
	.MODE          (MODE_DDS[11:0]),
    // AD/DA()
    .DA0_Clk       (DA0_Clk),
    .DA1_Clk       (DA1_Clk),
    .DA0_Data      (DA0_Data[7:0]),
    .DA1_Data      (DA1_Data[7:0])
);


endmodule
