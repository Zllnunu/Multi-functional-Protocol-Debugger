// ============================================================================
// Module: AHB2_SoC_Interface.v
// Description:
//   **已修正**: 修复了由于部分地址译码导致的地址别名冲突问题。
//   读操作逻辑被重构，优先判断完整的BRAM/ROM地址范围，
//   然后再处理寄存器地址，从而解决了数据读取错误的问题。
// ============================================================================
`timescale 1ns / 1ps
module AHB2_SoC_Interface (
    input  HCLK,
    input  AHB2HRESETn,
    input  AHB2HSEL,
    input  [31:0] AHB2HADDR,
    input  [1:0]  AHB2HTRANS,
    input  AHB2HWRITE,
    input  [31:0] AHB2HWDATA,
    output reg [31:0] AHB2HRDATA,
    output reg AHB2HREADY,
    output wire [1:0] AHB2HRESP,

    output wire [3:0]  main_mode_select,
    output wire [11:0] MODE_DDS,

    // --- 模拟输入接口 ---
    output reg analog_preview_start,
    input  analog_data_ready,
    output reg analog_data_ack,
    input  [7:0] analog_bram_dout,
    output reg [8:0] analog_bram_addr,
    output wire [15:0] analog_decim_val, // ★ 新增：模拟输入时基（Decimation）控制输出 ★

    // --- 数字测量 (基础) 接口 ---
    output reg digital_meas_start,
    output reg digital_meas_ack,
    input  digital_meas_ready,
    input  [31:0] digital_period_in,
    input  [31:0] digital_hightime_in,
    // --- 数字测量 /协议分析 (拓展) 接口 ---
    output reg digital_capture_start,
    output reg digital_capture_ack,
    input  digital_capture_ready,
    input  [31:0]      capture_bram_rdata,
    output reg [4:0]   capture_bram_raddr,

    input  wire [31:0] digital_in_data,

    // USB CDC 模式接口 
    output wire usb_cdc_start,


    output wire uart_tx_debug
);

// ========================================================================
// Section 1: AHB 总线逻辑和寄存器实现
// ========================================================================
    assign AHB2HRESP = 2'b00;
    wire trans_valid = AHB2HTRANS[1];
    wire wr_en = AHB2HSEL & trans_valid &  AHB2HWRITE;
    wire rd_en = AHB2HSEL & trans_valid & ~AHB2HWRITE;

    // --- 内部寄存器定义 ---
    reg [31:0] mode_select_reg;
    reg [31:0] dds_control_reg;
    reg [31:0] analog_control_reg;
    reg [31:0] digital_control_reg;
    reg [31:0] digital_capture_control_reg;
    reg [31:0] analog_decim_reg;// ★ 新增：时基寄存器 ★
    reg [31:0] usb_cdc_control_reg;
    assign main_mode_select = mode_select_reg[3:0];
    assign MODE_DDS = dds_control_reg[11:0];

    // (如果M1写入0或太小的值，我们将在 adc_decim_dpb 模块中处理默认值)
    assign analog_decim_val = analog_decim_reg[15:0];
    assign usb_cdc_start = usb_cdc_control_reg[0];
    // --- 单一的寄存器写操作 always 块 ---
    always @(posedge HCLK or negedge AHB2HRESETn) begin
        if (!AHB2HRESETn){
             mode_select_reg, dds_control_reg, analog_control_reg,
              digital_control_reg, digital_capture_control_reg ,            
              analog_decim_reg , usb_cdc_control_reg  } <= 0;// ★ 新增：复位时基寄存器 ★
              
        else if (wr_en) begin
            // 注意: 此处的部分译码对于没有地址重叠的稀疏寄存器是可接受的，但不是最佳实践
            case (AHB2HADDR[7:2])
                6'h00: mode_select_reg           <= AHB2HWDATA;
                6'h01: dds_control_reg           <= AHB2HWDATA;
                6'h02: analog_control_reg        <= AHB2HWDATA;
                6'h04: digital_control_reg       <= AHB2HWDATA;
                6'h08: digital_capture_control_reg <= AHB2HWDATA;
                6'h0A: analog_decim_reg          <= AHB2HWDATA; // ★ 新增：处理对 0x28 (即 6'h0A) 的写入 ★
                6'h0B: usb_cdc_control_reg       <= AHB2HWDATA; // (0x2C)
                default: ;
            endcase
        end
    end


    // --- 读操作流水线状态机 ---
    localparam R_IDLE   = 3'd0;
    localparam R_WAIT1  = 3'd1;
    localparam R_WAIT2  = 3'd2;
    localparam R_LATCH  = 3'd3;
    localparam R_ACCESS = 3'd4;
    reg [2:0] read_state;
    reg [31:0] addr_reg;
    reg [31:0] bram_data_latch;

    always @(posedge HCLK or negedge AHB2HRESETn) begin
        if (!AHB2HRESETn) begin
            read_state <= R_IDLE;
            AHB2HREADY <= 1'b1;
            AHB2HRDATA <= 32'd0;
            analog_bram_addr <= 9'd0;
            capture_bram_raddr <= 5'd0;
            bram_data_latch <= 32'd0;
        end else begin
            AHB2HREADY <= 1'b1; // 默认就绪

            case (read_state)
                R_IDLE: begin
                    if (rd_en) begin
                        addr_reg <= AHB2HADDR;
                        AHB2HREADY <= 1'b0; 
                        read_state <= R_WAIT1; 
                        
                        // BRAM地址生成 (此部分逻辑正确)
                        if ((AHB2HADDR >= 32'h81000400) && (AHB2HADDR < 32'h81000800)) begin
                            capture_bram_raddr <= (AHB2HADDR - 32'h81000400) >> 2;
                        end else if ((AHB2HADDR >= 32'h81000100) && (AHB2HADDR < 32'h81000300)) begin
                            analog_bram_addr <= AHB2HADDR - 32'h81000100;
                        end
                    end
                end

                R_WAIT1: begin
                    AHB2HREADY <= 1'b0; 
                    read_state <= R_WAIT2;
                end
                
                R_WAIT2: begin
                    AHB2HREADY <= 1'b0; 
                    read_state <= R_LATCH;
                end

                R_LATCH: begin
                    bram_data_latch <= capture_bram_rdata;
                    AHB2HREADY <= 1'b0;
                    read_state <= R_ACCESS;
                end
                
                R_ACCESS: begin
                    // ====================== 核心修正部分 ======================
                    // ** 采用完整地址、高优先级译码逻辑，彻底杜绝地址别名冲突 **

                    // 优先级 1: 模拟信号 ROM
                    if ((addr_reg >= 32'h81000100) && (addr_reg < 32'h81000300)) begin
                        // 此处处理字节到32位字的转换，对于纯C语言指针访问可能是非预期的，
                        // 但我们保留此逻辑因为它在您之前的设计中是工作的。
                        case (addr_reg[1:0])
                            2'b00:  AHB2HRDATA <= {24'h0, analog_bram_dout};
                            2'b01:  AHB2HRDATA <= {16'h0, analog_bram_dout, 8'h0};
                            2'b10:  AHB2HRDATA <= {8'h0, analog_bram_dout, 16'h0};
                            2'b11:  AHB2HRDATA <= {analog_bram_dout, 24'h0};
                        endcase
                    end
                    // 优先级 2: 数字捕获 BRAM
                    else if ((addr_reg >= 32'h81000400) && (addr_reg < 32'h81000800)) begin
                        AHB2HRDATA <= bram_data_latch;
                    end
                    // 优先级 3: 寄存器区域
                    else begin
                        case (addr_reg[7:2])
                            6'h03:  AHB2HRDATA <= {31'b0, analog_data_ready};       // 0x0C
                            6'h05:  AHB2HRDATA <= {31'b0, digital_meas_ready};      // 0x14
                            6'h06:  AHB2HRDATA <= digital_period_in;               // 0x18
                            6'h07:  AHB2HRDATA <= digital_hightime_in;             // 0x1C
                            6'h09:  AHB2HRDATA <= {31'b0, digital_capture_ready};   // 0x24
                            // 注意: 其他寄存器(如控制寄存器)是只写的，无需在此处处理读操作
                            default: AHB2HRDATA <= 32'hDEADBEEF; // 对于未定义的地址返回一个明显错误的值
                        endcase
                    end
                    // ====================== 修正结束 ======================
                    
                    AHB2HREADY <= 1'b1;
                    read_state <= R_IDLE;
                end
            endcase
        end
    end

    // 控制信号同步 (此部分逻辑无需修改)
    always @(posedge HCLK or negedge AHB2HRESETn) begin
        if (!AHB2HRESETn) begin
            analog_preview_start   <= 0;
            analog_data_ack        <= 0;
            digital_meas_start     <= 0;
            digital_meas_ack       <= 0;
            digital_capture_start  <= 0;
            digital_capture_ack    <= 0;
        end
        else begin
            analog_preview_start <= analog_control_reg[0];
            if (wr_en && (AHB2HADDR[7:2] == 6'h02) && AHB2HWDATA[1])
                analog_data_ack <= 1;
            else
                analog_data_ack <= 0;

            digital_meas_start <= digital_control_reg[0];
            if (wr_en && (AHB2HADDR[7:2] == 6'h04) && AHB2HWDATA[1])
                digital_meas_ack <= 1;
            else
                digital_meas_ack <= 0;

            digital_capture_start <= digital_capture_control_reg[0];
            if (wr_en && (AHB2HADDR[7:2] == 6'h08) && AHB2HWDATA[1])
                digital_capture_ack <= 1;
            else
                digital_capture_ack <= 0;
        end
    end
    
    // UART 调试部分无需修改...
    // ... (省略 UART 调试代码)
    reg  [7:0]  uart_data_byte;
    reg         uart_send_en;
    wire        uart_tx_done;
    reg  [31:0] dbg_addr_reg;
    reg  [31:0] dbg_data_reg;
    reg  [3:0]  byte_count;
    reg [31:0] ahb_addr_prev_cycle;

    always @(posedge HCLK) begin
        ahb_addr_prev_cycle <= AHB2HADDR;
    end

    reg [1:0] debug_state;

    always @(posedge HCLK or negedge AHB2HRESETn) begin
        if (!AHB2HRESETn) begin
            debug_state <= 2'd0;
            byte_count  <= 4'd0;
        end else begin
            case (debug_state)
                2'd0: if (wr_en) debug_state <= 2'd1;
                2'd1: begin
                    dbg_addr_reg <= ahb_addr_prev_cycle;
                    dbg_data_reg <= AHB2HWDATA;
                    byte_count <= 4'd0;
                    debug_state <= 2'd2;
                end
                2'd2: debug_state <= 2'd3;
                2'd3: begin
                    if (uart_tx_done) begin
                        if (byte_count == 4'd8) begin
                            debug_state <= 2'd0;
                        end else begin
                            byte_count <= byte_count + 1'b1;
                            debug_state <= 2'd2;
                        end
                    end
                end
                default: debug_state <= 2'd0;
            endcase
        end
    end

    always @(*) begin
        uart_send_en = (debug_state == 2'd2);
        case (byte_count)
            4'd0: uart_data_byte = 8'hAA;
            4'd1: uart_data_byte = dbg_addr_reg[31:24];
            4'd2: uart_data_byte = dbg_addr_reg[23:16];
            4'd3: uart_data_byte = dbg_addr_reg[15:8];
            4'd4: uart_data_byte = dbg_addr_reg[7:0];
            4'd5: uart_data_byte = dbg_data_reg[31:24];
            4'd6: uart_data_byte = dbg_data_reg[23:16];
            4'd7: uart_data_byte = dbg_data_reg[15:8];
            4'd8: uart_data_byte = dbg_data_reg[7:0];
            default: uart_data_byte = 8'hFF;
        endcase
    end

    uart_byte_tx u_uart_debug_tx (
        .clk        (HCLK),
        .reset_n    (AHB2HRESETn),
        .data_byte  (uart_data_byte),
        .send_en    (uart_send_en),
        .baud_set   (3'b100),
        .uart_tx    (uart_tx_debug),
        .tx_done    (uart_tx_done),
        .uart_state ()
    );
endmodule