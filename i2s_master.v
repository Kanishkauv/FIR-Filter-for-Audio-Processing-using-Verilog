// =============================================================================
// i2s_master.v - makes the codec clocks and moves 24-bit samples in and out
//
// One 10-bit counter running at 50 MHz makes every clock:
//   AUD_XCK  = cnt[1]  50 MHz / 4    = 12.5 MHz   (codec master clock)
//   AUD_BCLK = cnt[3]  50 MHz / 16   = 3.125 MHz  (one bit per period)
//   LRCK     = cnt[9]  50 MHz / 1024 = 48.828 kHz (sample rate)
// 12.5 MHz / 256 = 48.828 kHz, which is what the codec expects in its
// normal 256 x fs mode (register R8 = 0).
//
// Each LRCK period has 64 BCLK periods: 32 for left (LRCK low), then 32 for
// right (LRCK high). I2S puts the MSB in slot 1 (one BCLK after LRCK
// changes), so a 24-bit word uses slots 1..24. Slots 0 and 25..31 are zero.
//
// The codec changes ADCDAT after BCLK falls and reads DACDAT when BCLK rises.
// So we read ADCDAT in the middle of the BCLK high time (cnt[3:0] = 11) and
// change DACDAT at the same moment BCLK falls (cnt[3:0] goes 15 -> 0).
// =============================================================================
`default_nettype none
module i2s_master (
    input  wire               clk,         // 50 MHz
    input  wire               rst,
    output wire               aud_xck,
    output wire               aud_bclk,
    output wire               aud_lrck,    // goes to both ADCLRCK and DACLRCK
    output reg                aud_dacdat,
    input  wire               aud_adcdat,
    input  wire signed [23:0] dac_left,    // read once per frame (when cnt = 1023)
    input  wire signed [23:0] dac_right,
    output reg  signed [23:0] adc_left,
    output reg  signed [23:0] adc_right,
    output reg                adc_valid    // one-clock pulse: new left/right pair ready
);
    reg [9:0] cnt = 10'd0;
    always @(posedge clk)
        if (rst) cnt <= 10'd0;
        else     cnt <= cnt + 10'd1;

    assign aud_xck  = cnt[1];
    assign aud_bclk = cnt[3];
    assign aud_lrck = cnt[9];

    wire [4:0] slot  = cnt[8:4];           // bit slot inside the channel, 0..31
    wire       right = cnt[9];             // 0 = left half, 1 = right half

    // ---------------- ADC side: codec -> FPGA ----------------
    reg [23:0] adc_sh = 24'd0;
    wire [23:0] adc_word = {adc_sh[22:0], aud_adcdat};

    always @(posedge clk) begin
        adc_valid <= 1'b0;
        if (cnt[3:0] == 4'd11 && slot >= 5'd1 && slot <= 5'd24) begin
            adc_sh <= adc_word;
            if (slot == 5'd24) begin       // last bit of the word
                if (!right) adc_left <= adc_word;
                else begin
                    adc_right <= adc_word;
                    adc_valid <= 1'b1;
                end
            end
        end
    end

    // ---------------- DAC side: FPGA -> codec ----------------
    reg  [23:0] hold_l = 24'd0, hold_r = 24'd0;   // words sent in this frame
    wire [5:0]  next      = cnt[9:4] + 6'd1;      // slot that starts at the next BCLK fall
    wire [4:0]  next_slot = next[4:0];
    wire [23:0] next_word = next[5] ? hold_r : hold_l;

    always @(posedge clk) begin
        if (cnt == 10'd1023) begin                // a new frame starts next clock
            hold_l <= dac_left;
            hold_r <= dac_right;
        end
        if (rst)
            aud_dacdat <= 1'b0;
        else if (cnt[3:0] == 4'd15) begin
            if (next_slot >= 5'd1 && next_slot <= 5'd24)
                aud_dacdat <= next_word[5'd24 - next_slot];   // slot 1 = bit 23
            else
                aud_dacdat <= 1'b0;
        end
    end
endmodule
`default_nettype wire
