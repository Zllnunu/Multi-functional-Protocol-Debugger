
`timescale 1ns/1ps
module tb ;
    reg sysclk ; 
    reg canclk ; 
    reg ponrst_n ; 
    reg [7:0] cfgstrp_clkdiv ; 
    reg send, send1 ; 
    reg rec, rec1 ; 
    wire cbus_t0 ; 
    wire cbus_t1 ; 
    wand c ; 
    assign c = cbus_t0 ; 
    assign c = cbus_t1 ; 
    top top_uut (.sysclk(sysclk), .canclk(canclk), .ponrst_n(ponrst_n), .cfgstrp_clkdiv(cfgstrp_clkdiv), .send(send), .rec(rec), .cbus_rxd(c), .cbus_txd(cbus_t0)) ; 
    top top_uut1 (.sysclk(sysclk), .canclk(canclk), .ponrst_n(ponrst_n), .cfgstrp_clkdiv(cfgstrp_clkdiv), .send(send1), .rec(rec1), .cbus_rxd(c), .cbus_txd(cbus_t1)) ; 
    initial
        begin
            cfgstrp_clkdiv = 8'd10 ;
        end
    initial
        begin
            sysclk = 0 ;
            forever
                #(5) sysclk = (~sysclk) ;
        end
    initial
        begin
            canclk = 0 ;
            forever
                #(50) canclk = (~canclk) ;
        end
    initial
        begin
            ponrst_n = 0 ;
            #(60000) ponrst_n = 1 ;
        end
    initial
        begin
            send = 0 ;
            send1 = 0 ;
            #(150000) send = 1 ;
            #(165) send = 0 ;
        end
    initial
        begin
            rec = 0 ;
            rec1 = 0 ;
            #(1500000) rec1 = 1 ;
            #(245) rec1 = 0 ;
        end
    initial
        begin
            #(2000000) $finish  ;
        end
    initial
        begin
            $fsdbDumpfile ("can_tb_verdi.fsdb") ;
            $fsdbDumpvars  ;
        end
endmodule



`timescale 1ns/1ps
module top (sysclk, canclk, ponrst_n, cfgstrp_clkdiv, send, rec, cbus_rxd, cbus_txd) ;
    input sysclk, canclk, ponrst_n ; 
    input [7:0] cfgstrp_clkdiv ; 
    input send, rec ; 
    input cbus_rxd ; 
    output cbus_txd ; 
    wire cpu_cs ; 
    wire cpu_read ; 
    wire cpu_write ; 
    wire [31:0] cpu_addr ; 
    wire [31:0] cpu_wdat ; 
    wire [31:0] cpu_rdat ; 
    wire cpu_ack ; 
    wire cpu_err ; 
    wire int_o ; 
    CAN_Top can_uut (.sysclk(sysclk), .canclk(canclk), .ponrst_n(ponrst_n), .cfgstrp_clkdiv(cfgstrp_clkdiv), .cbus_rxd(cbus_rxd), .cbus_txd(cbus_txd), .cpu_cs(cpu_cs), .cpu_read(cpu_read), .cpu_write(cpu_write), .cpu_addr(cpu_addr), .cpu_wdat(cpu_wdat), .cpu_rdat(cpu_rdat), .cpu_ack(cpu_ack), .cpu_err(cpu_err), .int_o(int_o)) ; 
    REG reg_uut (.sysclk(sysclk), .ponrst_n(ponrst_n), .send(send), .rec(rec), .cpu_cs(cpu_cs), .cpu_ack(cpu_ack), .cpu_addr(cpu_addr), .cpu_wdat(cpu_wdat), .cpu_rdat(cpu_rdat), .cpu_write(cpu_write), .cpu_read(cpu_read)) ; 
endmodule



`timescale 1ns/1ps
module REG (sysclk, ponrst_n, send, rec, cpu_cs, cpu_ack, cpu_addr, cpu_wdat, cpu_rdat, cpu_write, cpu_read) ;
    input sysclk, ponrst_n ; 
    input send, rec ; 
    input cpu_ack ; 
    input [31:0] cpu_rdat ; 
    output reg cpu_cs ; 
    output reg [31:0] cpu_addr ; 
    output reg [31:0] cpu_wdat ; 
    output reg cpu_write ; 
    output reg cpu_read ; 
    reg [11:0] ini_cnt ; 
    reg [3:0] start_cnt ; 
    reg [1:0] cnt ; 
    reg [1:0] cs ; 
    reg [1:0] ns ; 
    parameter idle = 2'b00 ; 
    parameter send_s = 2'b01 ; 
    parameter rec_s = 2'b10 ; 
    parameter ini_s = 2'b11 ; 
    wire [31:0] txhdr2 ; 
    wire [31:0] txhdr1 ; 
    wire [31:0] send_data1 ; 
    wire [31:0] send_data2 ; 
    parameter IDE = 1'b0 ; 
    parameter RTR = 1'b0 ; 
    parameter EDL = 1'b0 ; 
    parameter BID = 11'b10101010101 ; 
    parameter IE = 18'b0 ; 
    parameter BRS = 0 ; 
    parameter RSVD = 24'b0 ; 
    parameter NUMBYTES = 7'd8 ; 
    assign txhdr1 = {IDE,RTR,EDL,BID,IE} ; 
    assign txhdr2 = {BRS,RSVD,NUMBYTES} ; 
    assign send_data1 = 32'h7c01a579 ; 
    assign send_data2 = 32'h88888888 ; 
    always
        @(posedge sysclk or negedge ponrst_n)
        begin
            if ((!ponrst_n)) 
                cpu_cs <=  0 ;
            else
                if (cpu_ack) 
                    cpu_cs <=  0 ;
                else
                    if ((cs != idle)) 
                        cpu_cs <=  1 ;
                    else
                        cpu_cs <=  0 ;
        end
    always
        @(posedge sysclk or negedge ponrst_n)
        begin
            if ((!ponrst_n)) 
                cpu_write <=  0 ;
            else
                if (cpu_ack) 
                    cpu_write = 0 ;
                else
                    if (((cs == ini_s) || (cs == send_s))) 
                        cpu_write = 1 ;
                    else
                        cpu_write <=  cpu_write ;
        end
    always
        @(posedge sysclk or negedge ponrst_n)
        begin
            if ((!ponrst_n)) 
                cpu_read <=  0 ;
            else
                if (cpu_ack) 
                    cpu_read <=  0 ;
                else
                    if ((cs == rec_s)) 
                        cpu_read <=  1 ;
                    else
                        cpu_read <=  cpu_read ;
        end
    wire ini_done ; 
    parameter brp_addr = 32'h0008 ; 
    parameter btn_addr = 32'h000c ; 
    parameter btd_addr = 32'h0010 ; 
    parameter rb_addr = 32'h0040 ; 
    parameter tb_addr = 32'h0044 ; 
    parameter thb_addr = 32'h0048 ; 
    parameter ie_addr = 32'h0024 ; 
    parameter af1_addr = 32'h0100 ; 
    parameter af2_addr = 32'h0104 ; 
    parameter cmd_addr = 32'h0004 ; 
    parameter brp_data = 32'h000a ; 
    parameter btn_data = {3'b0,5'b00001,10'b0,6'd4,2'b0,6'd4} ; 
    parameter btd_data = {3'b0,5'b00001,10'b0,6'd4,2'b0,6'd4} ; 
    parameter rb_data = 32'h00030000 ; 
    parameter thb_data = 32'h000f0008 ; 
    parameter tb_data = 32'h00070004 ; 
    parameter ie_data = 32'h1 ; 
    parameter af1_data = 32'h80000000 ; 
    parameter af2_data = 32'ha0000000 ; 
    parameter cmd_data = 1 ; 
    parameter brp = 4'd0 ; 
    parameter btn = 4'd1 ; 
    parameter btd = 4'd2 ; 
    parameter rb = 4'd3 ; 
    parameter tb = 4'd4 ; 
    parameter thb = 4'd5 ; 
    parameter ie = 4'd6 ; 
    parameter af1 = 4'd7 ; 
    parameter af2 = 4'd8 ; 
    parameter cmd = 4'd9 ; 
    always
        @(posedge sysclk or negedge ponrst_n)
        begin
            if ((!ponrst_n)) 
                ini_cnt <=  0 ;
            else
                if ((ini_cnt < 12'd3500)) 
                    ini_cnt <=  (ini_cnt + 1) ;
                else
                    ini_cnt <=  ini_cnt ;
        end
    always
        @(posedge sysclk or negedge ponrst_n)
        begin
            if ((!ponrst_n)) 
                start_cnt <=  0 ;
            else
                if ((((start_cnt < 4'd10) && (cs == ini_s)) && (cpu_ack == 1))) 
                    start_cnt <=  (start_cnt + 1) ;
                else
                    start_cnt <=  start_cnt ;
        end
    assign ini_done = ((start_cnt >= 4'd10) ? 1'b1 : 1'b0) ; 
    always
        @(posedge sysclk or negedge ponrst_n)
        begin
            if ((!ponrst_n)) 
                cnt <=  0 ;
            else
                if ((((cs == send_s) || (cs == rec_s)) && (cpu_ack == 1))) 
                    cnt <=  (cnt + 1) ;
                else
                    if ((cs == idle)) 
                        cnt <=  0 ;
                    else
                        cnt <=  cnt ;
        end
    always
        @(posedge sysclk or negedge ponrst_n)
        begin
            if ((!ponrst_n)) 
                cs <=  idle ;
            else
                cs <=  ns ;
        end
    always
        @(*)
        begin
            case (cs)
            idle : 
                begin
                    if (((start_cnt < 9) && (ini_cnt >= 12'd3500))) 
                        ns = ini_s ;
                    else
                        if (((send == 1) && (ini_done == 1))) 
                            ns = send_s ;
                        else
                            if (((rec == 1) && (ini_done == 1))) 
                                ns = rec_s ;
                            else
                                ns = idle ;
                end
            ini_s : 
                begin
                    if (((start_cnt >= 9) && (cpu_ack == 1))) 
                        ns = idle ;
                    else
                        ns = ini_s ;
                end
            send_s : 
                begin
                    if (((cnt == 3) && (cpu_ack == 1))) 
                        ns = idle ;
                    else
                        if ((!send)) 
                            ns = idle ;
                        else
                            ns = send_s ;
                end
            rec_s : 
                begin
                    if ((!rec)) 
                        ns = idle ;
                    else
                        ns = rec_s ;
                end
            endcase 
        end
    always
        @(*)
        begin
            case (cs)
            idle : 
                begin
                    cpu_write = 0 ;
                    cpu_read = 0 ;
                    cpu_wdat = 0 ;
                    cpu_addr = 0 ;
                end
            ini_s : 
                begin
                    case (start_cnt)
                    brp : 
                        begin
                            cpu_addr = brp_addr ;
                            cpu_wdat = brp_data ;
                        end
                    btn : 
                        begin
                            cpu_addr = btn_addr ;
                            cpu_wdat = btn_data ;
                        end
                    btd : 
                        begin
                            cpu_addr = btd_addr ;
                            cpu_wdat = btd_data ;
                        end
                    rb : 
                        begin
                            cpu_addr = rb_addr ;
                            cpu_wdat = rb_data ;
                        end
                    tb : 
                        begin
                            cpu_addr = tb_addr ;
                            cpu_wdat = tb_data ;
                        end
                    thb : 
                        begin
                            cpu_addr = thb_addr ;
                            cpu_wdat = thb_data ;
                        end
                    ie : 
                        begin
                            cpu_addr = ie_addr ;
                            cpu_wdat = ie_data ;
                        end
                    af1 : 
                        begin
                            cpu_addr = af1_addr ;
                            cpu_wdat = af1_data ;
                        end
                    af2 : 
                        begin
                            cpu_addr = af2_addr ;
                            cpu_wdat = af2_data ;
                        end
                    cmd : 
                        begin
                            cpu_addr = cmd_addr ;
                            cpu_wdat = cmd_data ;
                        end
                    default : 
                        begin
                            cpu_addr = 0 ;
                            cpu_wdat = 0 ;
                        end
                    endcase 
                end
            send_s : 
                begin
                    cpu_addr = 32'h0204 ;
                    case (cnt)
                    0 : 
                        cpu_wdat = txhdr1 ;
                    1 : 
                        cpu_wdat = txhdr2 ;
                    2 : 
                        cpu_wdat = send_data1 ;
                    3 : 
                        begin
                            cpu_wdat = send_data2 ;
                        end
                    default : 
                        begin
                            cpu_wdat = 0 ;
                        end
                    endcase 
                end
            rec_s : 
                begin
                    cpu_addr = 32'h0200 ;
                    cpu_wdat = 0 ;
                end
            endcase 
        end
endmodule


