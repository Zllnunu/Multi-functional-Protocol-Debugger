`timescale 1ns / 1ps
`include "address_map.vh"

module usb_test1 (
    input             clk,
    input             rst_n,

    // --- USB FX2 接口 ---
    input             usb_ifclk,
    inout      [7:0]  usb_fd,
    output     [1:0]  usb_fifoaddr,
    output            usb_slrd,
    output            usb_slwr,
    output            usb_slcs,
    output            usb_sloe,
    output            usb_pkt_end,
    input             usb_flagb,
    input             usb_flagc,
    
    // --- 外设物理端口 ---
    output            fpga_uart_tx,
    input             fpga_uart_rx,
    output     [3:0]  led_out,

    // --- I2C 物理端口 ---
    output            i2c_scl,
    inout             i2c_sda,
 
    // --- CAN 物理端口 ---
    output            can_tx,
    input             can_rx,
    
    // --- SPI 物理端口 ---
    output            spi_sclk,
    output            spi_mosi,
    input             spi_miso,
    output     [3:0]  spi_cs_n,

    // --- ADDED START ---
    // 新增：自定义序列输出端口
    output     [3:0]  seq_out
    // --- ADDED END ---
);
//================================================================
//== 1. 复位与时钟域同步
//================================================================
    localparam RST_DELAY_TARGET = 17'd50000;
    reg  [16:0] rst_delay_cnt;
    reg         power_on_reset_n_int;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_delay_cnt <= 0;
            power_on_reset_n_int <= 1'b0;
        end else if (rst_delay_cnt < RST_DELAY_TARGET) begin
            rst_delay_cnt <= rst_delay_cnt + 1'b1;
            power_on_reset_n_int <= 1'b0;
        end else begin
            power_on_reset_n_int <= 1'b1;
        end
    end

    reg [1:0] sys_rst_sync;
    reg [1:0] usb_rst_sync;
    wire      sys_reset_n;
    wire      usb_reset_n;
    always @(posedge clk or negedge power_on_reset_n_int) begin
        if (!power_on_reset_n_int) sys_rst_sync <= 2'b00;
        else sys_rst_sync <= {sys_rst_sync[0], 1'b1};
    end
    assign sys_reset_n = sys_rst_sync[1];
    always @(posedge usb_ifclk or negedge power_on_reset_n_int) begin
        if (!power_on_reset_n_int) usb_rst_sync <= 2'b00;
        else usb_rst_sync <= {usb_rst_sync[0], 1'b1};
    end
    assign usb_reset_n = usb_rst_sync[1];
//================================================================
//== 2. USB FIFO 控制与跨时钟域数据通路
//================================================================
    assign usb_slcs = 1'b0;
    wire [7:0] fx2_fdata_in;
    wire [7:0] fx2_fdata_out;
    assign fx2_fdata_out = tx_fifo_rdata;
    assign fx2_fdata_in  = (~usb_slrd) ? usb_fd : 8'h00;
    assign usb_fd        = (~usb_slwr) ? fx2_fdata_out : 8'hZZ;

    wire rx_fifo_winc, rx_fifo_rinc;
    wire rx_fifo_wfull, rx_fifo_rempty;
    wire [7:0] rx_fifo_rdata;

    wire tx_fifo_rinc;
    reg  tx_fifo_winc;
    wire tx_fifo_wfull, tx_fifo_rempty;
    reg  [7:0] tx_fifo_wdata;
    wire [7:0] tx_fifo_rdata;

    fx2_fifo_crtl u_fx2_ctrl (
        .fx2_ifclk(usb_ifclk), .reset_n(usb_reset_n), .fx2_flagb(usb_flagb),
        .fx2_flagc(usb_flagc), .fx2_faddr(usb_fifoaddr), .fx2_sloe(usb_sloe), 
        .fx2_slwr(usb_slwr), .fx2_slrd(usb_slrd), .fx2_pkt_end(usb_pkt_end),
        .rx_fifo_empty(tx_fifo_rempty), .rx_fifo_full(tx_fifo_wfull), .rx_fifo_pop(tx_fifo_rinc),
        .tx_fifo_full(rx_fifo_wfull), .tx_fifo_push(rx_fifo_winc)
    );
    async_fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(10)) u_rx_fifo (
        .wclk(usb_ifclk), .wrst_n(usb_reset_n), .winc(rx_fifo_winc), .wdata(fx2_fdata_in), .wfull(rx_fifo_wfull),
        .rclk(clk), .rrst_n(sys_reset_n), .rinc(rx_fifo_rinc), .rdata(rx_fifo_rdata), .rempty(rx_fifo_rempty)
    );
    async_fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(10)) u_tx_fifo (
        .wclk(clk), .wrst_n(sys_reset_n), .winc(tx_fifo_winc), .wdata(tx_fifo_wdata), .wfull(tx_fifo_wfull),
        .rclk(usb_ifclk), .rrst_n(usb_reset_n), .rinc(tx_fifo_rinc), .rdata(tx_fifo_rdata), .rempty(tx_fifo_rempty)
    );
//================================================================
//== 3. 指令解析与内部总线
//================================================================
    wire [15:0] cfg_addr;
    wire [31:0] cfg_wdata;
    wire        cfg_write;
    wire        parser_tx_push;
    wire [7:0]  parser_tx_din;
    reg  [7:0]  periph_rdata_bus;
    reg         periph_valid_bus;
    wire [2:0]  periph_sel;
    wire        uart_rvalid_out, i2c_rvalid_out, spi_rvalid_out;
    wire [7:0]  uart_rdata_out, i2c_rdata_out, spi_rdata_out;

    command_parser u_command_parser (
        .clk(clk), .rst_n(sys_reset_n), .fifo_dout(rx_fifo_rdata), .fifo_empty(rx_fifo_rempty), .fifo_pop(rx_fifo_rinc),
        .tx_fifo_push(parser_tx_push), .tx_fifo_din(parser_tx_din), .tx_fifo_full(tx_fifo_wfull),
        .periph_rdata(periph_rdata_bus), .periph_valid(periph_valid_bus), .periph_sel(periph_sel),
        .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata), .cfg_write(cfg_write)
        // (移除 uart_tx_fifo_full 端口)
    );

    always @(*) begin
        if (parser_tx_push && !tx_fifo_wfull) begin
            tx_fifo_winc = 1'b1;
            tx_fifo_wdata = parser_tx_din;
        end else if (uart_rvalid_out && !tx_fifo_wfull) begin
            tx_fifo_winc = 1'b1;
            tx_fifo_wdata = uart_rdata_out;
        end else begin
            tx_fifo_winc = 1'b0;
            tx_fifo_wdata = 8'h00;
        end
    end

//================================================================
//== 4. 地址译码与外设例化
//================================================================
    wire pwm_write_en, spi_write_en, i2c_write_en, uart_write_en, can_write_en;
    assign pwm_write_en  = cfg_write && (cfg_addr >= `PWM_BASE_ADDR)  && (cfg_addr < `SPI_BASE_ADDR);
    assign spi_write_en  = cfg_write && (cfg_addr >= `SPI_BASE_ADDR)  && (cfg_addr < `I2C_BASE_ADDR);
    assign i2c_write_en  = cfg_write && (cfg_addr >= `I2C_BASE_ADDR)  && (cfg_addr < `UART_BASE_ADDR);
    assign uart_write_en = cfg_write && (cfg_addr >= `UART_BASE_ADDR) && (cfg_addr < `CAN_BASE_ADDR);
    assign can_write_en  = cfg_write && (cfg_addr >= `CAN_BASE_ADDR)  && (cfg_addr < `SEQ_BASE_ADDR);
    
    wire seq_write_en;
    assign seq_write_en  = cfg_write && (cfg_addr >= `SEQ_BASE_ADDR);

    pwm_controller #(.NUM_CHANNELS(4)) u_pwm_controller (
        .clk(clk), .rst_n(sys_reset_n), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata), .cfg_write(pwm_write_en),
        .pwm_outs(led_out)
    );
    spi_master_wrapper u_spi_master_wrapper (
        .clk(clk), .rst_n(sys_reset_n), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata), .cfg_write(spi_write_en),
        .cfg_rdata_out(spi_rdata_out), .cfg_rvalid_out(spi_rvalid_out),
        .spi_sclk(spi_sclk), .spi_mosi(spi_mosi), .spi_miso(spi_miso), .spi_cs_n(spi_cs_n)
    );
    i2c_master_wrapper u_i2c_master_wrapper (
        .clk(clk), .rst_n(sys_reset_n), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata), .cfg_write(i2c_write_en),
        .cfg_rdata_out(i2c_rdata_out), .cfg_rvalid_out(i2c_rvalid_out), .i2c_scl(i2c_scl), .i2c_sda(i2c_sda)
    );
    uart_wrapper u_uart_wrapper (
        .clk(clk), .rst_n(sys_reset_n), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata), .cfg_write(uart_write_en),
        .cfg_rdata_out(uart_rdata_out), .cfg_rvalid_out(uart_rvalid_out), .uart_rx_pin(fpga_uart_rx), .uart_tx_pin(fpga_uart_tx)
        // (移除 tx_fifo_is_full 端口)
    );
    can_wrapper u_can_wrapper (
        .clk(clk), .rst_n(sys_reset_n), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata), .cfg_write(can_write_en),
        .can_tx(can_tx), .can_rx(can_rx), .irq()
    );
    sequence_generator #(.NUM_CHANNELS(4)) u_seq_gen (
        .clk(clk), 
        .rst_n(sys_reset_n), 
        .cfg_addr(cfg_addr), 
        .cfg_wdata(cfg_wdata), 
        .cfg_write(seq_write_en),
        .seq_outs(seq_out)
    );
    
//================================================================
//== 5. 外设回读数据选择器
//================================================================
    always @(*) begin
        case (periph_sel)
            3'b010: begin // SPI
                periph_rdata_bus = spi_rdata_out;
                periph_valid_bus = spi_rvalid_out;
            end
            3'b011: begin // I2C
                periph_rdata_bus = i2c_rdata_out;
                periph_valid_bus = i2c_rvalid_out;
            end
            default: begin
                periph_rdata_bus = 8'h00;
                periph_valid_bus = 1'b0;
            end
        endcase
    end
    
endmodule