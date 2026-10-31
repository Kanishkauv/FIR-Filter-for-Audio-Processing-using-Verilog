// =============================================================================
// de2_fir_audio.v - real-time FIR audio filter on the DE2-115 (simplified)
//
//   mic -> WM8731 ADC -> i2s_master -> fir_filter -> i2s_master -> WM8731 DAC
//        -> LINE OUT (headphones)
//
// wm8731_config sets up the codec over I2C once after power-up.
//
// Controls (only 3 switches are used)
//   SW[0]  low-pass  1 kHz
//   SW[1]  high-pass 2 kHz
//   SW[2]  band-pass 1-4 kHz
//   none up, or more than one up = bypass (no filtering)
// Lights
//   LEDR[0] LPF on, LEDR[1] HPF on, LEDR[2] BPF on
// Reset
//   Automatic at power-up / when the FPGA is programmed (no KEY used).
// =============================================================================
`default_nettype none
module de2_fir_audio #(
    parameter CFG_WAIT = 1_000_000          // clocks to wait before talking to the codec
) (
    input  wire        CLOCK_50,
    input  wire [2:0]  SW,
    output wire [2:0]  LEDR,

    output wire        AUD_XCK,
    output wire        AUD_BCLK,
    output wire        AUD_ADCLRCK,
    output wire        AUD_DACLRCK,
    output wire        AUD_DACDAT,
    input  wire        AUD_ADCDAT,

    output wire        I2C_SCLK,
    inout  wire        I2C_SDAT
);
    wire clk = CLOCK_50;

    // ---------------- power-up reset: about 1.3 ms ----------------
    reg [15:0] por = 16'd0;
    reg        rst = 1'b1;
    always @(posedge clk) begin
        if (por != 16'hFFFF) por <= por + 16'd1;
        rst <= (por != 16'hFFFF);
    end

    // switches into the clock domain (two flip-flops)
    reg [2:0] sw_a = 3'd0, sw_b = 3'd0;
    always @(posedge clk) begin
        sw_a <= SW;
        sw_b <= sw_a;
    end

    // ---------------- codec setup ----------------
    wm8731_config #(.WAIT_CLKS(CFG_WAIT)) codec_cfg (
        .clk      (clk),
        .rst      (rst),
        .i2c_sclk (I2C_SCLK),
        .i2c_sdat (I2C_SDAT)
    );

    // ---------------- I2S ----------------
    wire               lrck;
    wire signed [23:0] adc_l, adc_r;
    wire               adc_valid;
    reg  signed [23:0] dac_word = 24'sd0;

    i2s_master i2s (
        .clk        (clk),
        .rst        (rst),
        .aud_xck    (AUD_XCK),
        .aud_bclk   (AUD_BCLK),
        .aud_lrck   (lrck),
        .aud_dacdat (AUD_DACDAT),
        .aud_adcdat (AUD_ADCDAT),
        .dac_left   (dac_word),
        .dac_right  (dac_word),
        .adc_left   (adc_l),
        .adc_right  (adc_r),
        .adc_valid  (adc_valid)
    );
    assign AUD_ADCLRCK = lrck;
    assign AUD_DACLRCK = lrck;

    // mono = (left + right) / 2, done in 25 bits so it cannot overflow
    wire signed [24:0] lr_sum = {adc_l[23], adc_l} + {adc_r[23], adc_r};
    wire signed [23:0] mono   = lr_sum[24:1];

    // ---------------- filter ----------------
    wire               fir_valid;
    wire signed [23:0] fir_out;
    wire [1:0]         sel;

    fir_filter fir (
        .clk        (clk),
        .rst        (rst),
        .sw         (sw_b),
        .in_valid   (adc_valid),
        .in_sample  (mono),
        .out_valid  (fir_valid),
        .out_sample (fir_out),
        .filter_sel (sel)
    );

    // same filtered sound to both ears
    always @(posedge clk)
        if (fir_valid) dac_word <= fir_out;

    // ---------------- filter lights ----------------
    assign LEDR[0] = (sel == 2'd1);
    assign LEDR[1] = (sel == 2'd2);
    assign LEDR[2] = (sel == 2'd3);
endmodule
`default_nettype wire
