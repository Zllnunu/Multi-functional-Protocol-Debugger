
`resetall

module AHB_LCD_Controller
(
	output	wire	[31:0]	AHB_HRDATA,
	output	wire			AHB_HREADY,
	output	wire	[ 1:0]	AHB_HRESP,
	input	wire	[ 1:0]  AHB_HTRANS,
	input	wire	[ 2:0]  AHB_HBURST,
	input	wire	[ 3:0]  AHB_HPROT,
	input	wire	[ 2:0]	AHB_HSIZE,
	input	wire			AHB_HWRITE,
	input	wire			AHB_HMASTLOCK,
	input	wire	[ 3:0]	AHB_HMASTER,
	input	wire	[31:0]	AHB_HADDR,
	input	wire	[31:0]  AHB_HWDATA,
	input	wire			AHB_HSEL,
	input	wire			AHB_HCLK,
	input	wire			AHB_HRESETn,

    //LCD Interface
    inout [15:0]LCD_DATA,
    output reg LCD_CSn,
    output reg LCD_RS,
    output reg LCD_WRn,
    output reg LCD_RDn,
    output reg LCD_RSTn,
    output reg LCD_BL
    
);

reg [15:0]lcd_data_o;
reg lcd_data_oe;
wire [15:0]lcd_data_i;
//LCD_DATA tri-state
assign LCD_DATA = lcd_data_oe ? lcd_data_o : 16'hZZZZ;
assign lcd_data_i = lcd_data_oe ? 16'hZZZZ : LCD_DATA;


//Define Reg for AHB BUS
reg Done;
reg [31:0]ahb_address;
reg [31:0] ahb_rdata;
reg ahb_control;
reg ahb_sel;
reg ahb_htrans;

assign AHB_HREADY = Done; //ready signal, slave to MCU master
//Response OKAY
assign AHB_HRESP  = 2'b0;//response signal, slave to MCU master



always @(posedge AHB_HCLK or negedge AHB_HRESETn)
begin
	if(~AHB_HRESETn)
	begin
		ahb_address  <= 32'b0;
		ahb_control  <= 1'b0;
        ahb_sel      <= 1'b0;
        ahb_htrans   <= 1'b0;
	end
	else              //Select The AHB Device 
	begin			  //Get the Address of reg
		ahb_address  <= AHB_HADDR;
		ahb_control  <= AHB_HWRITE;
        ahb_sel      <= AHB_HSEL;
        ahb_htrans   <= AHB_HTRANS[1];
	end
end

wire write_enable = ahb_htrans & ahb_control    & ahb_sel;
wire read_enable  = ahb_htrans & (!ahb_control) & ahb_sel;


reg [15:0]Data;
reg Cmd_Flag;   //0:Command , RS Low    1:Display data or Parameter , RS High
reg Start;
reg RD_Flag;    //0:Disable read data   1:Enable read data

//write data to AHB bus
always @(posedge AHB_HCLK or negedge AHB_HRESETn)
begin
	if(~AHB_HRESETn) begin
        Data   <= 16'h0000;
        Cmd_Flag <= 1'b1;
        Start <= 1'b0;
        RD_Flag <= 1'b0;
	end
	else if(write_enable & (ahb_address == 32'h80000000)) begin //Command
        Data <= AHB_HWDATA[15:0];
        Start <= 1'b1;
        Cmd_Flag <= 1'b0;
        RD_Flag <= 1'b0;
	end
	else if(write_enable & (ahb_address == 32'h80000004)) begin //Display data or Parameter
        Data <= AHB_HWDATA[15:0];
        Start <= 1'b1;
        Cmd_Flag <= 1'b1;
        RD_Flag <= 1'b0;
	end
    else if(read_enable & (ahb_address == 32'h80000004)) begin //Display data or id
        Start <= 1'b1;
        Cmd_Flag <= 1'b1;
        RD_Flag <= 1'b1;
	end
    else begin
        Start <= 1'b0;
    end
end


//read data from AHB bus
//always @(posedge AHB_HCLK or negedge AHB_HRESETn)
//begin
//	if(read_enable) begin
//		case (ahb_address[31:0])
//		32'h80000002:  ahb_rdata = Data;
//		default:ahb_rdata = 32'hFFFFFFFF;
//		endcase
//	end
//    else begin
//        ahb_rdata = 32'h00000000;
//    end
//end

assign AHB_HRDATA = ahb_rdata;


reg Start_r;
wire Start_Pos;
assign Start_Pos = Start_r & (~Start);

always @(posedge AHB_HCLK or negedge AHB_HRESETn)
begin
	if(~AHB_HRESETn)
        Start_r  <= 1'b0;

	else 
		Start_r  <= Start;
end

reg [3:0]State;
reg [3:0]Delay_Cnt;

always @(posedge AHB_HCLK or negedge AHB_HRESETn)
if(~AHB_HRESETn) begin
    State <= 3'd0;
    LCD_CSn <= 1'b1;
    LCD_RS <= 1'b1;
    LCD_WRn <= 1'b1;
    LCD_RDn <= 1'b1;
    LCD_RSTn <= 1'b1;
    LCD_BL <= 1'b1;
    lcd_data_o <= 16'h0000;
    Done <= 1'b0;
    Delay_Cnt <= 4'd0;
    ahb_rdata = 32'h00000000;
    lcd_data_oe <= 1'b1;
end
else begin
    case(State)
    4'd0: begin
        if(Start_Pos) begin
            LCD_RS <= Cmd_Flag;
            Done <= 1'b0;
            if(RD_Flag) begin
                State <= 4'd6;
                lcd_data_oe <= 1'b0;
            end
            else begin
                State <= 4'd1;
                lcd_data_oe <= 1'b1;
            end
        end
        else begin
            State <= 4'd0;
            LCD_RS <= LCD_RS;
            Done <= 1'b0;
        end
    end
    
    //Write
    4'd1: begin
        State <= State + 1'b1;
        LCD_CSn <= 1'b0;
    end
    4'd2: begin
        State <= State + 1'b1;
        lcd_data_o <= Data;
    end
    4'd3: begin
        State <= State + 1'b1;
        LCD_WRn <= 1'b0;
    end
    4'd4: begin
        State <= State + 1'b1;
        LCD_WRn <= 1'b1;
    end
    4'd5: begin
        State <= 4'd0;
        LCD_CSn <= 1'b1;
        Done <= 1'b1;
    end

    //Read
    4'd6: begin
        State <= State + 1'b1;
        LCD_RS <= 1'b1;
    end
    4'd7: begin
        State <= State + 1'b1;
        LCD_CSn <= 1'b0;
    end
    4'd8: begin
        LCD_RDn <= 1'b1;
        if(Delay_Cnt < 4'd8) begin  //RDn Hold High 180ns
            Delay_Cnt <= Delay_Cnt + 1'b1;
            State <= State;
        end
        else begin
            Delay_Cnt <= 4'd0;
            State <= State + 1'b1;
        end
    end
    4'd9: begin
        LCD_RDn <= 1'b0;
        if(Delay_Cnt < 4'd7) begin  //RDn Hold Low 160ns
            Delay_Cnt <= Delay_Cnt + 1'b1;
            State <= State;
        end
        else begin
            Delay_Cnt <= 4'd0;
            State <= State + 1'b1;
        end
    end
    4'd10: begin
        State <= State + 1'b1;
        ahb_rdata <= lcd_data_i;
    end
    4'd11: begin
        State <= State + 1'b1;
        LCD_RDn <= 1'b1;
    end
    4'd12: begin
        State <= 4'd0;
        LCD_CSn <= 1'b1;
        Done <= 1'b1;
    end


    default: State <= 4'd0;
    endcase
end
	
endmodule