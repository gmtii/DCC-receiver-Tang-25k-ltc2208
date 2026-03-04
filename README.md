Tang Primer 25K - DDC SDR receiver 

Block schematics:

![alt text](https://github.com/gmtii/DCC-receiver-Tang-25k-ltc2208/blob/iberico/2026-03-04_12-14)  

Changes in this fork:  

Control RX frequency and LTC2208 parameters with python serial gui.  

![alt text](https://github.com/gmtii/DCC-receiver-Tang-25k-ltc2208/blob/iberico/2026-03-03_22-40.png)  

Structure:  

16 bit samples from LTC2208 (clock 61.440 MHz)  
cordic => IQ  
2 stage CIC-decimator  
polyphaze FIR-decimator X8R8  
output quadrature samples on MCU over I2S-master interface (48000 Hz sample rate)  

Original project: Hermes SDR
Tang version (i2c control): https://github.com/Cvarc-Xtal/DDC-receiver-Tang-Nano-9K
Serial control fork: https://github.com/enthru/DDC-receiver-Tang-Nano-9K

EXTERNAL 61.44 MHZ CLK:  


IO_LOC "sck" J11;  
IO_PORT "sck" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  

LTC2208 PINOUT:  

IO_LOC "adc_data[15]" L9;  
IO_PORT "adc_data[15]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[14]" K9;  
IO_PORT "adc_data[14]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[13]" L10;  
IO_PORT "adc_data[13]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[12]" K10;  
IO_PORT "adc_data[12]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[11]" L7;  
IO_PORT "adc_data[11]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[10]" L8;  
IO_PORT "adc_data[10]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[9]" K7;  
IO_PORT "adc_data[9]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[8]" J7;  
IO_PORT "adc_data[8]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[7]" H1;  
IO_PORT "adc_data[7]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[6]" H2;  
IO_PORT "adc_data[6]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[5]" G4;  
IO_PORT "adc_data[5]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[4]" H4;  
IO_PORT "adc_data[4]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[3]" J1;  
IO_PORT "adc_data[3]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[2]" J2;  
IO_PORT "adc_data[2]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[1]" E3;  
IO_PORT "adc_data[1]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  
IO_LOC "adc_data[0]" D1;  
IO_PORT "adc_data[0]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;  

IO_LOC "PGA" J10;  
IO_PORT "PGA" IO_TYPE=LVCMOS33 PULL_MODE=DOWN DRIVE=8 BANK_VCCIO=3.3;  
IO_LOC "RAND" F7;  
IO_PORT "RAND" IO_TYPE=LVCMOS33 PULL_MODE=DOWN DRIVE=8 BANK_VCCIO=3.3;  
IO_LOC "SHDN" J8;  
IO_PORT "SHDN" IO_TYPE=LVCMOS33 PULL_MODE=DOWN DRIVE=8 BANK_VCCIO=3.3;  
IO_LOC "DITH" K8;  
IO_PORT "DITH" IO_TYPE=LVCMOS33 PULL_MODE=DOWN DRIVE=8 BANK_VCCIO=3.3;  
IO_LOC "PREAMP" A1;  
IO_PORT "PREAMP" IO_TYPE=LVCMOS33 PULL_MODE=DOWN DRIVE=8 BANK_VCCIO=3.3;  

// PE4302 attenuator control  

IO_LOC  "ATT1" H5;  
IO_PORT "ATT1" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "ATT2" J5;  
IO_PORT "ATT2" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "ATT3" H8;  
IO_PORT "ATT3" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "ATT4" H7;  
IO_PORT "ATT4" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "ATT5" G7;  
IO_PORT "ATT5" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "ATT6" G8;  
IO_PORT "ATT6" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;

