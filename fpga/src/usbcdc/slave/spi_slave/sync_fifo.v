`timescale 1ns / 1ps

// ===========================================================================
// ** Module: sync_fifo **
// ** Description: (全新模块) **
//   一个通用的、参数化的同步 FIFO (读写时钟相同)。
//   使用 'almost_full' 和 'almost_empty' 逻辑 (虽然在此处未用满)
//   来确保指针比较的正确性。
// ===========================================================================
module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4  // 2^ADDR_WIDTH = 深度
)(
    input             clk,
    input             rst_n,

    // Write Interface
    input             winc,  // 写使能 (write increment)
    input [DATA_WIDTH-1:0] wdata,
    output            wfull,

    // Read Interface
    input             rinc,  // 读使能 (read increment)
    output [DATA_WIDTH-1:0] rdata,
    output            rempty
);

    localparam FIFO_DEPTH = (1 << ADDR_WIDTH);

    // Memory
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    // Pointers
    reg [ADDR_WIDTH:0] wptr; // 扩展 1 位以区分满/空
    reg [ADDR_WIDTH:0] rptr;

    // Internal full/empty signals
    wire wfull_internal;
    wire rempty_internal;
    
    // Read data output
    assign rdata = mem[rptr[ADDR_WIDTH-1:0]];

    // Write operation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= 0;
        end else begin
            if (winc && !wfull_internal) begin
                mem[wptr[ADDR_WIDTH-1:0]] <= wdata;
                wptr <= wptr + 1'b1;
            end
        end
    end

    // Read operation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rptr <= 0;
        end else begin
            if (rinc && !rempty_internal) begin
                rptr <= rptr + 1'b1;
            end
        end
    end

    // Full/Empty logic
    assign wfull_internal = (wptr[ADDR_WIDTH] != rptr[ADDR_WIDTH]) && 
                            (wptr[ADDR_WIDTH-1:0] == rptr[ADDR_WIDTH-1:0]);
    assign rempty_internal = (wptr == rptr);

    assign wfull  = wfull_internal;
    assign rempty = rempty_internal;

endmodule