`timescale 1ns / 1ps
`include "address_map.vh"

module spi_master_wrapper (
    input             clk,
    input             rst_n,
    
    // --- 内部配置总线 ---
    input      [15:0] cfg_addr,
    input      [31:0] cfg_wdata,
    input             cfg_write,

    // --- 数据回传接口 ---
    output reg [7:0]  cfg_rdata_out,
    output reg        cfg_rvalid_out,

    // --- 物理 SPI 接口 ---
    output            spi_sclk,
    output            spi_mosi,
    input             spi_miso,
    output reg [3:0]  spi_cs_n
);
// --- 内部寄存器 ---
    reg [31:0] config_reg;
    reg [63:0] tx_data_reg;
    reg [7:0]  len_reg;
    reg [3:0]  cs_reg;
    reg        start_trigger;
// --- 为时序优化的流水线寄存器 ---
    reg [1:0]  mode_reg;
    reg [31:0] speed_reg;
// --- 连接底层SPI核的信号 ---
    reg        core_trans_en;
    wire       core_trans_done;
    wire [7:0] core_rx_data;
// --- 包装器内部状态机 ---
    reg [3:0]  state, next_state;
    localparam S_IDLE       = 4'd0, S_START      = 4'd1, S_LOAD_BYTE  = 4'd2,
               S_WAIT_DONE  = 4'd3, S_STOP       = 4'd4;
    reg [63:0] tx_shifter;
    reg [7:0]  byte_count;

    // --- 总线从机逻辑 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            config_reg  <= 0;
            tx_data_reg <= 0;
            len_reg     <= 0;
            cs_reg      <= 0;
            start_trigger <= 1'b0;
        end else begin
            start_trigger <= 1'b0;
            if (cfg_write && (cfg_addr[15:4] == (`SPI_BASE_ADDR>>4))) begin
                case (cfg_addr)
                    `SPI_BASE_ADDR + `SPI_REG_OFFSET_CONFIG: config_reg <= cfg_wdata;
                    // --- FIX 1 (来自上次): 修正了数据组合顺序 ---
                    `SPI_BASE_ADDR + `SPI_REG_OFFSET_TX_DATA: tx_data_reg <= {cfg_wdata, tx_data_reg[31:0]};
                    `SPI_BASE_ADDR + `SPI_REG_OFFSET_CTRL: begin
                        if (cfg_wdata[0] && state == S_IDLE) begin
                            len_reg <= cfg_wdata[15:8];
                            cs_reg  <= cfg_wdata[7:4];
                            start_trigger <= 1'b1;
                        end
                    end
                endcase
            end
        end
    end

    // --- 流水线级 ---
    always @(posedge clk) begin
        mode_reg <= config_reg[1:0];
        speed_reg <= {16'd0, config_reg[31:16]};
    end

    // --- 例化Spi_Master_Ctrl模块 ---
    Spi_Master_Ctrl #( .BITS_ORDER(1) ) u_spi_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .cpol_i     (mode_reg[1]),      
        .cpha_i     (mode_reg[0]),      
        .clk_divisor(speed_reg),
        .SPI_CS     (),
        .SPI_SCLK   (spi_sclk),
        .SPI_MOSI   (spi_mosi),
        .SPI_MISO   (spi_miso),
        .tx_data    (tx_shifter[63:56]), // 始终发送最高字节
        .trans_en   (core_trans_en),
        .rx_data    (core_rx_data),
        .trans_done (core_trans_done),
        .spi_busy   ()
    );

    // ==========================================================
    // == FSM 修复: 重写为 3 块 `always`
    // ==========================================================

    // 块 1: 状态寄存器 (时序)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // 块 2: 状态机输出 (时序)
    // 根据 *当前* 状态设置寄存器输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_cs_n       <= 4'b1111; // 默认不选
            tx_shifter     <= 0;
            byte_count     <= 0;
            cfg_rvalid_out <= 1'b0;
            cfg_rdata_out  <= 8'h00;
        end else begin
            // 默认值
            cfg_rvalid_out <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (next_state == S_START) begin
                        // 在进入 S_START 时加载
                        tx_shifter <= tx_data_reg;
                        byte_count <= len_reg;
                        spi_cs_n   <= ~(1'b1 << cs_reg); // 在此断言 CS
                    end
                end
                
                S_START: begin
                    // S_START 状态是瞬时的, 动作在 S_IDLE 中处理
                end
                
                S_LOAD_BYTE: begin
                    // (core_trans_en 是组合逻辑, 见 块 3)
                end

                S_WAIT_DONE: begin
                    if (core_trans_done) begin
                        // 在 S_WAIT_DONE 完成时更新
                        tx_shifter     <= tx_shifter << 8; // **FIXED: 现在可以正确移位**
                        byte_count     <= byte_count - 1; // **FIXED: 现在可以正确计数**
                        cfg_rvalid_out <= 1'b1;
                        cfg_rdata_out  <= core_rx_data;
                    end
                end
                
                S_STOP: begin
                    spi_cs_n <= 4'b1111; // 在此释放 CS
                end
            endcase
        end
    end

    // 块 3: 下一状态逻辑 和 组合逻辑输出
    always @(*) begin
        next_state    = state;
        core_trans_en = 1'b0; // 默认关闭

        case (state)
            S_IDLE: begin
                if (start_trigger) begin
                    next_state = S_START;
                end
            end
            
            S_START: begin
                // --- FIX 2 (来自上次): 检查 len_reg ---
                if (len_reg > 0) begin
                    next_state = S_LOAD_BYTE;
                end else begin
                    next_state = S_STOP;
                end
            end
            
            S_LOAD_BYTE: begin
                core_trans_en = 1'b1; // 组合逻辑输出
                next_state    = S_WAIT_DONE;
            end
            
            S_WAIT_DONE: begin
                if (core_trans_done) begin
                    if (byte_count > 1) begin
                        next_state = S_LOAD_BYTE; // 返回加载下一字节
                    end else begin
                        next_state = S_STOP; // 传输完成
                    end
                end
            end
            
            S_STOP: begin
                next_state = S_IDLE;
            end
            
            default: begin
                next_state = S_IDLE;
            end
        endcase
    end
endmodule