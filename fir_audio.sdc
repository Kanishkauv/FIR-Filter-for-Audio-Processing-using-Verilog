# fir_audio.sdc - timing constraints
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]
derive_clock_uncertainty

# Codec, I2C, switches and LEDs are slow (3 MHz at most) and are timed by
# counters in the design, so the pins themselves need no timing checks.
set_false_path -from [get_ports {SW[*] AUD_ADCDAT I2C_SDAT}]
set_false_path -to   [get_ports {LEDR[*] AUD_* I2C_*}]
