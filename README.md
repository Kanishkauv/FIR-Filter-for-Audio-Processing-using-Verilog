# Real-Time FIR Audio Filter on Altera DE2-115

Real-time FIR digital filtering of audio on the Terasic/Altera DE2-115 (Cyclone IV E) using the onboard WM8731 audio codec. Mic/line in → FPGA FIR filter → headphone out.

Filter coefficients are designed in MATLAB, and the datapath is written in Verilog HDL.

## Reference

* "Implementation of FIR Digital Filters on FPGA Board for Real-Time Audio Processing," IEEE ICT-PEP 2023 (Basys-3 + PMOD I2S2)
* Original Basys-3 implementation: https://github.com/sinandredemption/fir\_basys3

This project ports that design to the DE2-115 and replaces the PMOD I2S2 with the onboard WM8731 codec.

## Specifications

|Parameter|Value|
|-|-|
|Board|DE2-115 (EP4CE115F29C7)|
|Codec|WM8731 (I2C config, I2S data)|
|Sample rate|48 kHz|
|Data width|24-bit sample, Q15 coefficients, 89 taps|
|Filters|Low-pass (fc = 1 kHz), High-pass (fc = 2 kHz)|

## Repository structure

```
rtl/            Verilog source (I2C config, I2S interface, FIR core, top)
matlab/         Coefficient design script and generated coefficient files
constraints/    Pin assignments / SDC timing constraints
docs/           Block diagram, results, waveforms
```


## How to run

1. Run `matlab/fir\_coeffs.m` to generate the coefficient files.
2. Open the Quartus project, add the `rtl/` sources, and import the pin assignments.
3. Compile the design and program the DE2-115.
4. Play the test audio into LINE IN (or MIC IN) and listen on LINE OUT.



## Author

Kanishka U V, M.Tech VLSI Design, VIT Vellore

Vaishnav S Nambiar, M.Tech VLSI Design, VIT Vellore

Aarcha M S, M.Tech VLSI Design, VIT Vellore

