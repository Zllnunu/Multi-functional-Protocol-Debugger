// fx2_fifo_crtl.v (官方例程的核心驱动模块)
`timescale 1ns / 1ps

module fx2_fifo_crtl (
    input fx2_ifclk,
    input reset_n,
    input fx2_flagb,  // 端点2 OUT空标志，1为非空
    input fx2_flagc,  // 端点6 IN满标志，1为非满
    output reg [1:0] fx2_faddr,
    output reg fx2_sloe,
    output reg fx2_slwr,
    output reg fx2_slrd,

    input rx_fifo_empty,	// (FPGA->PC FIFO) 空标志
    input rx_fifo_full,		// (FPGA->PC FIFO) 满标志
    input tx_fifo_full,		// (PC->FPGA FIFO) 满标志

    output reg tx_fifo_push, // (PC->FPGA FIFO) 写使能
    output reg rx_fifo_pop,  // (FPGA->PC FIFO) 读使能
   
    output fx2_pkt_end
);

  reg [3:0] SM_State;
  localparam S_IDLE = 4'b0001;
  localparam S_READ = 4'b0010;
  localparam S_WRITE_WAIT = 4'b0100;
  localparam S_WRITE = 4'b1000;

  reg [3:0] delay_cnt;
  reg [3:0] rst_delay_cnt; // 新增：复位延时计数器
  wire      delay_done;    // 新增：延时完成标志

  // 新增：控制复位延时计数器
  always @(posedge fx2_ifclk or negedge reset_n) begin
      if (!reset_n) begin
          rst_delay_cnt <= 0;
      end else if (rst_delay_cnt < 4'd2) begin // 延时2个时钟周期
          rst_delay_cnt <= rst_delay_cnt + 1'b1;
      end
  end
  assign delay_done = (rst_delay_cnt == 4'd2);

  // 原始逻辑：控制状态机空闲时的延时
  always @(posedge fx2_ifclk or negedge reset_n) begin
    if (~reset_n) begin
      delay_cnt <= 4'd0;
    end else if (SM_State == S_IDLE) begin
      if (delay_cnt >= 4'd8) begin
        delay_cnt <= 4'd8;
      end else begin
        delay_cnt <= delay_cnt + 4'd1;
      end
    end else begin
      delay_cnt <= 4'd0;
    end
  end

  always @(posedge fx2_ifclk or negedge reset_n) begin
    if (~reset_n) begin
      SM_State <= S_IDLE;
    end else begin
      case (SM_State)
        S_IDLE: begin
          if (!delay_done) begin // 修改：只有在复位延时完成后才开始
            SM_State <= S_IDLE;
          end else if (~rx_fifo_empty) begin
            SM_State <= S_WRITE_WAIT;
          end else if ((~tx_fifo_full) && (fx2_flagb)) begin
            SM_State <= S_READ;
          end else begin
            SM_State <= S_IDLE;
          end
        end
        S_READ: begin
          if (rx_fifo_full) begin
            SM_State <= S_WRITE_WAIT;
          end else if((~fx2_flagb) || (tx_fifo_full)) begin
            SM_State <= S_IDLE;
          end else begin
            SM_State <= S_READ;
          end
        end
        S_WRITE_WAIT: begin
          if (fx2_flagc) begin
            SM_State <= S_WRITE;
          end else if(rx_fifo_full) begin
            SM_State <= S_WRITE_WAIT;
          end else begin
            SM_State <= S_IDLE;
          end
        end
        S_WRITE: begin
          if ((~fx2_flagc) || (rx_fifo_empty)) begin
            SM_State <= S_IDLE;
          end else begin
            SM_State <= S_WRITE;
          end
        end
        default: SM_State <= S_IDLE;
      endcase
    end
  end

  always @(*) begin
    if (((SM_State == S_IDLE) && (delay_cnt >= 4'd3)) || (SM_State == S_READ)) begin
      fx2_faddr = 2'b00;
    end else begin
      fx2_faddr = 2'b10;
    end
  end

  always @(*) begin
    if (((~tx_fifo_full)) && (fx2_flagb == 1'b1) && (SM_State == S_READ)) begin
      fx2_slrd     = 1'b0;
      fx2_sloe     = 1'b0;
      tx_fifo_push = 1'b1;
    end else begin
      fx2_slrd     = 1'b1;
      fx2_sloe     = 1'b1;
      tx_fifo_push = 1'b0;
    end
  end

  always @(*) begin
    if (((~rx_fifo_empty)) && (fx2_flagc == 1'b1) && (SM_State == S_WRITE)) begin
      fx2_slwr    = 1'b0;
      rx_fifo_pop = 1'b1;
    end else begin
      fx2_slwr    = 1'b1;
      rx_fifo_pop = 1'b0;
    end
  end

  assign fx2_pkt_end = ((SM_State == S_IDLE) && (delay_cnt < 4'd3)) ? 1'b0 : 1'b1;

endmodule