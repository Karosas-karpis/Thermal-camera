## This file is a general .xdc for the Basys3 rev B board
## To use it in a project:
## - uncomment the lines corresponding to used pins
## - rename the used ports (in each line, after get_ports) according to the top level signal names in the project

## Clock signal
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]


## Switches
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN W16   IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN W17   IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN W15   IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]
set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]
set_property -dict { PACKAGE_PIN W13   IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]
set_property -dict { PACKAGE_PIN V2    IOSTANDARD LVCMOS33 } [get_ports {sw[8]}]
set_property -dict { PACKAGE_PIN T3    IOSTANDARD LVCMOS33 } [get_ports {sw[9]}]
set_property -dict { PACKAGE_PIN T2    IOSTANDARD LVCMOS33 } [get_ports {sw[10]}]
set_property -dict { PACKAGE_PIN R3    IOSTANDARD LVCMOS33 } [get_ports {sw[11]}]
set_property -dict { PACKAGE_PIN W2    IOSTANDARD LVCMOS33 } [get_ports {sw[12]}]
set_property -dict { PACKAGE_PIN U1    IOSTANDARD LVCMOS33 } [get_ports {sw[13]}]
set_property -dict { PACKAGE_PIN T1    IOSTANDARD LVCMOS33 } [get_ports {sw[14]}]
set_property -dict { PACKAGE_PIN R2    IOSTANDARD LVCMOS33 } [get_ports {sw[15]}]


## LEDs
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19   IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN U19   IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN V19   IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN W18   IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN U15   IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
#set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
#set_property -dict { PACKAGE_PIN V3    IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
#set_property -dict { PACKAGE_PIN W3    IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
#set_property -dict { PACKAGE_PIN U3    IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
#set_property -dict { PACKAGE_PIN P3    IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
#set_property -dict { PACKAGE_PIN N3    IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
#set_property -dict { PACKAGE_PIN P1    IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
#set_property -dict { PACKAGE_PIN L1    IOSTANDARD LVCMOS33 } [get_ports {led[15]}]


##7 Segment Display
#set_property -dict { PACKAGE_PIN W7   IOSTANDARD LVCMOS33 } [get_ports {seg[0]}]
#set_property -dict { PACKAGE_PIN W6   IOSTANDARD LVCMOS33 } [get_ports {seg[1]}]
#set_property -dict { PACKAGE_PIN U8   IOSTANDARD LVCMOS33 } [get_ports {seg[2]}]
#set_property -dict { PACKAGE_PIN V8   IOSTANDARD LVCMOS33 } [get_ports {seg[3]}]
#set_property -dict { PACKAGE_PIN U5   IOSTANDARD LVCMOS33 } [get_ports {seg[4]}]
#set_property -dict { PACKAGE_PIN V5   IOSTANDARD LVCMOS33 } [get_ports {seg[5]}]
#set_property -dict { PACKAGE_PIN U7   IOSTANDARD LVCMOS33 } [get_ports {seg[6]}]

#set_property -dict { PACKAGE_PIN V7   IOSTANDARD LVCMOS33 } [get_ports dp]

#set_property -dict { PACKAGE_PIN U2   IOSTANDARD LVCMOS33 } [get_ports {an[0]}]
#set_property -dict { PACKAGE_PIN U4   IOSTANDARD LVCMOS33 } [get_ports {an[1]}]
#set_property -dict { PACKAGE_PIN V4   IOSTANDARD LVCMOS33 } [get_ports {an[2]}]
#set_property -dict { PACKAGE_PIN W4   IOSTANDARD LVCMOS33 } [get_ports {an[3]}]


##Buttons
## btnC = restart thermal camera bring-up
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports btnC]
#set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports btnU]
#set_property -dict { PACKAGE_PIN W19   IOSTANDARD LVCMOS33 } [get_ports btnL]
#set_property -dict { PACKAGE_PIN T17   IOSTANDARD LVCMOS33 } [get_ports btnR]
#set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports btnD]


## Pmod JA - Thermal-44 camera module (3.3 V from JA6/JA12, GND JA5/JA11)
## Top row    (pins 1-4):  SCLK  MOSI  MISO  CS_N
## Bottom row (pins 7-10): SCL   SDA   nRST  DRDY
## SPI outputs use slow slew + 4 mA drive to limit ringing on long jumper wires
## (ringing on SCLK makes the sensor count extra clock edges).
set_property -dict { PACKAGE_PIN J1   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4 } [get_ports thermal_sclk];# JA1 - SCLK
set_property -dict { PACKAGE_PIN L2   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4 } [get_ports thermal_mosi];# JA2 - MOSI
set_property -dict { PACKAGE_PIN J2   IOSTANDARD LVCMOS33 } [get_ports thermal_miso];# JA3 - MISO
set_property -dict { PACKAGE_PIN G2   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4 } [get_ports thermal_cs_n];# JA4 - CS
set_property -dict { PACKAGE_PIN H1   IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports thermal_scl];# JA7 - SCL
set_property -dict { PACKAGE_PIN K2   IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports thermal_sda];# JA8 - SDA
set_property -dict { PACKAGE_PIN H2   IOSTANDARD LVCMOS33 } [get_ports thermal_rst_n];# JA9 - nRESET
set_property -dict { PACKAGE_PIN G3   IOSTANDARD LVCMOS33 } [get_ports thermal_drdy];# JA10 - DATA_READY

## Slow/asynchronous I/O: inputs are synchronised or sampled long after they settle
set_false_path -from [get_ports {btnC sw[*] thermal_miso thermal_drdy thermal_scl thermal_sda}]
set_false_path -to   [get_ports {led[*] thermal_sclk thermal_mosi thermal_cs_n thermal_scl thermal_sda thermal_rst_n}]
## With the 7-segment display / led[15:8] enabled again:
#set_false_path -to   [get_ports {led[*] seg[*] dp an[*] thermal_sclk thermal_mosi thermal_cs_n thermal_scl thermal_sda thermal_rst_n}]


## OV7670 on JB + JC (not used yet, Part 3), matched to camera 2-row header.
## Camera pins (right to left on both rows):
##   3.3  SCL  VS   PLK  D7  D5  D3  D1  RET
##   GND  SDA  HS   XLK  D6  D4  D2  D0  PWDN
## Board bottom edge left to right is JB then JC.

## Pmod JB (left) - camera left side: RET/PWDN and D1/D0 D3/D2 D5/D4
## Row toward board center = pins 1-4, row toward board edge = pins 7-10
#set_property -dict { PACKAGE_PIN A14  IOSTANDARD LVCMOS33 } [get_ports cam_reset];# JB1 - RET
#set_property -dict { PACKAGE_PIN A16  IOSTANDARD LVCMOS33 } [get_ports {d[1]}];# JB2 - D1
#set_property -dict { PACKAGE_PIN B15  IOSTANDARD LVCMOS33 } [get_ports {d[3]}];# JB3 - D3
#set_property -dict { PACKAGE_PIN B16  IOSTANDARD LVCMOS33 } [get_ports {d[5]}];# JB4 - D5
#set_property -dict { PACKAGE_PIN A15  IOSTANDARD LVCMOS33 } [get_ports pwdn];# JB7 - PWDN
#set_property -dict { PACKAGE_PIN A17  IOSTANDARD LVCMOS33 } [get_ports {d[0]}];# JB8 - D0
#set_property -dict { PACKAGE_PIN C15  IOSTANDARD LVCMOS33 } [get_ports {d[2]}];# JB9 - D2
#set_property -dict { PACKAGE_PIN C16  IOSTANDARD LVCMOS33 } [get_ports {d[4]}];# JB10 - D4

## Pmod JC (right) - camera right side: D7/D6 PLK/XLK VS/HS SCL/SDA + 3.3/GND
#set_property -dict { PACKAGE_PIN K17  IOSTANDARD LVCMOS33 } [get_ports {d[7]}];# JC1 - D7
#set_property -dict { PACKAGE_PIN M18  IOSTANDARD LVCMOS33 } [get_ports pclk];# JC2 - PLK
#set_property -dict { PACKAGE_PIN N17  IOSTANDARD LVCMOS33 } [get_ports cam_vsync];# JC3 - VS
#set_property -dict { PACKAGE_PIN P18  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports sioc];# JC4 - SCL
#set_property -dict { PACKAGE_PIN L17  IOSTANDARD LVCMOS33 } [get_ports {d[6]}];# JC7 - D6
#set_property -dict { PACKAGE_PIN M19  IOSTANDARD LVCMOS33 } [get_ports xclk];# JC8 - XLK
#set_property -dict { PACKAGE_PIN P17  IOSTANDARD LVCMOS33 } [get_ports href];# JC9 - HS
#set_property -dict { PACKAGE_PIN R18  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports siod];# JC10 - SDA

## Camera pixel clock (typical ~10-25 MHz from OV7670)
#create_clock -period 40.000 -name pclk_pin -waveform {0.000 20.000} [get_ports pclk]
#set_clock_groups -asynchronous -group [get_clocks sys_clk_pin] -group [get_clocks pclk_pin]

##Pmod Header JXADC
#set_property -dict { PACKAGE_PIN J3   IOSTANDARD LVCMOS33 } [get_ports {JXADC[0]}];#Sch name = XA1_P
#set_property -dict { PACKAGE_PIN L3   IOSTANDARD LVCMOS33 } [get_ports {JXADC[1]}];#Sch name = XA2_P
#set_property -dict { PACKAGE_PIN M2   IOSTANDARD LVCMOS33 } [get_ports {JXADC[2]}];#Sch name = XA3_P
#set_property -dict { PACKAGE_PIN N2   IOSTANDARD LVCMOS33 } [get_ports {JXADC[3]}];#Sch name = XA4_P
#set_property -dict { PACKAGE_PIN K3   IOSTANDARD LVCMOS33 } [get_ports {JXADC[4]}];#Sch name = XA1_N
#set_property -dict { PACKAGE_PIN M3   IOSTANDARD LVCMOS33 } [get_ports {JXADC[5]}];#Sch name = XA2_N
#set_property -dict { PACKAGE_PIN M1   IOSTANDARD LVCMOS33 } [get_ports {JXADC[6]}];#Sch name = XA3_N
#set_property -dict { PACKAGE_PIN N1   IOSTANDARD LVCMOS33 } [get_ports {JXADC[7]}];#Sch name = XA4_N


##VGA Connector
set_property -dict { PACKAGE_PIN G19   IOSTANDARD LVCMOS33 } [get_ports {vgaRed[0]}]
set_property -dict { PACKAGE_PIN H19   IOSTANDARD LVCMOS33 } [get_ports {vgaRed[1]}]
set_property -dict { PACKAGE_PIN J19   IOSTANDARD LVCMOS33 } [get_ports {vgaRed[2]}]
set_property -dict { PACKAGE_PIN N19   IOSTANDARD LVCMOS33 } [get_ports {vgaRed[3]}]
set_property -dict { PACKAGE_PIN N18   IOSTANDARD LVCMOS33 } [get_ports {vgaBlue[0]}]
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports {vgaBlue[1]}]
set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports {vgaBlue[2]}]
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports {vgaBlue[3]}]
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports {vgaGreen[0]}]
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports {vgaGreen[1]}]
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports {vgaGreen[2]}]
set_property -dict { PACKAGE_PIN D17   IOSTANDARD LVCMOS33 } [get_ports {vgaGreen[3]}]
set_property -dict { PACKAGE_PIN P19   IOSTANDARD LVCMOS33 } [get_ports hsync]
set_property -dict { PACKAGE_PIN R19   IOSTANDARD LVCMOS33 } [get_ports vsync]


##USB-RS232 Interface
#set_property -dict { PACKAGE_PIN B18   IOSTANDARD LVCMOS33 } [get_ports RsRx]
#set_property -dict { PACKAGE_PIN A18   IOSTANDARD LVCMOS33 } [get_ports RsTx]


##USB HID (PS/2)
#set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33   PULLUP true } [get_ports PS2Clk]
#set_property -dict { PACKAGE_PIN B17   IOSTANDARD LVCMOS33   PULLUP true } [get_ports PS2Data]


##Quad SPI Flash
##Note that CCLK_0 cannot be placed in 7 series devices. You can access it using the
##STARTUPE2 primitive.
#set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports {QspiDB[0]}]
#set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports {QspiDB[1]}]
#set_property -dict { PACKAGE_PIN G18   IOSTANDARD LVCMOS33 } [get_ports {QspiDB[2]}]
#set_property -dict { PACKAGE_PIN F18   IOSTANDARD LVCMOS33 } [get_ports {QspiDB[3]}]
#set_property -dict { PACKAGE_PIN K19   IOSTANDARD LVCMOS33 } [get_ports QspiCSn]


## Configuration options, can be used for all designs
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

## SPI configuration mode options for QSPI boot, can be used for all designs
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
