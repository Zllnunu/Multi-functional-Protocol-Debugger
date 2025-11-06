`timescale 1ns / 1ps

// ===========================================================================
// ** MODIFIED VERSION **
// 1. 更改了 SPI 输出端口以匹配 spi_slave_robust (cpol, cpha)
// 2. 增加了 I2C 10位地址模式的输出端口
// 3. 增加了新的 I2C 命令 (0x04, 0x05, 0x06) 来配置 10 位地址
// ===========================================================================
module slave_config_parser (
    input             clk,
    input             rst_n,

    // --- Input Interface (from pre-parser or FIFO) ---
    input      [7:0]  rx_data,    // Received byte
    input             rx_valid,   // Indicates rx_data is valid for one clk cycle

    // --- SPI Slave Configuration Outputs ---
    // ** MODIFIED PORTS (was config_spi_slave_mode) **
    output reg        config_spi_cpol,           // SPI CPOL (Mode[1])
    output reg        config_spi_cpha,           // SPI CPHA (Mode[0])
    output reg        config_spi_mode_valid,     // Pulse high when config is updated

    // --- I2C Slave Configuration Outputs ---
    output reg [6:0]  config_i2c_slave_address,  // 7-bit Slave Address
    output reg        config_i2c_reg_addr_16bit, // 0=8bit reg addr, 1=16bit
    
    // ** NEW I2C PORTS **
    output reg        config_i2c_enable_10bit_mode,  // 0=7bit mode, 1=10bit mode
    output reg [9:0]  config_i2c_slave_10bit_address, // 10-bit Slave Address

    output reg        config_i2c_7b_addr_valid,     // Pulse high
    output reg        config_i2c_reg_size_valid,    // Pulse high
    output reg        config_i2c_10b_addr_valid,    // Pulse high
    output reg        config_i2c_mode_valid,        // Pulse high

    // --- Status ---
    output reg        parse_error                // Pulse high if frame is invalid
);

//--------------------------------------------------------------------------
// FSM States
//--------------------------------------------------------------------------
    localparam S_IDLE       = 4'd0;
    localparam S_RECV_MOD   = 4'd1;
    localparam S_RECV_CMD   = 4'd2;
    localparam S_RECV_DATA  = 4'd3;
    localparam S_RECV_CHK   = 4'd4;
    localparam S_RECV_END   = 4'd5;

//--------------------------------------------------------------------------
// Frame Definitions
//--------------------------------------------------------------------------
    localparam START_BYTE   = 8'hA5;
    localparam END_BYTE     = 8'h5A;

    localparam MODULE_SPI   = 8'h01;
    localparam MODULE_I2C   = 8'h02;

    // SPI Commands
    localparam CMD_SPI_SET_MODE  = 8'h01; // Data[1:0] = CPOL/CPHA

    // I2C Commands
    localparam CMD_I2C_SET_7B_ADDR   = 8'h02; // Data[6:0] = 7-bit address
    localparam CMD_I2C_SET_REG_SIZE  = 8'h03; // Data[0]   = 0(8bit), 1(16bit)
    
    // ** NEW I2C COMMANDS **
    localparam CMD_I2C_SET_ADDR_MODE   = 8'h04; // Data[0]   = 0(7bit), 1(10bit)
    localparam CMD_I2C_SET_10B_ADDR_H  = 8'h05; // Data[1:0] = Addr[9:8]
    localparam CMD_I2C_SET_10B_ADDR_L  = 8'h06; // Data[7:0] = Addr[7:0]
    
//--------------------------------------------------------------------------
// Internal Registers
//--------------------------------------------------------------------------
    reg [3:0]  current_state, next_state;
    reg [7:0]  module_reg, cmd_reg, data_reg;
    reg [7:0]  checksum_reg;

    // Pulse generation
    reg        spi_mode_valid_pulse;
    reg        i2c_7b_addr_valid_pulse;
    reg        i2c_reg_size_valid_pulse;
    reg        i2c_mode_valid_pulse;
    reg        i2c_10b_addr_h_pulse;
    reg        i2c_10b_addr_l_pulse;
    reg        error_pulse;

    // ** NEW: Internal register for 10-bit address assembly **
    reg [9:0]  config_i2c_slave_10bit_address_reg;

//--------------------------------------------------------------------------
// FSM (Combinational part)
//--------------------------------------------------------------------------
    always @(*) begin
        next_state = S_IDLE;
        
        // Default pulse outputs
        spi_mode_valid_pulse   = 1'b0;
        i2c_7b_addr_valid_pulse = 1'b0;
        i2c_reg_size_valid_pulse = 1'b0;
        i2c_mode_valid_pulse   = 1'b0;
        i2c_10b_addr_h_pulse = 1'b0;
        i2c_10b_addr_l_pulse = 1'b0;
        error_pulse            = 1'b0;
        
        case(current_state)
            S_IDLE:
                if (rx_valid) begin
                    if (rx_data == START_BYTE) begin
                        next_state = S_RECV_MOD;
                    end
                end
            
            S_RECV_MOD:
                if (rx_valid) begin
                    next_state = S_RECV_CMD;
                end
            
            S_RECV_CMD:
                if (rx_valid) begin
                    next_state = S_RECV_DATA;
                end

            S_RECV_DATA:
                if (rx_valid) begin
                    next_state = S_RECV_CHK;
                end
                
            S_RECV_CHK:
                if (rx_valid) begin
                    next_state = S_RECV_END;
                end

            S_RECV_END:
                if (rx_valid) begin
                    if (rx_data == END_BYTE) begin
                        // Frame OK, check checksum
                        if (checksum_reg == (module_reg ^ cmd_reg ^ data_reg)) begin
                            // Checksum OK, dispatch command
                            case (module_reg)
                                MODULE_SPI: begin
                                    if (cmd_reg == CMD_SPI_SET_MODE) begin
                                        spi_mode_valid_pulse = 1'b1;
                                    end
                                end
                                MODULE_I2C: begin
                                    case (cmd_reg)
                                        CMD_I2C_SET_7B_ADDR:  i2c_7b_addr_valid_pulse = 1'b1;
                                        CMD_I2C_SET_REG_SIZE: i2c_reg_size_valid_pulse = 1'b1;
                                        CMD_I2C_SET_ADDR_MODE: i2c_mode_valid_pulse = 1'b1;
                                        CMD_I2C_SET_10B_ADDR_H: i2c_10b_addr_h_pulse = 1'b1;
                                        CMD_I2C_SET_10B_ADDR_L: i2c_10b_addr_l_pulse = 1'b1;
                                    endcase
                                end
                            endcase
                        end else begin
                            // Checksum Error
                            error_pulse = 1'b1;
                        end
                    end else begin
                        // End Byte Error
                        error_pulse = 1'b1;
                    end
                    next_state = S_IDLE;
                end

            default:
                next_state = S_IDLE;
        endcase
    end

//--------------------------------------------------------------------------
// State Machine Registers (Sequential part)
//--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            module_reg   <= 8'h00;
            cmd_reg      <= 8'h00;
            data_reg     <= 8'h00;
            checksum_reg <= 8'h00;
        end else begin
            current_state <= next_state;
            if (rx_valid) begin
                case(next_state) // Use next_state to capture on correct transition
                    S_RECV_CMD:  module_reg   <= rx_data;
                    S_RECV_DATA: cmd_reg      <= rx_data;
                    S_RECV_CHK:  data_reg     <= rx_data;
                    S_RECV_END:  checksum_reg <= rx_data;
                endcase
            end
        end
    end

//--------------------------------------------------------------------------
// Output Registers and Pulse Logic (Sequential part)
//--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // SPI Outputs
            config_spi_cpol <= 1'b0;
            config_spi_cpha <= 1'b0;
            config_spi_mode_valid <= 1'b0;

            // I2C Outputs
            config_i2c_slave_address     <= 7'h00;
            config_i2c_reg_addr_16bit    <= 1'b0;
            config_i2c_enable_10bit_mode <= 1'b0;
            config_i2c_slave_10bit_address <= 10'h000;
            config_i2c_slave_10bit_address_reg <= 10'h000; // Internal scratchpad

            config_i2c_7b_addr_valid   <= 1'b0;
            config_i2c_reg_size_valid  <= 1'b0;
            config_i2c_10b_addr_valid  <= 1'b0;
            config_i2c_mode_valid      <= 1'b0;
            
            parse_error                <= 1'b0;
            
        end else begin
            // --- Update config values based on pulses ---
            
            // ** MODIFIED: Split mode into CPOL and CPHA **
            if (spi_mode_valid_pulse) begin
                config_spi_cpol <= data_reg[1]; // Mode[1]
                config_spi_cpha <= data_reg[0]; // Mode[0]
            end
            
            if (i2c_7b_addr_valid_pulse)   config_i2c_slave_address  <= data_reg[6:0];
            if (i2c_reg_size_valid_pulse)  config_i2c_reg_addr_16bit <= data_reg[0];
            
            // ** NEW: Handle 10-bit address config **
            if (i2c_mode_valid_pulse)      config_i2c_enable_10bit_mode <= data_reg[0];
            
            // Store High-bits in internal register
            if (i2c_10b_addr_h_pulse)      config_i2c_slave_10bit_address_reg[9:8] <= data_reg[1:0];
            
            // Store Low-bits AND latch the full 10-bit address to the output
            if (i2c_10b_addr_l_pulse) begin
                config_i2c_slave_10bit_address_reg[7:0] <= data_reg[7:0];
                config_i2c_slave_10bit_address <= {config_i2c_slave_10bit_address_reg[9:8], data_reg[7:0]};
            end

            // --- Assign pulses directly for single-cycle output ---
            config_spi_mode_valid   <= spi_mode_valid_pulse;
            config_i2c_7b_addr_valid <= i2c_7b_addr_valid_pulse;
            config_i2c_reg_size_valid<= i2c_reg_size_valid_pulse;
            config_i2c_mode_valid    <= i2c_mode_valid_pulse;
            // Latch 10-bit valid only when LSBs are written
            config_i2c_10b_addr_valid<= i2c_10b_addr_l_pulse; 
            
            parse_error             <= error_pulse;
        end
    end

endmodule