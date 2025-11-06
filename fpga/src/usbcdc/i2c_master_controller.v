//有个缺陷，只指定了器件地址，对于寄存器地址，夹杂在了数据之间，需要在上位机中进行修改或者修改底层逻辑
//但是如果在指令解析模块加上寄存器地址这个强制选项，对于那些没有内部寄存器地址的简单I2C设备（比如一个简单的IO扩展芯片）进行通信
`timescale 1ns / 1ps
`include "address_map.vh"

// ** 修正后的最终版本 **
// 修复了 wlen 和 rlen 计数器逻辑缺陷

module i2c_master_wrapper (
    input             clk,
    input             rst_n,
    
    // --- 内部配置总线 ---
    input      [15:0] cfg_addr,
    input      [31:0] cfg_wdata,
    input             cfg_write,

    // --- 数据回传接口 ---
    output reg [7:0]  cfg_rdata_out,
    output reg        cfg_rvalid_out,

    // --- 物理 I2C 接口 ---
    output            i2c_scl,
    inout             i2c_sda
);
//================================================================
//== 1. 内部寄存器和信号定义
//================================================================
    // --- 总线配置寄存器 ---
    reg [7:0]  wlen_reg;
    reg [7:0]  rlen_reg;
    reg [63:0] tx_data_reg;
    reg [6:0]  slave_addr_reg;
    reg        start_trigger;

    // --- FSM 状态定义 ---
    reg [4:0]  state, next_state;
    reg [4:0]  prev_state;
    localparam S_IDLE        = 5'd0,  S_LOAD         = 5'd1,
               S_START       = 5'd2,  S_ADDR_WR      = 5'd3,
               S_WR_BYTE     = 5'd4,  S_REP_START    = 5'd5,
               S_ADDR_RD     = 5'd6,  S_RD_BYTE      = 5'd7,
               S_SEND_ACK    = 5'd8,  S_SEND_NACK    = 5'd9,
               S_STOP        = 5'd10, S_WAIT_CORE    = 5'd11;

    // --- FSM 内部工作寄存器 ---
    reg [7:0]  wlen_cnt;
    reg [7:0]  rlen_cnt;
    reg [63:0] tx_shifter;

    // --- 底层I2C核接口信号 ---
    reg  [5:0] core_cmd;
    reg        core_go;
    reg  [7:0] core_tx_data;
    wire [7:0] core_rx_data;
    wire       core_trans_done;
    wire       core_ack_o;
    wire       core_sdat_o;
    wire       core_sdat_oe;
    
//================================================================
//== 2. 总线从机逻辑 (时序逻辑)
//================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wlen_reg       <= 0;
            rlen_reg       <= 0;
            tx_data_reg    <= 0;
            slave_addr_reg <= 0;
            start_trigger  <= 1'b0;
        end else begin
            start_trigger <= 1'b0;
            if (cfg_write && (cfg_addr >= `I2C_BASE_ADDR) && (cfg_addr < `UART_BASE_ADDR)) begin
                case (cfg_addr)
                    `I2C_BASE_ADDR + `I2C_REG_OFFSET_LEN: begin
                        wlen_reg <= cfg_wdata[15:8];
                        rlen_reg <= cfg_wdata[7:0];
                    end
                    `I2C_BASE_ADDR + `I2C_REG_OFFSET_TX_DATA0: tx_data_reg[31:0] <= cfg_wdata;
                    `I2C_BASE_ADDR + `I2C_REG_OFFSET_TX_DATA1: tx_data_reg[63:32] <= cfg_wdata;
                    `I2C_BASE_ADDR + `I2C_REG_OFFSET_CTRL: begin
                        if (cfg_wdata[0] && state == S_IDLE) begin
                            slave_addr_reg <= cfg_wdata[7:1];
                            start_trigger <= 1'b1;
                        end
                    end
                endcase
            end
        end
    end

//================================================================
//== 3. FSM 状态更新 (时序逻辑)
//================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            prev_state     <= S_IDLE;
            wlen_cnt       <= 0;
            rlen_cnt       <= 0;
            tx_shifter     <= 0;
            cfg_rdata_out  <= 0;
            cfg_rvalid_out <= 1'b0;
        end else begin
            cfg_rvalid_out <= 1'b0;
            state <= next_state;
            
            if (next_state == S_WAIT_CORE && state != S_WAIT_CORE) begin
                prev_state <= state;
            end

            if (state == S_IDLE && next_state == S_LOAD) begin
                wlen_cnt   <= wlen_reg;
                rlen_cnt   <= rlen_reg;
                tx_shifter <= tx_data_reg << (64 - (wlen_reg * 8));
            end
            
            if (state == S_WR_BYTE && next_state == S_WAIT_CORE) begin
                tx_shifter <= tx_shifter << 8;
                wlen_cnt   <= wlen_cnt - 1;
            end 
            
            // ============ 修正 #1 开始 ============
            // 移除了 'else'，使这个 'if' 块独立于上面的 'if' 块
            // 这确保了 rlen_cnt 在S_WAIT_CORE状态的正确周期被递减
            if (state == S_WAIT_CORE && prev_state == S_RD_BYTE && core_trans_done) begin
                cfg_rdata_out  <= core_rx_data;
                cfg_rvalid_out <= 1'b1;
                rlen_cnt       <= rlen_cnt - 1;
            end
            // ============ 修正 #1 结束 ============
        end
    end

//================================================================
//== 4. FSM 下一状态逻辑与输出 (组合逻辑)
//================================================================
    always@(*) begin
        next_state   = state;
        core_go      = 1'b0;
        core_cmd     = 6'b0;
        core_tx_data = 8'h00;
        
        case(state)
            S_IDLE: 
                if(start_trigger) next_state = S_LOAD;
            S_LOAD: 
                next_state = S_START;
            S_START:     
                begin core_cmd = 6'b000010; core_go = 1'b1; next_state = S_WAIT_CORE; end
            S_ADDR_WR:   
                begin core_cmd = 6'b000001; core_tx_data = {slave_addr_reg, 1'b0}; core_go = 1'b1; next_state = S_WAIT_CORE; end
            S_WR_BYTE:   
                begin core_cmd = 6'b000001; core_tx_data = tx_shifter[63:56]; core_go = 1'b1; next_state = S_WAIT_CORE; end
            S_REP_START: 
                begin core_cmd = 6'b000010; core_go = 1'b1; next_state = S_WAIT_CORE; end
            S_ADDR_RD:   
                begin core_cmd = 6'b000001; core_tx_data = {slave_addr_reg, 1'b1}; core_go = 1'b1; next_state = S_WAIT_CORE; end
            S_RD_BYTE:   
                begin core_cmd = 6'b000100; core_go = 1'b1; next_state = S_WAIT_CORE; end
            S_SEND_ACK:  
                begin core_cmd = 6'b010000; core_go = 1'b1; next_state = S_WAIT_CORE; end
            S_SEND_NACK: 
                begin core_cmd = 6'b100000; core_go = 1'b1; next_state = S_WAIT_CORE; end
            S_STOP:      
                begin core_cmd = 6'b001000; core_go = 1'b1; next_state = S_WAIT_CORE; end
            
            S_WAIT_CORE: begin
                if(core_trans_done) begin
                    case(prev_state)
                        S_START:     
                            if (wlen_cnt > 0) next_state = S_ADDR_WR;
                            else if (rlen_cnt > 0) next_state = S_REP_START; 
                            else next_state = S_STOP;
                        S_ADDR_WR:   
                            if (core_ack_o == 1'b1) next_state = S_STOP;
                            else if (wlen_cnt > 0) next_state = S_WR_BYTE;
                            else if (rlen_cnt > 0) next_state = S_REP_START; 
                            else next_state = S_STOP;
                        S_WR_BYTE:   
                            if (core_ack_o == 1'b1) next_state = S_STOP;
                            // ============ 修正 #2 开始 ============
                            // 修复了写循环提前一字节结束的错误
                            else if (wlen_cnt > 0) next_state = S_WR_BYTE; // <-- 修正: 从 > 1 改为 > 0
                            // ============ 修正 #2 结束 ============
                            else if (rlen_cnt > 0) next_state = S_REP_START;
                            else next_state = S_STOP;
                        S_REP_START: 
                            next_state = S_ADDR_RD;
                        S_ADDR_RD:   
                            if (core_ack_o == 1'b1) next_state = S_STOP;
                            else if (rlen_cnt > 0) next_state = S_RD_BYTE;
                            else next_state = S_STOP;
                        S_RD_BYTE:   
                            // 当 rlen_cnt 为 1 时, 这是最后一个字节, 发送 NACK.
                            if (rlen_cnt > 1) next_state = S_SEND_ACK;
                            else next_state = S_SEND_NACK;
                        S_SEND_ACK:  
                            next_state = S_RD_BYTE;
                        S_SEND_NACK: 
                            next_state = S_STOP;
                        S_STOP:      
                            next_state = S_IDLE;
                        default:     
                            next_state = S_IDLE;
                    endcase
                end
            end
            
            default: 
                next_state = S_IDLE;
        endcase
    end

//================================================================
//== 5. 例化底层I2C核 & 三态门
//================================================================
    i2c_bit_shift i2c_core (
        .Clk        (clk),
        .Rst_n      (rst_n),
        .Cmd        (core_cmd),
        .Go         (core_go),
        .Tx_DATA    (core_tx_data),
        .Rx_DATA    (core_rx_data),
        .Trans_Done (core_trans_done),
        .ack_o      (core_ack_o),
        .i2c_sclk   (i2c_scl),
        .i2c_sdat   (i2c_sda),
        .i2c_sdat_o (core_sdat_o),
        .i2c_sdat_oe(core_sdat_oe)
    );
    
    assign i2c_sda = core_sdat_oe ? core_sdat_o : 1'bz;

endmodule