// async_fifo.v
module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    // Write Domain
    input                 wclk,
    input                 wrst_n,
    input                 winc,
    input      [DATA_WIDTH-1:0] wdata,
    output                wfull,

    // Read Domain
    input                 rclk,
    input                 rrst_n,
    input                 rinc,
    output     [DATA_WIDTH-1:0] rdata,
    output                rempty
);

    reg [DATA_WIDTH-1:0] mem [(2**ADDR_WIDTH)-1:0];
    reg [ADDR_WIDTH-1:0] waddr, raddr;  		//写读指针
    reg [ADDR_WIDTH:0]   wptr, rptr, wq2_rptr, rq2_wptr;

    // Gray code pointers
    wire [ADDR_WIDTH:0] wgray, rgray;
    // 正确声明
    reg [ADDR_WIDTH:0] wq1_rptr, rq1_wptr; // 将同步用的指针全部改为reg

    assign wfull = (wgray == {~rq2_wptr[ADDR_WIDTH:ADDR_WIDTH-1], rq2_wptr[ADDR_WIDTH-2:0]});
    assign rempty = (rgray == wq2_rptr);

    // Write Logic
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            waddr <= 0;
            wptr <= 0;
        end 
        else if (winc && !wfull) begin
            mem[waddr] <= wdata;
            waddr <= waddr + 1;
            wptr <= wptr + 1;
        end
    end

    // Read Logic
    assign rdata = mem[raddr];
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            raddr <= 0;
            rptr <= 0;
        end else if (rinc && !rempty) begin
            raddr <= raddr + 1;
            rptr <= rptr + 1;
        end
    end

    // Binary to Gray conversiondw
    assign wgray = (wptr >> 1) ^ wptr;
    assign rgray = (rptr >> 1) ^ rptr;

    // Synchronization logic for pointers
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            rq1_wptr <= 0;
            rq2_wptr <= 0;
        end else begin
            rq1_wptr <= rgray;
            rq2_wptr <= rq1_wptr;
        end
    end

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            wq1_rptr <= 0;
            wq2_rptr <= 0;
        end else begin
            wq1_rptr <= wgray;
            wq2_rptr <= wq1_rptr;
        end
    end

endmodule