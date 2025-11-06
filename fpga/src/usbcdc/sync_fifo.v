//
// 模块: sync_fifo.v
// 描述: 一个简单的同步 FIFO (单时钟域)
//
`timescale 1ns / 1ps

module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4  // 4 -> 16 个条目
)(
    input                          clk,
    input                          rst_n,

    // Write Port
    input                          winc,
    input      [DATA_WIDTH-1:0]    wdata,
    output                         wfull,

    // Read Port
    input                          rinc,
    output     [DATA_WIDTH-1:0]    rdata,
    output                         rempty
);

    localparam FIFO_DEPTH = (1 << ADDR_WIDTH);

    reg [DATA_WIDTH-1:0]    mem [0:FIFO_DEPTH-1];
    reg [ADDR_WIDTH-1:0]    waddr, raddr;
    reg [ADDR_WIDTH:0]      ptr; // 多一位用于区分满/空
    
    wire [ADDR_WIDTH:0]     wptr_next, rptr_next;
    wire                    fifo_empty, fifo_full;
    
    // --- 指针逻辑 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            waddr <= 0;
            raddr <= 0;
            ptr   <= 0;
        end else begin
            if (winc && !fifo_full) begin
                mem[waddr] <= wdata;
                waddr <= waddr + 1;
                ptr   <= ptr + 1;
            end
            
            if (rinc && !fifo_empty) begin
                raddr <= raddr + 1;
                ptr   <= ptr - 1;
            end
        end
    end

    // --- 满/空 状态 ---
    assign fifo_empty = (ptr == 0);
    assign fifo_full  = (ptr == FIFO_DEPTH);

    // --- 输出 ---
    assign rdata  = mem[raddr];
    assign wfull  = fifo_full;
    assign rempty = fifo_empty;

endmodule