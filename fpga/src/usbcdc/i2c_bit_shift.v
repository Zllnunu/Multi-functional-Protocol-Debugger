`timescale 1ns / 1ps

// ** 最终修正版 **
// 修复了 GEN_ACK 状态下主机ACK无法被正确拉低的问题
module i2c_bit_shift(
	input             Clk,
	input             Rst_n,
	
	input      [5:0]  Cmd,
	input             Go,
	input      [7:0]  Tx_DATA,
	output reg [7:0]  Rx_DATA,
	output reg        Trans_Done,
	output reg        ack_o,
	
	output reg        i2c_sclk,
	inout             i2c_sdat,

    output            i2c_sdat_o,
    output            i2c_sdat_oe
);
    reg i2c_sdat_o_reg;
    reg i2c_sdat_oe_reg;

    assign i2c_sdat_o = i2c_sdat_o_reg;
    assign i2c_sdat_oe = i2c_sdat_oe_reg;

    parameter SYS_CLOCK = 50_000_000;
    parameter SCL_CLOCK = 400_000;
    localparam SCL_CNT_M = SYS_CLOCK/SCL_CLOCK/4 - 1;

    localparam 
        WR   = 6'b000001,
        STA  = 6'b000010,
        RD   = 6'b000100,
        STO  = 6'b001000,
        ACK  = 6'b010000,
        NACK = 6'b100000;
        
    reg [19:0] div_cnt;
    wire       en_div_cnt;

    reg [7:0] state;
    localparam
        IDLE      = 8'b00000001,
        GEN_STA   = 8'b00000010,
        WR_DATA   = 8'b00000100,
        RD_DATA   = 8'b00001000,
        CHECK_ACK = 8'b00010000,
        GEN_ACK   = 8'b00100000,
        GEN_STO   = 8'b01000000;
        
    reg [7:0]  tx_data_reg;

    assign en_div_cnt = (state != IDLE);
    
    always@(posedge Clk or negedge Rst_n)begin
        if(!Rst_n)
            div_cnt <= 20'd0;
        else if(en_div_cnt)begin
            if(div_cnt < SCL_CNT_M)
                div_cnt <= div_cnt + 1'b1;
            else
                div_cnt <= 0;
        end
        else
            div_cnt <= 0;
    end

    wire sclk_plus = (div_cnt == SCL_CNT_M);
	
    reg [4:0] cnt;
    
    always@(posedge Clk or negedge Rst_n)
    if(!Rst_n)begin
        Rx_DATA <= 0;
        i2c_sdat_oe_reg <= 1'd0;
        i2c_sdat_o_reg <= 1'd1;
        Trans_Done <= 1'b0;
        ack_o <= 1'b1;
        state <= IDLE;
        cnt <= 0;
        i2c_sclk <= 1'b1;
        tx_data_reg <= 8'h00;
    end
    else begin
        Trans_Done <= 1'b0;
        case(state)
            IDLE:
                begin
                    i2c_sdat_oe_reg <= 1'd0;
                    i2c_sdat_o_reg  <= 1'b1;
                    cnt             <= 0;
                    
                    // IDLE 状态保持 SCL 不变, 等待命令
                    if(Go)begin
                        tx_data_reg <= Tx_DATA;
                        if(Cmd & STA)
                            state <= GEN_STA;
                        else if(Cmd & WR)
                            state <= WR_DATA;
                        else if(Cmd & RD)
                            state <= RD_DATA;
                        else if(Cmd & STO)
                            state <= GEN_STO;
                        else if(Cmd & ACK || Cmd & NACK)
                            state <= GEN_ACK;
                        else
                            state <= IDLE;
                    end
                    else begin
                        state <= IDLE;
                    end
                end
            
            GEN_STA:
                begin
                    if(sclk_plus)begin
                        cnt <= cnt + 1'b1;
                        case(cnt)
                            0: begin i2c_sdat_o_reg <= 1'b1; i2c_sdat_oe_reg <= 1'b1; end
                            1: begin i2c_sclk <= 1'b1; end
                            2: begin i2c_sdat_o_reg <= 1'b0; i2c_sclk <= 1'b1; end
                            3: begin i2c_sclk <= 1'b0; end
                            default: begin i2c_sdat_o_reg <= 1'b1; i2c_sclk <= 1'b1; end
                        endcase
                        if(cnt == 3)begin
                            Trans_Done <= 1'b1;
                            state <= IDLE;
                        end
                    end
                end
            
            WR_DATA:
                begin
                    if(sclk_plus)begin
                        cnt <= cnt + 1'b1;
                        case(cnt)
                            0,4,8,12,16,20,24,28: begin i2c_sdat_o_reg <= tx_data_reg[7-cnt[4:2]]; i2c_sdat_oe_reg <= 1'd1; end
                            1,5,9,13,17,21,25,29: begin i2c_sclk <= 1'b1; end
                            2,6,10,14,18,22,26,30: begin i2c_sclk <= 1'b1; end
                            3,7,11,15,19,23,27,31: begin i2c_sclk <= 1'b0; end
                            default: begin i2c_sdat_o_reg <= 1'b1; i2c_sclk <= 1'b1; end
                        endcase
                        if(cnt == 31)begin
                            state <= CHECK_ACK;
                        end
                    end
                end
                
            RD_DATA:
                begin
                    if(sclk_plus)begin
                        cnt <= cnt + 1'b1;
                        case(cnt)
                            0,4,8,12,16,20,24,28: begin i2c_sdat_oe_reg <= 1'd0; i2c_sclk <= 1'b0; end
                            1,5,9,13,17,21,25,29: begin i2c_sclk <= 1'b1; end
                            2,6,10,14,18,22,26,30: begin i2c_sclk <= 1'b1; Rx_DATA <= {Rx_DATA[6:0],i2c_sdat}; end
                            3,7,11,15,19,23,27,31: begin i2c_sclk <= 1'b0; end
                            default: begin i2c_sdat_o_reg <= 1'b1; i2c_sclk <= 1'b1; end
                        endcase
                        if(cnt == 31)begin
                            Trans_Done <= 1'b1;
                            state <= IDLE;
                        end
                    end
                end
            
            CHECK_ACK:
                begin
                    if(sclk_plus)begin
                        cnt <= cnt + 1'b1;
                        case(cnt)
                            0: begin i2c_sdat_oe_reg <= 1'd0; i2c_sclk <= 1'b0; end
                            1: begin i2c_sclk <= 1'b1; end
                            2: begin ack_o <= i2c_sdat; i2c_sclk <= 1'b1; end
                            3: begin i2c_sclk <= 1'b0; end
                            default: begin i2c_sdat_o_reg <= 1'b1; i2c_sclk <= 1'b1; end
                        endcase
                        if(cnt == 3)begin
                            Trans_Done <= 1'b1;
                            state <= IDLE;							
                        end
                    end
                end
            
            GEN_ACK:
                begin
                    if(sclk_plus)begin
                        cnt <= cnt + 1'b1;
                        case(cnt)
                            0: begin 
                                    i2c_sdat_oe_reg <= 1'd1;
                                    i2c_sclk <= 1'b0;
                                    // ============ 修正开始 ============
                                    // 修复了 if(Cmd & ACK) 导致无法正确拉低SDA的问题
                                    // 直接使用 NACK 位 (Cmd[5]) 赋值:
                                    //   Cmd = ACK  (010000) -> Cmd[5] = 0 -> SDA = 0
                                    //   Cmd = NACK (100000) -> Cmd[5] = 1 -> SDA = 1
                                    i2c_sdat_o_reg <= Cmd[5];
                                    // ============ 修正结束 ============
                                end
                            1: begin i2c_sclk <= 1'b1; end
                            2: begin i2c_sclk <= 1'b1; end
                            3: begin i2c_sclk <= 1'b0; end
                            default: begin i2c_sdat_o_reg <= 1'b1; i2c_sclk <= 1'b1; end
                        endcase
                        if(cnt == 3)begin
                            Trans_Done <= 1'b1;
                            state <= IDLE;
                        end
                    end
                end
            
            GEN_STO:
                begin
                    if(sclk_plus)begin
                        cnt <= cnt + 1'b1;
                        case(cnt)
                            0: begin i2c_sdat_o_reg <= 1'b0; i2c_sdat_oe_reg <= 1'b1; end
                            1: begin i2c_sclk <= 1'b1; end
                            2: begin i2c_sdat_o_reg <= 1'b1; i2c_sclk <= 1'b1; end
                            3: begin i2c_sclk <= 1'b1; end
                            default: begin i2c_sdat_o_reg <= 1'b1; i2c_sclk <= 1'b1; end
                        endcase
                        if(cnt == 3)begin
                            Trans_Done <= 1'b1;
                            state <= IDLE;
                        end
                    end
                end
            default: state <= IDLE;
        endcase
    end
endmodule