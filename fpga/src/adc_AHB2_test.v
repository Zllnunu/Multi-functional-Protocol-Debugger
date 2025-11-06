// ============================================================================
// Module: adc_preview_test.v
// Author: Gemini
// Description:
//   **已修正**: pROM IP核的地址输入 .ad() 已修正为完整的位宽，
//   以解决地址回绕 (wrap-around) 导致的波形显示错误。
// ============================================================================
`timescale 1ns / 1ps
module adc_preview_test (
    input         clk,
    input         reset_n,
    // 使用与pROM IP核地址位宽匹配的输入
    input  [8:0]  bram_addr, // 假设pROM深度为512 (地址位宽为9)
    output [7:0]  bram_dout,
    output        data_ready
);

    assign data_ready = 1'b1;

    // 实例化您的 Gowin pROM IP 核
    // **重要**: 请确保您在IP核生成器中，pROM的地址端口 ad 的位宽与
    // 此处的 bram_addr 位宽完全匹配。
    Gowin_pROM prom_sine_wave (
        .dout(bram_dout), 
        .clk(clk),
        .oce(1'b1),
        .ce(1'b1), 
        .reset(~reset_n),
        // --- ** 核心修正: 将完整的地址总线连接到pROM ** ---
        .ad(bram_addr) 
    );

endmodule
