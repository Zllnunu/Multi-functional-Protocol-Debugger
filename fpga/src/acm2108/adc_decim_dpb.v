// ============================================================================
// 降频缓存模块（DPB 双口RAM版）
//  - A口：adc_clk 域写入（每 N 取 1）
//  - B口：HCLK   域读出 512 字节
//  目标：READY=1（满帧）→ M1 读 0..511 → M1 发 ACK → 清 READY → 写侧收 ACK 清指针 → 下一帧
//  约束：不改 SoC 顶层通信，只在本模块内自洽完成握手。
// ============================================================================

module adc_decim_dpb #(
    parameter integer POINTS        = 512,
    parameter integer DEFAULT_DECIM = 10000
)(
    // 写侧（ADC 域）
    input  wire                 adc_clk,
    input  wire                 adc_rstn,             // 低有效：1=正常，0=复位
    input  wire                 adc_valid,
    input  wire [7:0]           adc_data,

    // 读侧（HCLK 域）
    input  wire                 HCLK,
    input  wire                 HRESETn,              // 低有效

    // 预览握手（来自上层寄存器）
    input  wire                 analog_preview_start, // START（AHB 域锁存后送来）
    input  wire                 analog_data_ack,      // 上层 ACK（此版按脉冲上升沿处理）
    output wire                 analog_data_ready,    // READY（HCLK 域粘性位）

    input  wire [15:0]          decim_val_in,

    // 预览数据 BRAM 读口（HCLK 域）
    input  wire [8:0]           analog_bram_addr,
    output wire [7:0]           analog_bram_dout,

    // 可选：以太网占用门控（本模块未使用；保持端口不改 SoC）
    input  wire                 eth_active
);

    // ---------------------------------------------
    // 参数与内部信号
    // ---------------------------------------------
    localparam integer ADDR_W  = 9; // 0..511

    // 如果 M1 写入的值小于 5 (您的极限值)，则强制使用 DEFAULT_DECIM
    wire [15:0] current_decim_val = (decim_val_in < 5) ? DEFAULT_DECIM[15:0] : decim_val_in;

    reg  [ADDR_W-1:0] wptr;
    reg  [15:0]       decim_cnt;
    reg               frame_done_tgl_adc;

    // START 2FF 跨域同步到 adc_clk 域
    reg [1:0] start_sync;
    always @(posedge adc_clk or negedge adc_rstn) begin
        if (!adc_rstn) start_sync <= 2'b00;
        else           start_sync <= {start_sync[0], analog_preview_start};
    end
    wire start_adc = start_sync[1];

    // 写入门控（不把业务掺到复位）
    wire preview_enable = start_adc;

    // 写侧抽取命中与写 RAM（先写后判满，地址 511 也写）
    wire wr_hit   = adc_valid && (decim_cnt == (current_decim_val - 1));
    wire wr_fire  = preview_enable & wr_hit;
    wire last_addr= (wptr == 9'd511);

    // 内部 ACK toggle（HCLK 域翻转 → adc_clk 域 2FF+XOR 检测）
    reg        ack_tgl_local_h;    // HCLK 域翻转
    reg  [1:0] ack_sync_a;         // adc_clk 域 2FF
    wire       ack_edge_adc = ack_sync_a[1] ^ ack_sync_a[0];

    // ---------------------------------------------
    // 写侧：抽取计数、写指针、满帧事件（ACK 优先于写）
    // ---------------------------------------------
    always @(posedge adc_clk or negedge adc_rstn) begin
        if (!adc_rstn) begin
            decim_cnt          <= 16'd0;
            wptr               <= {ADDR_W{1'b0}};
            frame_done_tgl_adc <= 1'b0;
            ack_sync_a         <= 2'b00;
        end else begin
            // 同步 HCLK 域 ACK toggle
            ack_sync_a <= {ack_sync_a[0], ack_tgl_local_h};

            // ★ 先处理 ACK：清指针/计数，开启下一帧
            if (ack_edge_adc) begin
                wptr      <= {ADDR_W{1'b0}};
                decim_cnt <= 16'd0;
            end
            // 其次处理写入（先写后判满）
            else if (preview_enable && adc_valid) begin
                if (decim_cnt == (current_decim_val - 1)) begin
                    decim_cnt <= 16'd0;
                    if (last_addr) begin
                        // 地址 511 也被写入（wr_fire），随后翻转满帧事件
                        frame_done_tgl_adc <= ~frame_done_tgl_adc;
                        // 停在 511，等 ACK 清零后再置 0 开启下一帧
                    end else begin
                        wptr <= wptr + 1'b1;
                    end
                end else begin
                    decim_cnt <= decim_cnt + 16'd1;
                end
            end
            // 未使能预览时保持计数器清零
            else begin
                decim_cnt <= 16'd0;
            end
        end
    end

    // ---------------------------------------------
    // DPB 双口 RAM（A: adc_clk 写；B: HCLK 读）
    // ---------------------------------------------
    wire [7:0] douta_o, doutb_o;

//    pll_decim your_instance_name(
//        .clkout0(dpb_clk), //100hz 270°
//        .clkin(HCLK) //input clkin
//    );

    DPB_AD u_dpb (
        .douta (douta_o),
        .doutb (doutb_o),
        .clka  (adc_clk),
        .ocea  (1'b1),
        .cea   (1'b1),
        .reseta(~adc_rstn),        // 若 DPB 为高有效复位，这里取反；若为低有效复位，请去掉 ~
        .wrea  (wr_fire),
        .clkb  (HCLK),
        .oceb  (1'b1),
        .ceb   (1'b1),
        .resetb(~HRESETn),         // 同上
        .wreb  (1'b0),
        .ada   (wptr),
        .dina  (adc_data),
        .adb   (analog_bram_addr),
        .dinb  (8'h00)
    );

    assign analog_bram_dout = doutb_o;

    // ---------------------------------------------
    // HCLK 域：满帧事件同步 → READY 粘性位
    //          （ACK 仅按上升沿生效）
    // ---------------------------------------------

    // 写侧满帧事件同步到 HCLK 域
    reg fd_h_d1, fd_h_d2, fd_h_q;
    always @(posedge HCLK or negedge HRESETn) begin
      if (!HRESETn) begin
        fd_h_d1 <= 1'b0; fd_h_d2 <= 1'b0; fd_h_q <= 1'b0;
      end else begin
        fd_h_d1 <= frame_done_tgl_adc;
        fd_h_d2 <= fd_h_d1;
        fd_h_q  <= fd_h_d2;
      end
    end
    wire frame_done_pulse_h = fd_h_d2 ^ fd_h_q;

    // READY 粘性位
    reg data_ready_raw;

    // 记录上一拍地址（已废弃，但保留
    reg [8:0] addr_d;
    always @(posedge HCLK or negedge HRESETn) begin
      if (!HRESETn) addr_d <= 9'd0;
      else          addr_d <= analog_bram_addr;
    end

    // “见过 511”（已废弃）
    reg seen_511;
    always @(posedge HCLK or negedge HRESETn) begin
      if (!HRESETn)              seen_511 <= 1'b0;
      else if (!data_ready_raw)  seen_511 <= 1'b0;
      else if (analog_bram_addr == 9'd511) seen_511 <= 1'b1;
    end
    
    // 置位后一拍才允许考虑清零，避免“同拍置位又清掉”
    reg ready_armed;
    always @(posedge HCLK or negedge HRESETn) begin
      if (!HRESETn) ready_armed <= 1'b0;
      else begin
        if (frame_done_pulse_h)   ready_armed <= 1'b1;     // 新帧刚置位
        else if (!data_ready_raw) ready_armed <= 1'b0;     // 清零后复位
      end
    end

    // ★ 最小保持时间（可调），保证 READY 至少维持若干 HCLK 周期
    localparam integer READY_HOLD_CYC = 16;  // 建议先用较小值，避免丢触发
    reg [$clog2(READY_HOLD_CYC):0] ready_hold_cnt;
    wire hold_active = (ready_hold_cnt != 0);

    // 待处理挂账
    reg ack_pend;
    // reg rd_pend; // 彻底移除 rd_pend

    // === ACK 上升沿检测（把 ACK 当作脉冲处理） ===
    reg ack_d;
    always @(posedge HCLK or negedge HRESETn) begin
      if (!HRESETn) ack_d <= 1'b0;
      else          ack_d <= analog_data_ack;
    end
    wire ack_rise = analog_data_ack & ~ack_d;

    // 主状态（READY/ACK 处理）
    always @(posedge HCLK or negedge HRESETn) begin
      if (!HRESETn) begin
        data_ready_raw   <= 1'b0;
        ack_tgl_local_h  <= 1'b0;
        ready_hold_cnt   <= {($clog2(READY_HOLD_CYC)+1){1'b0}};
        ack_pend         <= 1'b0;
        // rd_pend          <= 1'b0; // 彻底移除
      end else begin
        // 满帧 → READY 置位，并加载保持计数；清空待处理
        if (frame_done_pulse_h) begin
          data_ready_raw  <= 1'b1;
          ready_hold_cnt  <= READY_HOLD_CYC[$clog2(READY_HOLD_CYC):0];
          ack_pend        <= 1'b0;
          // rd_pend         <= 1'b0; // 彻底移除
        end else if (hold_active) begin
          // 保持期计数
          ready_hold_cnt <= ready_hold_cnt - 1'b1;
        end

        // 只要本帧 READY 持续有效，就锁存“发生过的”ACK上升沿
        if (data_ready_raw) begin
          if (ack_rise) ack_pend <= 1'b1; // 仅上升沿有效
          
          // ====================== ★ 修复点 2 ======================
          // 彻底移除 rd_pend 自动ACK机制
          // =======================================================
        
        end

        // 保持期结束后，若任一待处理成立，则清 READY 并翻转 ACK toggle
        // ====================== ★ 修复点 3 ======================
        // ★ 修复点 ★：现在此条件将仅依赖 ack_pend
        if (ready_armed && !hold_active && data_ready_raw && ack_pend) begin
          data_ready_raw  <= 1'b0;
          ack_tgl_local_h <= ~ack_tgl_local_h; // <--- ★★★ 已更正拼写 ★★★
          ack_pend        <= 1'b0;
          // rd_pend         <= 1'b0; // 彻底移除
        end
      end
    end

    assign analog_data_ready = data_ready_raw;

endmodule