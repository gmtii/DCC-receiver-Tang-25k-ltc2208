//Copyright (C)2014-2026 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.11.03 Education 
//Created Time: 2026-02-15 21:03:59
create_clock -name MCK -period 12 -waveform {0 6} [get_ports {MCK}]
create_clock -name sck -period 16 -waveform {0 8} [get_ports {sck}]
create_clock -name decim_avail -period 20833 -waveform {1 200} [get_nets {rx/decim_avail}]
create_clock -name BCK -period 651 -waveform {0 325} [get_ports {BCK}]
create_clock -name CLK50 -period 20 -waveform {0 10} [get_ports {clk_50}]
//set_input_delay -clock sck -max 2.5 [get_ports {adc_data[*]}]
//set_input_delay -clock sck -min 0.5 [get_ports {adc_data[*]}]