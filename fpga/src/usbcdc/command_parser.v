//对于多路PWM输出：PWM_CONFIG:CH=1;FREQ=1000;DUTY=50;ENABLE=1;
//SPI:CS=0,MODE=0,SPEED=1000000,LEN=4,DATA=0xDEADBEEF;
//对于SPI，后续可以考虑帧格式（高位在前还是地位在前）的设置.没什么用，不加了
//IIC:ADDR=<值>,SPEED=<值>,WLEN=<值>,WDATA=<值>,RLEN=<值>;
//UART:BAUD=<值>,BITS=<值>,PARITY=<值>,STOP=<值>,LEN=<值>,DATA=<值>;
//CAN:ID=<值>,EXT=<值>,RTR=<值>,RTR=<值>,DLC=<值>,BITRATE=<值>,DATA=<值>;
`timescale 1ns / 1ps
`include "address_map.vh"

// ** FINAL VERSION - Passthrough Removed, Bugfixes Kept **
module command_parser (
    input             clk,
    input             rst_n,
    input      [7:0]  fifo_dout,
    input             fifo_empty,
    output reg        fifo_pop,
   
    output reg        tx_fifo_push,
    output reg [7:0]  tx_fifo_din,
    input             tx_fifo_full,
    
    input      [7:0]  periph_rdata,
    input             periph_valid,
    output reg [2:0]  periph_sel,
    
    // (移除 uart_tx_fifo_full 输入)

    output reg [15:0] cfg_addr,
    output reg [31:0] cfg_wdata,
    output reg        cfg_write
);
    // State machine states and IDs
    localparam S_IDLE        = 5'd0, S_MATCH_CMD   = 5'd1, S_CHECK_CMD     = 5'd2;
    localparam S_MATCH_KEY   = 5'd3, S_WAIT_EQ     = 5'd4, S_PARSE_VAL     = 5'd5;
    localparam S_PARAM_DONE  = 5'd6, S_EXECUTE     = 5'd7;
    localparam S_WAIT_READ_DATA = 5'd8;
    localparam S_EXECUTE_UART_WAIT = 5'd9;
    // (移除 S_UART_PASSTHROUGH)

    // Command IDs
    localparam CMD_ID_NONE   = 8'd0, CMD_ID_PWM = 8'd1, CMD_ID_SPI = 8'd2;
    localparam CMD_ID_UART   = 8'd3, CMD_ID_IIC = 8'd4, CMD_ID_CAN = 8'd5;
    localparam CMD_ID_SEQ    = 8'd6;

    // Keyword IDs
    localparam KEY_ID_NONE    = 8'd0,  KEY_ID_CH      = 8'd1,  KEY_ID_PERIOD  = 8'd2,  KEY_ID_DUTYVAL = 8'd3,  KEY_ID_ENABLE  = 8'd4;
    localparam KEY_ID_CS      = 8'd10, KEY_ID_MODE    = 8'd11, KEY_ID_DIVISOR = 8'd12, KEY_ID_LEN     = 8'd13, KEY_ID_DATA    = 8'd14;
    localparam KEY_ID_BITS    = 8'd21, KEY_ID_PARITY  = 8'd22, KEY_ID_STOP    = 8'd23;
    // (移除 KEY_ID_UART_MODE)
    localparam KEY_ID_ADDR    = 8'd30, KEY_ID_WLEN    = 8'd31, KEY_ID_WDATA   = 8'd32, KEY_ID_RLEN    = 8'd33;
    localparam KEY_ID_ID      = 8'd40, KEY_ID_EXT     = 8'd41, KEY_ID_RTR     = 8'd42, KEY_ID_DLC     = 8'd43, KEY_ID_BITRATE = 8'd44;
    localparam KEY_ID_LOOP    = 8'd50;
    localparam KEY_ID_SYNC_GO = 8'd51;

    // Internal registers
    reg [15:0] cfg_addr_next;
    reg [31:0] cfg_wdata_next;
    reg        cfg_write_next;
    reg [4:0]  next_state;
    reg [7:0]  parsed_cmd_id_next;
    reg [7:0]  parsed_key_id_next;
    reg [63:0] value_accumulator_next;
    reg [3:0]  digit_value;

    reg [4:0]  current_state;
    reg [7:0]  match_buffer [0:15];
    reg [4:0]  match_ptr;
    reg [7:0]  parsed_cmd_id;
    reg [7:0]  parsed_key_id;
    reg [63:0] value_accumulator;
    reg [3:0]  exec_step_reg;
    reg [7:0]  read_len_counter;

    // Parameter storage registers
    reg [3:0]  pwm_ch; reg [31:0] pwm_period;
    reg [31:0] pwm_dutyval; reg pwm_enable;
    reg [3:0]  spi_cs; reg [1:0]  spi_mode; reg [31:0] spi_divisor; reg [7:0]  spi_len;
    reg [63:0] spi_data;
    reg [6:0]  iic_addr; reg [31:0] iic_divisor; reg [7:0]  iic_wlen;
    reg [63:0] iic_wdata;
    reg [7:0]  iic_rlen;
    reg [31:0] uart_divisor; reg [3:0]  uart_bits; reg [1:0]  uart_parity; reg [1:0]  uart_stop;
    reg [7:0]  uart_len;
    reg [63:0] uart_data;
    
    // (移除 uart_passthrough_mode 和 uart_mode_val)

    reg [28:0] can_id; reg can_ext; reg can_rtr; reg [3:0]  can_dlc;
    reg [63:0] can_data; reg [31:0] can_bitrate;
    
    reg [3:0]   seq_ch;
    reg [7:0] seq_len; reg seq_loop; reg [31:0] seq_divisor;
    reg [255:0] seq_data;
    reg seq_enable;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            exec_step_reg <= 0;
            match_ptr <= 0;
            periph_sel <= 0;
            read_len_counter <= 0;
            parsed_cmd_id <= CMD_ID_NONE;
            parsed_key_id <= KEY_ID_NONE;
            value_accumulator <= 0;
            
            pwm_ch <= 0; pwm_period <= 0; pwm_dutyval <= 0; pwm_enable <= 0;
            spi_cs <= 0; spi_mode <= 0; spi_divisor <= 0; spi_len <= 0; spi_data <= 0;
            iic_addr <= 0; iic_divisor <= 0; iic_wlen <= 0; iic_wdata <= 0; iic_rlen <= 0;
            uart_divisor <= 0; uart_bits <= 0; uart_parity <= 0;
            uart_stop <= 0; uart_len <= 0; uart_data <= 0;
            // (移除 passthrough 模式复位)
            
            can_id <= 0; can_ext <= 0; can_rtr <= 0;
            can_dlc <= 0; can_data <= 0; can_bitrate <= 0;
            
            seq_ch <= 0; seq_len <= 0; seq_loop <= 0;
            seq_divisor <= 32'd0;
            seq_data <= 0;
            seq_enable <= 0;
        end else begin
            current_state <= next_state;
            
            // --- *** 关键修改：修复 exec_step_reg 逻辑 *** ---
            exec_step_reg <= exec_step_reg; // 默认保持

            if (current_state == S_PARAM_DONE && next_state == S_EXECUTE) begin
                exec_step_reg <= 0; // 1. (解析 -> 执行) 复位
            end else if (current_state == S_EXECUTE && next_state == S_EXECUTE_UART_WAIT) begin
                exec_step_reg <= 0; // 2. (UART配置 -> UART数据) 复位
            end else if (current_state == S_EXECUTE && next_state == S_EXECUTE) begin
                exec_step_reg <= exec_step_reg + 1'b1; // 3. 在 S_EXECUTE 内部递增
            end else if (current_state == S_EXECUTE_UART_WAIT && next_state == S_EXECUTE_UART_WAIT) begin
                 exec_step_reg <= exec_step_reg + 1'b1; // 4. 在 S_EXECUTE_UART_WAIT 内部递增
            end
            // --- *** 修改结束 *** ---
            
            if (next_state == S_IDLE && current_state != S_IDLE) begin
                parsed_cmd_id <= CMD_ID_NONE;
                parsed_key_id <= KEY_ID_NONE;
                pwm_ch <= 0; pwm_period <= 0; pwm_dutyval <= 0; pwm_enable <= 0;
                spi_cs <= 0; spi_mode <= 0; spi_divisor <= 0; spi_len <= 0; spi_data <= 0;
                iic_addr <= 0; iic_divisor <= 0; iic_wlen <= 0; iic_wdata <= 0; iic_rlen <= 0;
                uart_divisor <= 0; uart_bits <= 0; uart_parity <= 0;
                uart_stop <= 0; uart_len <= 0; uart_data <= 0;
                
                can_id <= 0; can_ext <= 0; can_rtr <= 0;
                can_dlc <= 0; can_data <= 0; can_bitrate <= 0;
                seq_ch <= 0; seq_len <= 0; seq_loop <= 0;
                seq_divisor <= 32'd0;
                seq_data <= 0;
                seq_enable <= 0;
            end

            if (next_state == S_WAIT_READ_DATA && current_state != S_WAIT_READ_DATA) begin
                if (parsed_cmd_id_next == CMD_ID_IIC) periph_sel <= 3'b011;
                else if (parsed_cmd_id_next == CMD_ID_SPI) periph_sel <= 3'b010;
                else periph_sel <= 3'b000;
            end else if (next_state == S_IDLE) begin
                periph_sel <= 3'b000;
            end

            if (next_state == S_WAIT_READ_DATA && current_state != S_WAIT_READ_DATA) begin
                 if (parsed_cmd_id_next == CMD_ID_SPI) read_len_counter <= spi_len;
                 else if (parsed_cmd_id_next == CMD_ID_IIC) read_len_counter <= iic_rlen;
            end else if (current_state == S_WAIT_READ_DATA && tx_fifo_push) begin
                read_len_counter <= read_len_counter - 1;
            end
            
            if ((next_state == S_MATCH_CMD && current_state != S_MATCH_CMD) || 
                (next_state == S_MATCH_KEY && current_state != S_MATCH_KEY)) begin
                match_ptr <= 0;
            end
            
            if (fifo_pop) begin
                if ((current_state == S_MATCH_CMD && fifo_dout != ":") ||
                    (current_state == S_MATCH_KEY && fifo_dout != "=" && fifo_dout != "," && fifo_dout != ";")) begin
               
                    if (match_ptr < 16) begin
                        match_buffer[match_ptr] <= fifo_dout;
                        match_ptr <= match_ptr + 1;
                    end
                end
            end

            parsed_cmd_id <= parsed_cmd_id_next;
            parsed_key_id <= parsed_key_id_next;
            value_accumulator <= value_accumulator_next;

            if (current_state == S_PARAM_DONE) begin
                case(parsed_key_id)
                    KEY_ID_CH:
                        if (parsed_cmd_id == CMD_ID_PWM) pwm_ch <= value_accumulator;
                        else if (parsed_cmd_id == CMD_ID_SEQ) seq_ch <= value_accumulator;
                    KEY_ID_PERIOD:  pwm_period <= value_accumulator; 
                    KEY_ID_DUTYVAL: pwm_dutyval <= value_accumulator;
                    KEY_ID_ENABLE:
                        if (parsed_cmd_id == CMD_ID_PWM) pwm_enable <= value_accumulator;
                        else if (parsed_cmd_id == CMD_ID_SEQ) seq_enable <= value_accumulator;
                    KEY_ID_CS:      spi_cs <= value_accumulator;
                    KEY_ID_MODE:    spi_mode <= value_accumulator;
                    KEY_ID_DIVISOR: 
                        if (parsed_cmd_id == CMD_ID_SPI) spi_divisor <= value_accumulator;
                        else if (parsed_cmd_id == CMD_ID_IIC) iic_divisor <= value_accumulator;
                        else if (parsed_cmd_id == CMD_ID_UART) uart_divisor <= value_accumulator;
                        else if (parsed_cmd_id == CMD_ID_SEQ) seq_divisor <= value_accumulator;
                    KEY_ID_ADDR:    iic_addr <= value_accumulator;
                    KEY_ID_WLEN:    iic_wlen <= value_accumulator; 
                    KEY_ID_WDATA:   iic_wdata <= value_accumulator; 
                    KEY_ID_RLEN:    iic_rlen <= value_accumulator;
                    KEY_ID_BITS:    uart_bits <= value_accumulator; 
                    KEY_ID_PARITY:  uart_parity <= value_accumulator; 
                    KEY_ID_STOP:    uart_stop <= value_accumulator;
                    // (移除 KEY_ID_UART_MODE)
                    KEY_ID_ID:      can_id <= value_accumulator; 
                    KEY_ID_EXT:     can_ext <= value_accumulator;
                    KEY_ID_RTR:     can_rtr <= value_accumulator; 
                    KEY_ID_DLC:     can_dlc <= value_accumulator; 
                    KEY_ID_BITRATE: can_bitrate <= value_accumulator;
                    KEY_ID_LEN:
                        if (parsed_cmd_id == CMD_ID_SPI) spi_len <= value_accumulator;
                        else if (parsed_cmd_id == CMD_ID_UART) uart_len <= value_accumulator;
                        else if (parsed_cmd_id == CMD_ID_SEQ) seq_len <= value_accumulator;
                    
                    // --- *** 关键修改：KEY_ID_DATA 左对齐 *** ---
                    KEY_ID_DATA:
                        if (parsed_cmd_id == CMD_ID_SPI) spi_data <= value_accumulator;
                        else if (parsed_cmd_id == CMD_ID_CAN) can_data <= value_accumulator;
                        else if (parsed_cmd_id == CMD_ID_SEQ) seq_data <= value_accumulator;
                        else if (parsed_cmd_id == CMD_ID_UART) begin
                            // uart_len 此时已被赋值
                            // 根据 uart_len 左移对齐
                            if (uart_len == 1)      uart_data <= value_accumulator << 56;
                            else if (uart_len == 2) uart_data <= value_accumulator << 48;
                            else if (uart_len == 3) uart_data <= value_accumulator << 40;
                            else if (uart_len == 4) uart_data <= value_accumulator << 32;
                            else if (uart_len == 5) uart_data <= value_accumulator << 24;
                            else if (uart_len == 6) uart_data <= value_accumulator << 16;
                            else if (uart_len == 7) uart_data <= value_accumulator << 8;
                            else                    uart_data <= value_accumulator; // 8 字节或 0 字节
                        end
                    // --- *** 修改结束 *** ---
                        
                    KEY_ID_LOOP:    seq_loop <= value_accumulator;
                    KEY_ID_SYNC_GO: ;
                endcase
            end
            
            // (移除 passthrough 模式标志设置)
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_addr <= 16'h0;
            cfg_wdata <= 32'h0;
            cfg_write <= 1'b0;
        end else begin
            cfg_addr <= cfg_addr_next;
            cfg_wdata <= cfg_wdata_next;
            cfg_write <= cfg_write_next;
        end
    end

    always @(*) begin
        next_state = current_state;
        fifo_pop = 1'b0;
        cfg_write_next = 1'b0;
        cfg_addr_next  = cfg_addr;
        cfg_wdata_next = cfg_wdata;
        tx_fifo_push = 1'b0;
        tx_fifo_din = 8'h00;
        parsed_cmd_id_next = parsed_cmd_id;
        parsed_key_id_next = parsed_key_id;
        value_accumulator_next = value_accumulator;
        digit_value = 0;
        
        case (current_state)
            S_IDLE: begin
                // --- 恢复: 移除 passthrough 检查 ---
                if (!fifo_empty) begin
                    if (fifo_dout == 8'h0D || fifo_dout == 8'h0A) begin
                        fifo_pop = 1'b1;
                        next_state = S_IDLE;
                    end else begin
                        fifo_pop = 1'b0;
                        next_state = S_MATCH_CMD;
                    end
                end
            end

            S_MATCH_CMD: begin
                if (!fifo_empty) begin
                    fifo_pop = 1'b1;
                    if (fifo_dout == ":") begin
                        next_state = S_CHECK_CMD;
                    end else if (match_ptr >= 15) begin
                        next_state = S_IDLE;
                    end else begin
                        next_state = S_MATCH_CMD;
                    end
                end
            end

            S_CHECK_CMD: begin
                if (match_ptr == 3 && match_buffer[0]=="P" && match_buffer[1]=="W" && match_buffer[2]=="M") parsed_cmd_id_next = CMD_ID_PWM;
                else if (match_ptr == 3 && match_buffer[0]=="S" && match_buffer[1]=="P" && match_buffer[2]=="I") parsed_cmd_id_next = CMD_ID_SPI;
                else if (match_ptr == 4 && match_buffer[0]=="U" && match_buffer[1]=="A" && match_buffer[2]=="R" && match_buffer[3]=="T") parsed_cmd_id_next = CMD_ID_UART;
                else if (match_ptr == 3 && match_buffer[0]=="I" && match_buffer[1]=="I" && match_buffer[2]=="C") parsed_cmd_id_next = CMD_ID_IIC;
                else if (match_ptr == 3 && match_buffer[0]=="C" && match_buffer[1]=="A" && match_buffer[2]=="N") parsed_cmd_id_next = CMD_ID_CAN;
                else if (match_ptr == 3 && match_buffer[0]=="S" && match_buffer[1]=="E" && match_buffer[2]=="Q") parsed_cmd_id_next = CMD_ID_SEQ;
                else parsed_cmd_id_next = CMD_ID_NONE;
                if (parsed_cmd_id_next != CMD_ID_NONE) begin
                    next_state = S_MATCH_KEY;
                end else begin
                    next_state = S_IDLE;
                end
            end
            
            S_MATCH_KEY: begin
                if (!fifo_empty) begin
                    fifo_pop = 1'b1;
                    if (fifo_dout == "=") next_state = S_WAIT_EQ;
                    else if (fifo_dout == ";") next_state = S_EXECUTE;
                    else if (fifo_dout == ",") next_state = S_MATCH_KEY;
                    else if (match_ptr >= 15) next_state = S_IDLE;
                    else next_state = S_MATCH_KEY;
                end
            end

            S_WAIT_EQ: begin
                value_accumulator_next = 0;
                next_state = S_PARSE_VAL;
                parsed_key_id_next = KEY_ID_NONE;
                case(parsed_cmd_id)
                    CMD_ID_PWM: 
                        if (match_ptr == 2 && match_buffer[0]=="C" && match_buffer[1]=="H") parsed_key_id_next = KEY_ID_CH;
                        else if (match_ptr == 6 && match_buffer[0]=="P" && match_buffer[1]=="E" && match_buffer[2]=="R" && match_buffer[3]=="I" && match_buffer[4]=="O" && match_buffer[5]=="D") parsed_key_id_next = KEY_ID_PERIOD;
                        else if (match_ptr == 7 && match_buffer[0]=="D" && match_buffer[1]=="U" && match_buffer[2]=="T" && match_buffer[3]=="Y" && match_buffer[4]=="V" && match_buffer[5]=="A" && match_buffer[6]=="L") parsed_key_id_next = KEY_ID_DUTYVAL;
                        else if (match_ptr == 6 && match_buffer[0]=="E" && match_buffer[1]=="N" && match_buffer[2]=="A" && match_buffer[3]=="B" && match_buffer[4]=="L" && match_buffer[5]=="E") parsed_key_id_next = KEY_ID_ENABLE;
                    CMD_ID_SPI: 
                        if (match_ptr == 2 && match_buffer[0]=="C" && match_buffer[1]=="S") parsed_key_id_next = KEY_ID_CS;
                        else if (match_ptr == 4 && match_buffer[0]=="M" && match_buffer[1]=="O" && match_buffer[2]=="D" && match_buffer[3]=="E") parsed_key_id_next = KEY_ID_MODE;
                        else if (match_ptr == 7 && match_buffer[0]=="D" && match_buffer[1]=="I" && match_buffer[2]=="V" && match_buffer[3]=="I" && match_buffer[4]=="S" && match_buffer[5]=="O" && match_buffer[6]=="R") parsed_key_id_next = KEY_ID_DIVISOR;
                        else if (match_ptr == 3 && match_buffer[0]=="L" && match_buffer[1]=="E" && match_buffer[2]=="N") parsed_key_id_next = KEY_ID_LEN;
                        else if (match_ptr == 4 && match_buffer[0]=="D" && match_buffer[1]=="A" && match_buffer[2]=="T" && match_buffer[3]=="A") parsed_key_id_next = KEY_ID_DATA;
                    CMD_ID_UART: 
                        if (match_ptr == 7 && match_buffer[0]=="D" && match_buffer[1]=="I" && match_buffer[2]=="V" && match_buffer[3]=="I" && match_buffer[4]=="S" && match_buffer[5]=="O" && match_buffer[6]=="R") parsed_key_id_next = KEY_ID_DIVISOR;
                        else if (match_ptr == 4 && match_buffer[0]=="B" && match_buffer[1]=="I" && match_buffer[2]=="T" && match_buffer[3]=="S") parsed_key_id_next = KEY_ID_BITS;
                        else if (match_ptr == 6 && match_buffer[0]=="P" && match_buffer[1]=="A" && match_buffer[2]=="R" && match_buffer[3]=="I" && match_buffer[4]=="T" && match_buffer[5]=="Y") parsed_key_id_next = KEY_ID_PARITY;
                        else if (match_ptr == 4 && match_buffer[0]=="S" && match_buffer[1]=="T" && match_buffer[2]=="O" && match_buffer[3]=="P") parsed_key_id_next = KEY_ID_STOP;
                        // (移除 "MODE=" 检查)
                        else if (match_ptr == 3 && match_buffer[0]=="L" && match_buffer[1]=="E" && match_buffer[2]=="N") parsed_key_id_next = KEY_ID_LEN;
                        else if (match_ptr == 4 && match_buffer[0]=="D" && match_buffer[1]=="A" && match_buffer[2]=="T" && match_buffer[3]=="A") parsed_key_id_next = KEY_ID_DATA;
                    CMD_ID_IIC: 
                        if (match_ptr == 4 && match_buffer[0]=="A" && match_buffer[1]=="D" && match_buffer[2]=="D" && match_buffer[3]=="R") parsed_key_id_next = KEY_ID_ADDR;
                        else if (match_ptr == 7 && match_buffer[0]=="D" && match_buffer[1]=="I" && match_buffer[2]=="V" && match_buffer[3]=="I" && match_buffer[4]=="S" && match_buffer[5]=="O" && match_buffer[6]=="R") parsed_key_id_next = KEY_ID_DIVISOR;
                        else if (match_ptr == 4 && match_buffer[0]=="W" && match_buffer[1]=="L" && match_buffer[2]=="E" && match_buffer[3]=="N") parsed_key_id_next = KEY_ID_WLEN;
                        else if (match_ptr == 5 && match_buffer[0]=="W" && match_buffer[1]=="D" && match_buffer[2]=="A" && match_buffer[3]=="T" && match_buffer[4]=="A") parsed_key_id_next = KEY_ID_WDATA;
                        else if (match_ptr == 4 && match_buffer[0]=="R" && match_buffer[1]=="L" && match_buffer[2]=="E" && match_buffer[3]=="N") parsed_key_id_next = KEY_ID_RLEN;
                    CMD_ID_CAN: 
                        if (match_ptr == 2 && match_buffer[0]=="I" && match_buffer[1]=="D") parsed_key_id_next = KEY_ID_ID;
                        else if (match_ptr == 3 && match_buffer[0]=="E" && match_buffer[1]=="X" && match_buffer[2]=="T") parsed_key_id_next = KEY_ID_EXT;
                        else if (match_ptr == 3 && match_buffer[0]=="R" && match_buffer[1]=="T" && match_buffer[2]=="R") parsed_key_id_next = KEY_ID_RTR;
                        else if (match_ptr == 3 && match_buffer[0]=="D" && match_buffer[1]=="L" && match_buffer[2]=="C") parsed_key_id_next = KEY_ID_DLC;
                        else if (match_ptr == 4 && match_buffer[0]=="D" && match_buffer[1]=="A" && match_buffer[2]=="T" && match_buffer[3]=="A") parsed_key_id_next = KEY_ID_DATA;
                        else if (match_ptr == 7 && match_buffer[0]=="B" && match_buffer[1]=="I" && match_buffer[2]=="T" && match_buffer[3]=="R" && match_buffer[4]=="A" && match_buffer[5]=="T" && match_buffer[6]=="E") parsed_key_id_next = KEY_ID_BITRATE;
                    CMD_ID_SEQ:
                        if      (match_ptr == 2 && match_buffer[0]=="C" && match_buffer[1]=="H") parsed_key_id_next = KEY_ID_CH;
                        else if (match_ptr == 3 && match_buffer[0]=="L" && match_buffer[1]=="E" && match_buffer[2]=="N") parsed_key_id_next = KEY_ID_LEN;
                        else if (match_ptr == 4 && match_buffer[0]=="L" && match_buffer[1]=="O" && match_buffer[2]=="O" && match_buffer[3]=="P") parsed_key_id_next = KEY_ID_LOOP;
                        else if (match_ptr == 7 && match_buffer[0]=="D" && match_buffer[1]=="I" && match_buffer[2]=="V" && match_buffer[3]=="I" && match_buffer[4]=="S" && match_buffer[5]=="O" && match_buffer[6]=="R") parsed_key_id_next = KEY_ID_DIVISOR;
                        else if (match_ptr == 4 && match_buffer[0]=="D" && match_buffer[1]=="A" && match_buffer[2]=="T" && match_buffer[3]=="A") parsed_key_id_next = KEY_ID_DATA;
                        else if (match_ptr == 6 && match_buffer[0]=="E" && match_buffer[1]=="N" && match_buffer[2]=="A" && match_buffer[3]=="B" && match_buffer[4]=="L" && match_buffer[5]=="E") parsed_key_id_next = KEY_ID_ENABLE;
                        else if (match_ptr == 7 && match_buffer[0]=="S" && match_buffer[1]=="Y" && match_buffer[2]=="N" && match_buffer[3]=="C" && match_buffer[4]=="_" && match_buffer[5]=="G" && match_buffer[6]=="O") parsed_key_id_next = KEY_ID_SYNC_GO;
                    default: parsed_key_id_next = KEY_ID_NONE;
                endcase
                if (parsed_key_id_next == KEY_ID_NONE) next_state = S_IDLE;
            end

            S_PARSE_VAL: begin
                if (!fifo_empty) begin
                    if (parsed_key_id == KEY_ID_DATA || parsed_key_id == KEY_ID_WDATA || parsed_key_id == KEY_ID_ID) begin // Hex values
                        if ((fifo_dout >= "0" && fifo_dout <= "9") || (fifo_dout >= "a" && fifo_dout <= "f") || (fifo_dout >= "A" && fifo_dout <= "F")) begin
                            fifo_pop = 1'b1;
                            next_state = S_PARSE_VAL;
                            if (fifo_dout >= "0" && fifo_dout <= "9") digit_value = fifo_dout - "0";
                            else if (fifo_dout >= "a" && fifo_dout <= "f") digit_value = fifo_dout - "a" + 10;
                            else digit_value = fifo_dout - "A" + 10;
                            value_accumulator_next = (value_accumulator << 4) + digit_value;
                        end else begin
                            fifo_pop = 1'b0;
                            next_state = S_PARAM_DONE;
                        end
                    end else begin // Decimal values
                        if (fifo_dout >= "0" && fifo_dout <= "9") begin
                            fifo_pop = 1'b1;
                            next_state = S_PARSE_VAL;
                            value_accumulator_next = value_accumulator * 10 + (fifo_dout - "0");
                        end else begin
                            fifo_pop = 1'b0;
                            next_state = S_PARAM_DONE;
                        end
                    end
                end
            end

            S_PARAM_DONE: begin
                if (!fifo_empty) begin
                    fifo_pop = 1'b1;
                    if(fifo_dout == ";") next_state = S_EXECUTE;
                    else if(fifo_dout == ",") next_state = S_MATCH_KEY;
                    else next_state = S_IDLE;
                end
            end
            
            S_EXECUTE: begin
                cfg_write_next = 1'b1;
                case (parsed_cmd_id)
                    CMD_ID_PWM: // ... (不变) ...
                    case (exec_step_reg)
                        4'd0: begin cfg_addr_next  = `PWM_BASE_ADDR + pwm_ch * `PWM_CHANNEL_STRIDE + `PWM_REG_OFFSET_PERIOD;
                                     cfg_wdata_next = pwm_period; end
                        4'd1: begin cfg_addr_next  = `PWM_BASE_ADDR + pwm_ch * `PWM_CHANNEL_STRIDE + `PWM_REG_OFFSET_DUTY;
                                     cfg_wdata_next = pwm_dutyval; end
                        4'd2: begin cfg_addr_next  = `PWM_BASE_ADDR + pwm_ch * `PWM_CHANNEL_STRIDE + `REG_OFFSET_CTRL;
                                     cfg_wdata_next = {31'b0, pwm_enable}; end
                        default: begin cfg_write_next = 1'b0;
                                     next_state = S_IDLE; end
                    endcase
                    CMD_ID_IIC: // ... (不变) ...
                    case (exec_step_reg)
                        4'd0: begin cfg_addr_next  = `I2C_BASE_ADDR + `I2C_REG_OFFSET_CONFIG;
                                     cfg_wdata_next = iic_divisor; end
                        4'd1: begin cfg_addr_next  = `I2C_BASE_ADDR + `I2C_REG_OFFSET_LEN;
                                     cfg_wdata_next = {16'd0, iic_wlen, iic_rlen}; end
                        4'd2: begin cfg_addr_next  = `I2C_BASE_ADDR + `I2C_REG_OFFSET_TX_DATA0;
                                     cfg_wdata_next = iic_wdata[31:0]; end
                        4'd3: begin cfg_addr_next  = `I2C_BASE_ADDR + `I2C_REG_OFFSET_TX_DATA1;
                                     cfg_wdata_next = iic_wdata[63:32]; end
                        4'd4: begin cfg_addr_next  = `I2C_BASE_ADDR + `I2C_REG_OFFSET_CTRL;
                                     cfg_wdata_next = {24'd0, iic_addr, 1'b1}; end
                        default: begin cfg_write_next = 1'b0;
                                     if (iic_rlen > 0) next_state = S_WAIT_READ_DATA; else next_state = S_IDLE;
                                 end
                    endcase
                    CMD_ID_UART: case(exec_step_reg)
                        // --- 恢复: 移除 KEY_ID_UART_MODE 检查 ---
                        4'd0: begin cfg_addr_next = `UART_BASE_ADDR + `UART_REG_OFFSET_CONFIG;
                                     cfg_wdata_next = { uart_divisor[15:0], 8'd0, uart_stop, uart_parity, uart_bits }; 
                                     if (uart_len > 0) begin
                                         next_state = S_EXECUTE_UART_WAIT; // 跳转到数据发送
                                     end else begin
                                         next_state = S_IDLE; // 仅配置，返回IDLE
                                     end
                             end
                        default: begin cfg_write_next = 1'b0;
                                     next_state = S_IDLE; end
                    endcase
                    CMD_ID_SPI: // ... (不变) ...
                    case (exec_step_reg)
                        4'd0: begin cfg_addr_next  = `SPI_BASE_ADDR + `SPI_REG_OFFSET_CONFIG;
                                     cfg_wdata_next = {spi_divisor[15:0], 14'b0, spi_mode}; end
                        4'd1: begin cfg_addr_next  = `SPI_BASE_ADDR + `SPI_REG_OFFSET_TX_DATA;
                                     cfg_wdata_next = spi_data[31:0]; end
                        4'd2: begin cfg_addr_next  = `SPI_BASE_ADDR + `SPI_REG_OFFSET_TX_DATA;
                                     cfg_wdata_next = spi_data[63:32]; end
                        4'd3: begin cfg_addr_next  = `SPI_BASE_ADDR + `SPI_REG_OFFSET_CTRL;
                                     cfg_wdata_next = {16'b0, spi_len, spi_cs, 3'b0, 1'b1}; end
                        default: begin cfg_write_next = 1'b0;
                                     if (spi_len > 0) next_state = S_WAIT_READ_DATA; else next_state = S_IDLE;
                                 end
                    endcase
                    CMD_ID_CAN: // ... (不变) ...
                    case (exec_step_reg)
                        4'd0: begin cfg_addr_next  = `CAN_BASE_ADDR + `CAN_REG_OFFSET_CONFIG;
                                     cfg_wdata_next = can_bitrate; end
                        4'd1: begin cfg_addr_next  = `CAN_BASE_ADDR + `CAN_REG_OFFSET_DATA0;
                                     cfg_wdata_next = can_data[31:0]; end
                        4'd2: begin cfg_addr_next  = `CAN_BASE_ADDR + `CAN_REG_OFFSET_DATA1;
                                     cfg_wdata_next = can_data[63:32]; end
                        4'd3: begin cfg_addr_next  = `CAN_BASE_ADDR + `CAN_REG_OFFSET_MSG_ID;
                                     cfg_wdata_next = {can_dlc[3], 1'b0, can_rtr, can_ext, can_id}; end
                        4'd4: begin cfg_addr_next  = `CAN_BASE_ADDR + `CAN_REG_OFFSET_CTRL;
                                     cfg_wdata_next = 32'h1; end
                        default: begin cfg_write_next = 1'b0;
                                     next_state = S_IDLE; end
                    endcase
                    CMD_ID_SEQ: // ... (不变) ...
                    begin
                        if (parsed_key_id == KEY_ID_SYNC_GO) begin 
                             case(exec_step_reg)
                                4'd0: begin cfg_addr_next = `SEQ_GLOBAL_CTRL_ADDR;
                                             cfg_wdata_next = 32'h1; end
                                default: begin cfg_write_next = 1'b0;
                                             next_state = S_IDLE; end
                            endcase
                        end else begin 
                            case (exec_step_reg)
                                4'd0: begin cfg_addr_next  = `SEQ_BASE_ADDR + seq_ch * `SEQ_CHANNEL_STRIDE + `SEQ_REG_OFFSET_DATA0;
                                             cfg_wdata_next = seq_data[31:0]; end
                                4'd1: begin cfg_addr_next  = `SEQ_BASE_ADDR + seq_ch * `SEQ_CHANNEL_STRIDE + `SEQ_REG_OFFSET_DATA1;
                                             cfg_wdata_next = seq_data[63:32]; end
                                4'd2: begin cfg_addr_next  = `SEQ_BASE_ADDR + seq_ch * `SEQ_CHANNEL_STRIDE + `SEQ_REG_OFFSET_DATA2;
                                             cfg_wdata_next = seq_data[95:64]; end
                                4'd3: begin cfg_addr_next  = `SEQ_BASE_ADDR + seq_ch * `SEQ_CHANNEL_STRIDE + `SEQ_REG_OFFSET_DATA3;
                                             cfg_wdata_next = seq_data[127:96]; end
                                4'd4: begin cfg_addr_next  = `SEQ_BASE_ADDR + seq_ch * `SEQ_CHANNEL_STRIDE + `SEQ_REG_OFFSET_DATA4;
                                             cfg_wdata_next = seq_data[159:128]; end
                                4'd5: begin cfg_addr_next  = `SEQ_BASE_ADDR + seq_ch * `SEQ_CHANNEL_STRIDE + `SEQ_REG_OFFSET_DATA5;
                                             cfg_wdata_next = seq_data[191:160]; end
                                4'd6: begin cfg_addr_next  = `SEQ_BASE_ADDR + seq_ch * `SEQ_CHANNEL_STRIDE + `SEQ_REG_OFFSET_DATA6;
                                             cfg_wdata_next = seq_data[223:192]; end
                                4'd7: begin cfg_addr_next  = `SEQ_BASE_ADDR + seq_ch * `SEQ_CHANNEL_STRIDE + `SEQ_REG_OFFSET_DATA7;
                                             cfg_wdata_next = seq_data[255:224]; end
                                4'd8: begin cfg_addr_next  = `SEQ_BASE_ADDR + seq_ch * `SEQ_CHANNEL_STRIDE + `SEQ_REG_OFFSET_CONFIG;
                                             cfg_wdata_next = {7'h0, seq_loop, 16'h0, seq_len}; end
                                4'd9: begin cfg_addr_next  = `SEQ_BASE_ADDR + seq_ch * `SEQ_CHANNEL_STRIDE + `SEQ_REG_OFFSET_DIVISOR;
                                             cfg_wdata_next = seq_divisor; end
                                4'd10: begin cfg_addr_next  = `SEQ_BASE_ADDR + seq_ch * `SEQ_CHANNEL_STRIDE + `SEQ_REG_OFFSET_CTRL;
                                              cfg_wdata_next = {31'd0, seq_enable}; end
                                default: begin cfg_write_next = 1'b0;
                                             next_state = S_IDLE; end
                            endcase
                        end
                    end
                    default: begin cfg_write_next = 1'b0;
                                 next_state = S_IDLE; end
                endcase
            end
            
            S_EXECUTE_UART_WAIT: begin
                // --- 恢复: 移除流控检查 (我们假设 8 字节的 FIFO 足够) ---
                if (exec_step_reg < uart_len) begin
                    cfg_write_next = 1'b1; 
                    cfg_addr_next = `UART_BASE_ADDR + `UART_REG_OFFSET_TX_DATA;
                    next_state = S_EXECUTE_UART_WAIT; // 保持状态
                    
                    // (数据已在 S_PARAM_DONE 中左对齐)
                    case (exec_step_reg)
                        4'd0: cfg_wdata_next = {24'h0, uart_data[63:56]};
                        4'd1: cfg_wdata_next = {24'h0, uart_data[55:48]};
                        4'd2: cfg_wdata_next = {24'h0, uart_data[47:40]}; 
                        4'd3: cfg_wdata_next = {24'h0, uart_data[39:32]};
                        4'd4: cfg_wdata_next = {24'h0, uart_data[31:24]};
                        4'd5: cfg_wdata_next = {24'h0, uart_data[23:16]};
                        4'd6: cfg_wdata_next = {24'h0, uart_data[15:8]};  
                        4'd7: cfg_wdata_next = {24'h0, uart_data[7:0]};
                        default: cfg_wdata_next = 32'h0;
                    endcase
                end else begin
                    cfg_write_next = 1'b0;
                    next_state = S_IDLE; // 发送完毕
                end
            end

            S_WAIT_READ_DATA: begin
                if (periph_valid && !tx_fifo_full) begin
                    tx_fifo_push = 1'b1;
                    tx_fifo_din = periph_rdata;
                end
                if (read_len_counter == 0) begin
                    next_state = S_IDLE;
                end
            end
            
            // (移除 S_UART_PASSTHROUGH 状态)

            default: next_state = S_IDLE;
        endcase
    end
endmodule