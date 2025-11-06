//Copyright (C)2014-2023 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.9
//Part Number: GW5AT-LV138PG484AC1/I0
//Device: GW5AT-138
//Device Version: B
//Created Time: Thu Nov  6 15:26:59 2025

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

	CAN_Top your_instance_name(
		.sysclk(sysclk_i), //input sysclk
		.canclk(canclk_i), //input canclk
		.ponrst_n(ponrst_n_i), //input ponrst_n
		.cfgstrp_clkdiv(cfgstrp_clkdiv_i), //input [7:0] cfgstrp_clkdiv
		.cbus_rxd(cbus_rxd_i), //input cbus_rxd
		.cbus_txd(cbus_txd_o), //output cbus_txd
		.cpu_cs(cpu_cs_i), //input cpu_cs
		.cpu_read(cpu_read_i), //input cpu_read
		.cpu_write(cpu_write_i), //input cpu_write
		.cpu_addr(cpu_addr_i), //input [31:0] cpu_addr
		.cpu_wdat(cpu_wdat_i), //input [31:0] cpu_wdat
		.cpu_rdat(cpu_rdat_o), //output [31:0] cpu_rdat
		.cpu_ack(cpu_ack_o), //output cpu_ack
		.cpu_err(cpu_err_o), //output cpu_err
		.int_o(int_o_o) //output int_o
	);

//--------Copy end-------------------
