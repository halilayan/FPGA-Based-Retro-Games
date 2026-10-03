## ============================================================================
## basys3.xdc - Basys 3 (XC7A35T-1CPG236C)
##
## All board-test top modules (vga_test_top, kbd_test_top, pong_board_top)
## expose the same port list, so this single file constrains any of them.
## To switch tests, only change the top module in the Sources panel.
## ============================================================================

## ---- 100 MHz system clock (W5) ---------------------------------------------
set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports clk_i]
create_clock -period 10.000 -name sys_clk -waveform {0 5} [get_ports clk_i]

## The 25.155 MHz pixel clock comes from the MMCM inside clk_pix_gen. Vivado
## derives it automatically, so no create_generated_clock is needed here.

## clk_sys (100 MHz) and clk_pix (~25.175 MHz) are independent MMCM outputs
## with no fixed phase relationship - any single-bit signal crossing between
## them (e.g. video_out.vhd's vblank_o into console_gpu_axi.vhd's vblank_i,
## synchronised there by sync_2ff) can NEVER be closed as a same-cycle path;
## trying to only produces a large, meaningless negative slack (found during
## blitter/console_gpu_axi bring-up: WNS -2.148 ns on exactly this
## path). Declaring the two clock groups asynchronous is the standard fix -
## it also covers any FUTURE clk_sys<->clk_pix single-bit crossing, not just
## this one, as long as it goes through a real synchroniser (sync_2ff or
## equivalent) rather than a raw combinational path.
set_clock_groups -asynchronous \
    -group [get_clocks -filter {NAME =~ *clk_100*}] \
    -group [get_clocks -filter {NAME =~ *clk_25*}]

## ---- Reset button, BTNC (U18), active high ---------------------------------
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports rst_i]
set_false_path -from [get_ports rst_i]

## ---- 16 slide switches (only SW0/SW1/SW14/SW15 used by pong_board_top) ----
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {sw_i[0]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {sw_i[1]}]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports {sw_i[2]}]
set_property -dict { PACKAGE_PIN W17 IOSTANDARD LVCMOS33 } [get_ports {sw_i[3]}]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports {sw_i[4]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {sw_i[5]}]
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports {sw_i[6]}]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports {sw_i[7]}]
set_property -dict { PACKAGE_PIN V2  IOSTANDARD LVCMOS33 } [get_ports {sw_i[8]}]
set_property -dict { PACKAGE_PIN T3  IOSTANDARD LVCMOS33 } [get_ports {sw_i[9]}]
set_property -dict { PACKAGE_PIN T2  IOSTANDARD LVCMOS33 } [get_ports {sw_i[10]}]
set_property -dict { PACKAGE_PIN R3  IOSTANDARD LVCMOS33 } [get_ports {sw_i[11]}]
set_property -dict { PACKAGE_PIN W2  IOSTANDARD LVCMOS33 } [get_ports {sw_i[12]}]
set_property -dict { PACKAGE_PIN U1  IOSTANDARD LVCMOS33 } [get_ports {sw_i[13]}]
set_property -dict { PACKAGE_PIN T1  IOSTANDARD LVCMOS33 } [get_ports {sw_i[14]}]
set_property -dict { PACKAGE_PIN R2  IOSTANDARD LVCMOS33 } [get_ports {sw_i[15]}]

## ---- PS/2 keyboard (via USB HID host), C17 / B17 ---------------------------
## PULLUP TRUE is mandatory - without it the keyboard never works.
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports ps2_clk_i]
set_property -dict { PACKAGE_PIN B17 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports ps2_data_i]

## Driven asynchronously by the keyboard; synchronised by sync_2ff in ps2_rx.
set_false_path -from [get_ports ps2_clk_i]
set_false_path -from [get_ports ps2_data_i]

## ---- VGA 12-bit ------------------------------------------------------------
set_property -dict { PACKAGE_PIN G19 IOSTANDARD LVCMOS33 } [get_ports {vga_r_o[0]}]
set_property -dict { PACKAGE_PIN H19 IOSTANDARD LVCMOS33 } [get_ports {vga_r_o[1]}]
set_property -dict { PACKAGE_PIN J19 IOSTANDARD LVCMOS33 } [get_ports {vga_r_o[2]}]
set_property -dict { PACKAGE_PIN N19 IOSTANDARD LVCMOS33 } [get_ports {vga_r_o[3]}]
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports {vga_g_o[0]}]
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {vga_g_o[1]}]
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports {vga_g_o[2]}]
set_property -dict { PACKAGE_PIN D17 IOSTANDARD LVCMOS33 } [get_ports {vga_g_o[3]}]
set_property -dict { PACKAGE_PIN N18 IOSTANDARD LVCMOS33 } [get_ports {vga_b_o[0]}]
set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports {vga_b_o[1]}]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports {vga_b_o[2]}]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports {vga_b_o[3]}]

set_property -dict { PACKAGE_PIN P19 IOSTANDARD LVCMOS33 } [get_ports hsync_o]
set_property -dict { PACKAGE_PIN R19 IOSTANDARD LVCMOS33 } [get_ports vsync_o]

## ---- 16 LEDs ---------------------------------------------------------------
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {led_o[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {led_o[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {led_o[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {led_o[3]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {led_o[4]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports {led_o[5]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {led_o[6]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {led_o[7]}]
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports {led_o[8]}]
set_property -dict { PACKAGE_PIN V3  IOSTANDARD LVCMOS33 } [get_ports {led_o[9]}]
set_property -dict { PACKAGE_PIN W3  IOSTANDARD LVCMOS33 } [get_ports {led_o[10]}]
set_property -dict { PACKAGE_PIN U3  IOSTANDARD LVCMOS33 } [get_ports {led_o[11]}]
set_property -dict { PACKAGE_PIN P3  IOSTANDARD LVCMOS33 } [get_ports {led_o[12]}]
set_property -dict { PACKAGE_PIN N3  IOSTANDARD LVCMOS33 } [get_ports {led_o[13]}]
set_property -dict { PACKAGE_PIN P1  IOSTANDARD LVCMOS33 } [get_ports {led_o[14]}]
set_property -dict { PACKAGE_PIN L1  IOSTANDARD LVCMOS33 } [get_ports {led_o[15]}]

## ---- KY-023 joystick button, Pmod JB1 (A14) - basys3_rm.pdf Table 6 -
## PULLUP TRUE is mandatory - the button pulls this pin to GND when pressed
## (active low), same convention as ps2_clk_i/ps2_data_i above. Port name
## confirmed from the real generated wrapper (2026-09-26): Vivado's default
## "Make External" naming gave it "d_i" (debounce_0's own pin name), not the
## "joy_btn_i" I originally guessed - renaming it in the BD to something
## clearer is a nice-to-have, not required; if you do rename it, update the
## line below to match.
## MOVED from Pmod JA1 (J1) to JB1 (A14): J1 is in the SAME I/O bank
## (Bank 35) as the XADC Vaux4/Vaux15 pins below, and a bank can only run
## ONE VCCO (supply voltage) at a time - LVCMOS33 (this button, 3.3V) and
## LVCMOS18 (XADC's aux analog inputs, 1.8V, non-negotiable) cannot coexist
## in the same bank. Found via a real Generate Bitstream failure
## ([Place 30-372]/[Place 30-374]) - Bank 35's actual placement report
## showed Vaux4/Vaux15 AND d_i all landing there together.
set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports d_i]

## ---- KY-023 joystick X/Y (XADC Wizard's Vaux4/Vaux15) --------------
## CORRECTED (2026-09-26) from an earlier, WRONG guess (J3/K3/L3/M3, based
## on an initial Table 6 reading) - that assumed any JXADC differential
## pair could carry any selected Vaux channel. WRONG: each Vaux channel
## number is hardwired to ONE fixed
## physical pin pair in this exact package (XC7A35T-CPG236), not
## reassignable via XDC. Vivado's own placer ignored the incorrect J3/K3/
## L3/M3 constraint and placed these at their real, only-valid locations
## instead - confirmed directly from a Generate Bitstream placement report:
##   Vaux4  (X axis) -> G2 (P) / G3 (N)  - these ALSO happen to be Pmod
##                       JA4/JA10 (Table 6) - a coincidence of this
##                       package's routing, not something we chose.
##   Vaux15 (Y axis) -> N2 (P) / N1 (N)  - these match Table 6's
##                       JXADC4/JXADC10 (the one pair my original guess got
##                       right, by luck).
## NO IOSTANDARD on these four - dedicated XADC analog pins, not regular
## LVCMOS I/O; the placement report shows Vivado uses LVCMOS18 for them on
## its own (XADC's own fixed electrical requirement), don't override it.
set_property PACKAGE_PIN G2 [get_ports Vaux4_v_p]
set_property PACKAGE_PIN G3 [get_ports Vaux4_v_n]
set_property PACKAGE_PIN N2 [get_ports Vaux15_v_p]
set_property PACKAGE_PIN N1 [get_ports Vaux15_v_n]

## ---- Block Design UART (AXI UART Lite), B18 / A18 ------------------
## Port names come from the wrapper's "UART" interface Make External: exact
## names as generated by Vivado (system_bd_wrapper.vhd), confirmed 2026-09-19.
## Direction is from the FPGA's perspective: UART_rxd is an FPGA input.
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports UART_rxd]
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports UART_txd]

## ---- Configuration ---------------------------------------------------------
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
