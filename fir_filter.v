// =============================================================================
// fir_filter.v - 89-tap FIR filter, one multiply per clock
//
//   y[n] = ( sum over k = 0..88 of  h[k] * x[n-k] ) >> 15
//
// h[k] are 16-bit signed coefficients scaled by 2^15 - 1 (made in MATLAB,
// filter_gen.m). x are 24-bit signed samples.
//
// A new sample arrives every 1024 clocks (48.828 kHz at 50 MHz). The 89
// products are added one per clock, so the result is ready about 93 clocks
// later. That leaves plenty of time before the next sample.
//
// Past samples live in a 128-word memory used as a ring: wptr points to the
// next free place, and x[n-k] is at address (newest - k). The 7-bit address
// wraps by itself, so no modulo logic is needed.
//
// Filter select (one switch per filter):
//   sw = 001  low-pass 1 kHz
//   sw = 010  high-pass 2 kHz
//   sw = 100  band-pass 1-4 kHz
//   anything else: bypass (input goes straight to the output)
// =============================================================================
`default_nettype none
module fir_filter (
    input  wire               clk,
    input  wire               rst,
    input  wire [2:0]         sw,
    input  wire               in_valid,     // one-clock pulse with a new sample
    input  wire signed [23:0] in_sample,
    output reg                out_valid,    // one-clock pulse with the result
    output reg  signed [23:0] out_sample,
    output wire [1:0]         filter_sel    // 0 bypass, 1 LPF, 2 HPF, 3 BPF
);
    localparam TAPS = 89;

    // ---------------- coefficient ROMs ----------------
    reg signed [15:0] c_lpf [0:TAPS-1];
    reg signed [15:0] c_hpf [0:TAPS-1];
    reg signed [15:0] c_bpf [0:TAPS-1];
    initial begin
        $readmemh("coeffs/lpf.hex", c_lpf);
        $readmemh("coeffs/hpf.hex", c_hpf);
        $readmemh("coeffs/bpf.hex", c_bpf);
    end

    // ---------------- sample memory (ring) ----------------
    reg signed [23:0] smp [0:127];
    integer i;
    initial for (i = 0; i < 128; i = i + 1) smp[i] = 24'd0;

    // ---------------- switch decode ----------------
    reg [1:0] sw_sel;
    always @(*) begin
        case (sw)
            3'b001:  sw_sel = 2'd1;
            3'b010:  sw_sel = 2'd2;
            3'b100:  sw_sel = 2'd3;
            default: sw_sel = 2'd0;
        endcase
    end

    // ---------------- control ----------------
    reg [6:0]  wptr = 7'd0;        // next free place in the ring
    reg [6:0]  newest = 7'd0;      // address of x[n]
    reg [6:0]  k = 7'd0;           // tap number being read
    reg        busy = 1'b0;
    reg [1:0]  sel = 2'd0;         // filter used for this sample
    reg signed [23:0] dry = 24'd0; // x[n], used for bypass
    assign filter_sel = sel;

    always @(posedge clk) begin
        if (rst) begin
            wptr <= 7'd0;
            busy <= 1'b0;
            k    <= 7'd0;
            sel  <= 2'd0;
        end else if (in_valid) begin
            newest <= wptr;
            wptr   <= wptr + 7'd1;
            dry    <= in_sample;
            sel    <= sw_sel;      // switches are only looked at here
            k      <= 7'd0;
            busy   <= 1'b1;
        end else if (busy) begin
            if (k == TAPS - 1) busy <= 1'b0;
            else               k <= k + 7'd1;
        end
    end

    always @(posedge clk)
        if (in_valid) smp[wptr] <= in_sample;

    // ---------------- stage 1: read x[n-k] and h[k] ----------------
    wire [6:0] rd_addr = newest - k;
    reg signed [23:0] x_q;
    reg signed [15:0] q_lpf, q_hpf, q_bpf;
    reg v1 = 1'b0, l1 = 1'b0;      // valid, last tap

    always @(posedge clk) begin
        x_q   <= smp[rd_addr];
        q_lpf <= c_lpf[k];
        q_hpf <= c_hpf[k];
        q_bpf <= c_bpf[k];
        v1    <= busy;
        l1    <= busy && (k == TAPS - 1);
    end

    // ---------------- stage 2: multiply ----------------
    reg signed [15:0] coef;
    always @(*) begin
        case (sel)
            2'd1:    coef = q_lpf;
            2'd2:    coef = q_hpf;
            2'd3:    coef = q_bpf;
            default: coef = 16'sd0;
        endcase
    end

    reg signed [39:0] prod;
    reg v2 = 1'b0, l2 = 1'b0;
    always @(posedge clk) begin
        prod <= x_q * coef;
        v2   <= v1;
        l2   <= l1;
    end

    // ---------------- stage 3: add ----------------
    reg signed [47:0] acc = 48'sd0;   // 40-bit products, 89 of them -> 47 bits needed
    reg l3 = 1'b0;
    always @(posedge clk) begin
        if (in_valid) acc <= 48'sd0;
        else if (v2)  acc <= acc + prod;
        l3 <= l2;
    end

    // ---------------- stage 4: scale, clip, output ----------------
    // acc >> 15 undoes the 2^15 coefficient scaling. If the result does not
    // fit in 24 bits it is clipped to the largest value instead of wrapping.
    wire [32:0] y_full = acc[47:15];
    wire        fits   = (y_full[32:23] == {10{y_full[23]}});
    wire [23:0] y_clip = fits ? y_full[23:0] : (y_full[32] ? 24'h800000 : 24'h7FFFFF);

    always @(posedge clk) begin
        out_valid <= l3;
        if (l3) out_sample <= (sel == 2'd0) ? dry : y_clip;
    end
endmodule
`default_nettype wire
