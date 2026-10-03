
################################################################
# This is a generated script based on design: system_bd
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2022.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source system_bd_script.tcl


# The design that will be created by this Tcl script contains the following 
# module references:
# asset_rom, axi_bram_byte_adapter, axi_bram_byte_adapter, blitter, console_gpu_axi, debounce, fb_arbiter, fb_ram, video_out

# Please add the sources of those modules before sourcing this Tcl script.

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7a35tcpg236-1
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name system_bd

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:axi_bram_ctrl:4.1\
xilinx.com:ip:axi_gpio:2.0\
xilinx.com:ip:axi_uartlite:2.0\
xilinx.com:ip:clk_wiz:6.0\
xilinx.com:ip:mdm:3.2\
xilinx.com:ip:microblaze:11.0\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:ip:util_vector_logic:2.0\
xilinx.com:ip:xadc_wiz:3.3\
xilinx.com:ip:xlconstant:1.1\
xilinx.com:ip:xlslice:1.0\
xilinx.com:ip:lmb_bram_if_cntlr:4.0\
xilinx.com:ip:lmb_v10:3.0\
xilinx.com:ip:blk_mem_gen:8.4\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
asset_rom\
axi_bram_byte_adapter\
axi_bram_byte_adapter\
blitter\
console_gpu_axi\
debounce\
fb_arbiter\
fb_ram\
video_out\
"

   set list_mods_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

   foreach mod_vlnv $list_check_mods {
      if { [can_resolve_reference $mod_vlnv] == 0 } {
         lappend list_mods_missing $mod_vlnv
      }
   }

   if { $list_mods_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
      common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
      set bCheckIPsPassed 0
   }
}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################


# Hierarchical cell: microblaze_0_local_memory
proc create_hier_cell_microblaze_0_local_memory { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_microblaze_0_local_memory() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode MirroredMaster -vlnv xilinx.com:interface:lmb_rtl:1.0 DLMB

  create_bd_intf_pin -mode MirroredMaster -vlnv xilinx.com:interface:lmb_rtl:1.0 ILMB


  # Create pins
  create_bd_pin -dir I -type clk LMB_Clk
  create_bd_pin -dir I -type rst SYS_Rst

  # Create instance: dlmb_bram_if_cntlr, and set properties
  set dlmb_bram_if_cntlr [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 dlmb_bram_if_cntlr ]
  set_property CONFIG.C_ECC {0} $dlmb_bram_if_cntlr


  # Create instance: dlmb_v10, and set properties
  set dlmb_v10 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 dlmb_v10 ]

  # Create instance: ilmb_bram_if_cntlr, and set properties
  set ilmb_bram_if_cntlr [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr:4.0 ilmb_bram_if_cntlr ]
  set_property CONFIG.C_ECC {0} $ilmb_bram_if_cntlr


  # Create instance: ilmb_v10, and set properties
  set ilmb_v10 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10:3.0 ilmb_v10 ]

  # Create instance: lmb_bram, and set properties
  set lmb_bram [ create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 lmb_bram ]
  set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.use_bram_block {BRAM_Controller} \
  ] $lmb_bram


  # Create interface connections
  connect_bd_intf_net -intf_net microblaze_0_dlmb [get_bd_intf_pins DLMB] [get_bd_intf_pins dlmb_v10/LMB_M]
  connect_bd_intf_net -intf_net microblaze_0_dlmb_bus [get_bd_intf_pins dlmb_bram_if_cntlr/SLMB] [get_bd_intf_pins dlmb_v10/LMB_Sl_0]
  connect_bd_intf_net -intf_net microblaze_0_dlmb_cntlr [get_bd_intf_pins dlmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTA]
  connect_bd_intf_net -intf_net microblaze_0_ilmb [get_bd_intf_pins ILMB] [get_bd_intf_pins ilmb_v10/LMB_M]
  connect_bd_intf_net -intf_net microblaze_0_ilmb_bus [get_bd_intf_pins ilmb_bram_if_cntlr/SLMB] [get_bd_intf_pins ilmb_v10/LMB_Sl_0]
  connect_bd_intf_net -intf_net microblaze_0_ilmb_cntlr [get_bd_intf_pins ilmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTB]

  # Create port connections
  connect_bd_net -net SYS_Rst_1 [get_bd_pins SYS_Rst] [get_bd_pins dlmb_bram_if_cntlr/LMB_Rst] [get_bd_pins dlmb_v10/SYS_Rst] [get_bd_pins ilmb_bram_if_cntlr/LMB_Rst] [get_bd_pins ilmb_v10/SYS_Rst]
  connect_bd_net -net microblaze_0_Clk [get_bd_pins LMB_Clk] [get_bd_pins dlmb_bram_if_cntlr/LMB_Clk] [get_bd_pins dlmb_v10/LMB_Clk] [get_bd_pins ilmb_bram_if_cntlr/LMB_Clk] [get_bd_pins ilmb_v10/LMB_Clk]

  # Restore current instance
  current_bd_instance $oldCurInst
}


# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set UART [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 UART ]

  set Vaux4 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 Vaux4 ]

  set Vaux15 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 Vaux15 ]


  # Create ports
  set clk_i [ create_bd_port -dir I -type clk clk_i ]
  set d_i [ create_bd_port -dir I d_i ]
  set hsync_o [ create_bd_port -dir O hsync_o ]
  set rst_i [ create_bd_port -dir I -type rst rst_i ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_HIGH} \
 ] $rst_i
  set vga_b_o [ create_bd_port -dir O -from 3 -to 0 vga_b_o ]
  set vga_g_o [ create_bd_port -dir O -from 3 -to 0 vga_g_o ]
  set vga_r_o [ create_bd_port -dir O -from 3 -to 0 vga_r_o ]
  set vsync_o [ create_bd_port -dir O vsync_o ]

  # Create instance: asset_rom_0, and set properties
  set block_name asset_rom
  set block_cell_name asset_rom_0
  if { [catch {set asset_rom_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $asset_rom_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: axi_bram_byte_adapter_0, and set properties
  set block_name axi_bram_byte_adapter
  set block_cell_name axi_bram_byte_adapter_0
  if { [catch {set axi_bram_byte_adapter_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $axi_bram_byte_adapter_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: axi_bram_byte_adapter_1, and set properties
  set block_name axi_bram_byte_adapter
  set block_cell_name axi_bram_byte_adapter_1
  if { [catch {set axi_bram_byte_adapter_1 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $axi_bram_byte_adapter_1 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property CONFIG.ADDR_WIDTH_G {14} $axi_bram_byte_adapter_1


  # Create instance: axi_bram_ctrl_0, and set properties
  set axi_bram_ctrl_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_0 ]
  set_property CONFIG.SINGLE_PORT_BRAM {1} $axi_bram_ctrl_0


  # Create instance: axi_bram_ctrl_1, and set properties
  set axi_bram_ctrl_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_1 ]
  set_property CONFIG.SINGLE_PORT_BRAM {1} $axi_bram_ctrl_1


  # Create instance: axi_gpio_0, and set properties
  set axi_gpio_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0 ]
  set_property -dict [list \
    CONFIG.C_ALL_INPUTS {1} \
    CONFIG.C_GPIO_WIDTH {1} \
  ] $axi_gpio_0


  # Create instance: axi_uartlite_0, and set properties
  set axi_uartlite_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 axi_uartlite_0 ]
  set_property CONFIG.C_BAUDRATE {115200} $axi_uartlite_0


  # Create instance: blitter_0, and set properties
  set block_name blitter
  set block_cell_name blitter_0
  if { [catch {set blitter_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $blitter_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: clk_wiz_0, and set properties
  set clk_wiz_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0 ]
  set_property -dict [list \
    CONFIG.CLKOUT1_JITTER {116.394} \
    CONFIG.CLKOUT1_PHASE_ERROR {87.466} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100} \
    CONFIG.CLKOUT2_JITTER {155.403} \
    CONFIG.CLKOUT2_PHASE_ERROR {87.466} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {25.175} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLK_OUT1_PORT {clk_100} \
    CONFIG.CLK_OUT2_PORT {clk_25} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {11.875} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {11.875} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {47} \
    CONFIG.MMCM_DIVCLK_DIVIDE {1} \
    CONFIG.NUM_OUT_CLKS {2} \
  ] $clk_wiz_0


  # Create instance: console_gpu_axi_0, and set properties
  set block_name console_gpu_axi
  set block_cell_name console_gpu_axi_0
  if { [catch {set console_gpu_axi_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $console_gpu_axi_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: debounce_0, and set properties
  set block_name debounce
  set block_cell_name debounce_0
  if { [catch {set debounce_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $debounce_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: fb_arbiter_0, and set properties
  set block_name fb_arbiter
  set block_cell_name fb_arbiter_0
  if { [catch {set fb_arbiter_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $fb_arbiter_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: fb_ram_0, and set properties
  set block_name fb_ram
  set block_cell_name fb_ram_0
  if { [catch {set fb_ram_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $fb_ram_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: mdm_1, and set properties
  set mdm_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:mdm:3.2 mdm_1 ]

  # Create instance: microblaze_0, and set properties
  set microblaze_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze:11.0 microblaze_0 ]
  set_property -dict [list \
    CONFIG.C_DEBUG_ENABLED {1} \
    CONFIG.C_D_AXI {1} \
    CONFIG.C_D_LMB {1} \
    CONFIG.C_I_LMB {1} \
    CONFIG.G_TEMPLATE_LIST {8} \
  ] $microblaze_0


  # Create instance: microblaze_0_axi_periph, and set properties
  set microblaze_0_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 microblaze_0_axi_periph ]
  set_property CONFIG.NUM_MI {6} $microblaze_0_axi_periph


  # Create instance: microblaze_0_local_memory
  create_hier_cell_microblaze_0_local_memory [current_bd_instance .] microblaze_0_local_memory

  # Create instance: rst_clk_wiz_0_100M, and set properties
  set rst_clk_wiz_0_100M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_clk_wiz_0_100M ]

  # Create instance: util_vector_logic_0, and set properties
  set util_vector_logic_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 util_vector_logic_0 ]
  set_property -dict [list \
    CONFIG.C_OPERATION {not} \
    CONFIG.C_SIZE {1} \
  ] $util_vector_logic_0


  # Create instance: video_out_0, and set properties
  set block_name video_out
  set block_cell_name video_out_0
  if { [catch {set video_out_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $video_out_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: xadc_wiz_0, and set properties
  set xadc_wiz_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xadc_wiz:3.3 xadc_wiz_0 ]
  set_property -dict [list \
    CONFIG.CHANNEL_AVERAGING {16} \
    CONFIG.CHANNEL_ENABLE_CALIBRATION {false} \
    CONFIG.CHANNEL_ENABLE_TEMPERATURE {false} \
    CONFIG.CHANNEL_ENABLE_VAUXP0_VAUXN0 {false} \
    CONFIG.CHANNEL_ENABLE_VAUXP13_VAUXN13 {false} \
    CONFIG.CHANNEL_ENABLE_VAUXP14_VAUXN14 {false} \
    CONFIG.CHANNEL_ENABLE_VAUXP15_VAUXN15 {true} \
    CONFIG.CHANNEL_ENABLE_VAUXP4_VAUXN4 {true} \
    CONFIG.CHANNEL_ENABLE_VAUXP8_VAUXN8 {false} \
    CONFIG.CHANNEL_ENABLE_VAUXP9_VAUXN9 {false} \
    CONFIG.CHANNEL_ENABLE_VBRAM {false} \
    CONFIG.CHANNEL_ENABLE_VCCAUX {false} \
    CONFIG.CHANNEL_ENABLE_VCCINT {false} \
    CONFIG.CHANNEL_ENABLE_VP_VN {false} \
    CONFIG.EXTERNAL_MUX_CHANNEL {VP_VN} \
    CONFIG.SEQUENCER_MODE {Continuous} \
    CONFIG.SINGLE_CHANNEL_SELECTION {TEMPERATURE} \
    CONFIG.USER_TEMP_ALARM {true} \
    CONFIG.VCCAUX_ALARM {true} \
    CONFIG.VCCINT_ALARM {true} \
    CONFIG.XADC_STARUP_SELECTION {channel_sequencer} \
  ] $xadc_wiz_0


  # Create instance: xlconstant_0, and set properties
  set xlconstant_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_0 ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0} \
    CONFIG.CONST_WIDTH {32} \
  ] $xlconstant_0


  # Create instance: xlconstant_4, and set properties
  set xlconstant_4 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_4 ]
  set_property CONFIG.CONST_VAL {0} $xlconstant_4


  # Create instance: xlconstant_5, and set properties
  set xlconstant_5 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_5 ]
  set_property CONFIG.CONST_VAL {0} $xlconstant_5


  # Create instance: xlconstant_6, and set properties
  set xlconstant_6 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_6 ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0} \
    CONFIG.CONST_WIDTH {64} \
  ] $xlconstant_6


  # Create instance: xlslice_0, and set properties
  set xlslice_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_0 ]
  set_property -dict [list \
    CONFIG.DIN_FROM {13} \
    CONFIG.DIN_WIDTH {17} \
  ] $xlslice_0


  # Create interface connections
  connect_bd_intf_net -intf_net Vaux15_0_1 [get_bd_intf_ports Vaux15] [get_bd_intf_pins xadc_wiz_0/Vaux15]
  connect_bd_intf_net -intf_net Vaux4_0_1 [get_bd_intf_ports Vaux4] [get_bd_intf_pins xadc_wiz_0/Vaux4]
  connect_bd_intf_net -intf_net axi_uartlite_0_UART [get_bd_intf_ports UART] [get_bd_intf_pins axi_uartlite_0/UART]
  connect_bd_intf_net -intf_net microblaze_0_M_AXI_DP [get_bd_intf_pins microblaze_0/M_AXI_DP] [get_bd_intf_pins microblaze_0_axi_periph/S00_AXI]
  connect_bd_intf_net -intf_net microblaze_0_axi_periph_M00_AXI [get_bd_intf_pins axi_uartlite_0/S_AXI] [get_bd_intf_pins microblaze_0_axi_periph/M00_AXI]
  connect_bd_intf_net -intf_net microblaze_0_axi_periph_M01_AXI [get_bd_intf_pins axi_bram_ctrl_0/S_AXI] [get_bd_intf_pins microblaze_0_axi_periph/M01_AXI]
  connect_bd_intf_net -intf_net microblaze_0_axi_periph_M02_AXI [get_bd_intf_pins axi_bram_ctrl_1/S_AXI] [get_bd_intf_pins microblaze_0_axi_periph/M02_AXI]
  connect_bd_intf_net -intf_net microblaze_0_axi_periph_M03_AXI [get_bd_intf_pins console_gpu_axi_0/s_axi] [get_bd_intf_pins microblaze_0_axi_periph/M03_AXI]
  connect_bd_intf_net -intf_net microblaze_0_axi_periph_M04_AXI [get_bd_intf_pins microblaze_0_axi_periph/M04_AXI] [get_bd_intf_pins xadc_wiz_0/s_axi_lite]
  connect_bd_intf_net -intf_net microblaze_0_axi_periph_M05_AXI [get_bd_intf_pins axi_gpio_0/S_AXI] [get_bd_intf_pins microblaze_0_axi_periph/M05_AXI]
  connect_bd_intf_net -intf_net microblaze_0_debug [get_bd_intf_pins mdm_1/MBDEBUG_0] [get_bd_intf_pins microblaze_0/DEBUG]
  connect_bd_intf_net -intf_net microblaze_0_dlmb_1 [get_bd_intf_pins microblaze_0/DLMB] [get_bd_intf_pins microblaze_0_local_memory/DLMB]
  connect_bd_intf_net -intf_net microblaze_0_ilmb_1 [get_bd_intf_pins microblaze_0/ILMB] [get_bd_intf_pins microblaze_0_local_memory/ILMB]

  # Create port connections
  connect_bd_net -net Net [get_bd_pins blitter_0/fb_we] [get_bd_pins fb_arbiter_0/blt_we_i] [get_bd_pins fb_arbiter_0/cart_we_i]
  connect_bd_net -net Net1 [get_bd_pins blitter_0/fb_addr] [get_bd_pins fb_arbiter_0/blt_addr_i] [get_bd_pins fb_arbiter_0/cart_addr_i]
  connect_bd_net -net Net2 [get_bd_pins blitter_0/fb_din] [get_bd_pins fb_arbiter_0/blt_din_i] [get_bd_pins fb_arbiter_0/cart_din_i]
  connect_bd_net -net asset_rom_0_dout_b_o [get_bd_pins asset_rom_0/dout_b_o] [get_bd_pins blitter_0/src_data]
  connect_bd_net -net axi_bram_byte_adapter_0_cpu_addr_o [get_bd_pins axi_bram_byte_adapter_0/cpu_addr_o] [get_bd_pins fb_arbiter_0/cpu_addr_i]
  connect_bd_net -net axi_bram_byte_adapter_0_cpu_din_o [get_bd_pins axi_bram_byte_adapter_0/cpu_din_o] [get_bd_pins fb_arbiter_0/cpu_din_i]
  connect_bd_net -net axi_bram_byte_adapter_0_cpu_we_o [get_bd_pins axi_bram_byte_adapter_0/cpu_we_o] [get_bd_pins fb_arbiter_0/cpu_we_i]
  connect_bd_net -net axi_bram_byte_adapter_1_cpu_addr_o [get_bd_pins asset_rom_0/addr_a_i] [get_bd_pins axi_bram_byte_adapter_1/cpu_addr_o]
  connect_bd_net -net axi_bram_byte_adapter_1_cpu_din_o [get_bd_pins asset_rom_0/din_a_i] [get_bd_pins axi_bram_byte_adapter_1/cpu_din_o]
  connect_bd_net -net axi_bram_byte_adapter_1_cpu_we_o [get_bd_pins asset_rom_0/we_a_i] [get_bd_pins axi_bram_byte_adapter_1/cpu_we_o]
  connect_bd_net -net axi_bram_ctrl_0_bram_addr_a [get_bd_pins axi_bram_byte_adapter_0/bram_addr_a_i] [get_bd_pins axi_bram_ctrl_0/bram_addr_a]
  connect_bd_net -net axi_bram_ctrl_0_bram_we_a [get_bd_pins axi_bram_byte_adapter_0/bram_we_a_i] [get_bd_pins axi_bram_ctrl_0/bram_we_a]
  connect_bd_net -net axi_bram_ctrl_0_bram_wrdata_a [get_bd_pins axi_bram_byte_adapter_0/bram_wrdata_a_i] [get_bd_pins axi_bram_ctrl_0/bram_wrdata_a]
  connect_bd_net -net axi_bram_ctrl_1_bram_addr_a [get_bd_pins axi_bram_byte_adapter_1/bram_addr_a_i] [get_bd_pins axi_bram_ctrl_1/bram_addr_a]
  connect_bd_net -net axi_bram_ctrl_1_bram_we_a [get_bd_pins axi_bram_byte_adapter_1/bram_we_a_i] [get_bd_pins axi_bram_ctrl_1/bram_we_a]
  connect_bd_net -net axi_bram_ctrl_1_bram_wrdata_a [get_bd_pins axi_bram_byte_adapter_1/bram_wrdata_a_i] [get_bd_pins axi_bram_ctrl_1/bram_wrdata_a]
  connect_bd_net -net blitter_0_busy [get_bd_pins blitter_0/busy] [get_bd_pins console_gpu_axi_0/blt_busy_i]
  connect_bd_net -net blitter_0_src_addr [get_bd_pins blitter_0/src_addr] [get_bd_pins xlslice_0/Din]
  connect_bd_net -net clk_in1_0_1 [get_bd_ports clk_i] [get_bd_pins clk_wiz_0/clk_in1]
  connect_bd_net -net clk_wiz_0_clk_25 [get_bd_pins clk_wiz_0/clk_25] [get_bd_pins fb_ram_0/clk_b_i] [get_bd_pins video_out_0/clk_pix_i]
  connect_bd_net -net clk_wiz_0_locked [get_bd_pins clk_wiz_0/locked] [get_bd_pins rst_clk_wiz_0_100M/dcm_locked]
  connect_bd_net -net console_gpu_axi_0_blt_cmd_color_o [get_bd_pins blitter_0/cmd_color] [get_bd_pins console_gpu_axi_0/blt_cmd_color_o]
  connect_bd_net -net console_gpu_axi_0_blt_cmd_h_o [get_bd_pins blitter_0/cmd_h] [get_bd_pins console_gpu_axi_0/blt_cmd_h_o]
  connect_bd_net -net console_gpu_axi_0_blt_cmd_key_en_o [get_bd_pins blitter_0/cmd_key_en] [get_bd_pins console_gpu_axi_0/blt_cmd_key_en_o]
  connect_bd_net -net console_gpu_axi_0_blt_cmd_key_o [get_bd_pins blitter_0/cmd_key] [get_bd_pins console_gpu_axi_0/blt_cmd_key_o]
  connect_bd_net -net console_gpu_axi_0_blt_cmd_op_o [get_bd_pins blitter_0/cmd_op] [get_bd_pins console_gpu_axi_0/blt_cmd_op_o]
  connect_bd_net -net console_gpu_axi_0_blt_cmd_src_o [get_bd_pins blitter_0/cmd_src] [get_bd_pins console_gpu_axi_0/blt_cmd_src_o]
  connect_bd_net -net console_gpu_axi_0_blt_cmd_start_o [get_bd_pins blitter_0/cmd_start] [get_bd_pins console_gpu_axi_0/blt_cmd_start_o]
  connect_bd_net -net console_gpu_axi_0_blt_cmd_w_o [get_bd_pins blitter_0/cmd_w] [get_bd_pins console_gpu_axi_0/blt_cmd_w_o]
  connect_bd_net -net console_gpu_axi_0_blt_cmd_x_o [get_bd_pins blitter_0/cmd_x] [get_bd_pins console_gpu_axi_0/blt_cmd_x_o]
  connect_bd_net -net console_gpu_axi_0_blt_cmd_y_o [get_bd_pins blitter_0/cmd_y] [get_bd_pins console_gpu_axi_0/blt_cmd_y_o]
  connect_bd_net -net console_gpu_axi_0_pal_wr_en_o [get_bd_pins console_gpu_axi_0/pal_wr_en_o] [get_bd_pins video_out_0/wr_en_i]
  connect_bd_net -net console_gpu_axi_0_pal_wr_idx_o [get_bd_pins console_gpu_axi_0/pal_wr_idx_o] [get_bd_pins video_out_0/wr_idx_i]
  connect_bd_net -net console_gpu_axi_0_pal_wr_rgb_o [get_bd_pins console_gpu_axi_0/pal_wr_rgb_o] [get_bd_pins video_out_0/wr_rgb_i]
  connect_bd_net -net d_i_0_1 [get_bd_ports d_i] [get_bd_pins debounce_0/d_i]
  connect_bd_net -net debounce_0_d_o [get_bd_pins axi_gpio_0/gpio_io_i] [get_bd_pins debounce_0/d_o]
  connect_bd_net -net fb_arbiter_0_fb_addr_o [get_bd_pins fb_arbiter_0/fb_addr_o] [get_bd_pins fb_ram_0/addr_a_i]
  connect_bd_net -net fb_arbiter_0_fb_din_o [get_bd_pins fb_arbiter_0/fb_din_o] [get_bd_pins fb_ram_0/din_a_i]
  connect_bd_net -net fb_arbiter_0_fb_we_o [get_bd_pins fb_arbiter_0/fb_we_o] [get_bd_pins fb_ram_0/we_a_i]
  connect_bd_net -net fb_ram_0_dout_b_o [get_bd_pins fb_ram_0/dout_b_o] [get_bd_pins video_out_0/fb_dout_i]
  connect_bd_net -net mdm_1_debug_sys_rst [get_bd_pins mdm_1/Debug_SYS_Rst] [get_bd_pins rst_clk_wiz_0_100M/mb_debug_sys_rst]
  connect_bd_net -net microblaze_0_Clk [get_bd_pins asset_rom_0/clk_a_i] [get_bd_pins asset_rom_0/clk_b_i] [get_bd_pins axi_bram_ctrl_0/s_axi_aclk] [get_bd_pins axi_bram_ctrl_1/s_axi_aclk] [get_bd_pins axi_gpio_0/s_axi_aclk] [get_bd_pins axi_uartlite_0/s_axi_aclk] [get_bd_pins blitter_0/clk] [get_bd_pins clk_wiz_0/clk_100] [get_bd_pins console_gpu_axi_0/s_axi_aclk] [get_bd_pins debounce_0/clk_i] [get_bd_pins fb_ram_0/clk_a_i] [get_bd_pins microblaze_0/Clk] [get_bd_pins microblaze_0_axi_periph/ACLK] [get_bd_pins microblaze_0_axi_periph/M00_ACLK] [get_bd_pins microblaze_0_axi_periph/M01_ACLK] [get_bd_pins microblaze_0_axi_periph/M02_ACLK] [get_bd_pins microblaze_0_axi_periph/M03_ACLK] [get_bd_pins microblaze_0_axi_periph/M04_ACLK] [get_bd_pins microblaze_0_axi_periph/M05_ACLK] [get_bd_pins microblaze_0_axi_periph/S00_ACLK] [get_bd_pins microblaze_0_local_memory/LMB_Clk] [get_bd_pins rst_clk_wiz_0_100M/slowest_sync_clk] [get_bd_pins video_out_0/clk_wr_i] [get_bd_pins xadc_wiz_0/s_axi_aclk]
  connect_bd_net -net reset_1 [get_bd_ports rst_i] [get_bd_pins clk_wiz_0/reset] [get_bd_pins rst_clk_wiz_0_100M/ext_reset_in]
  connect_bd_net -net rst_clk_wiz_0_100M_bus_struct_reset [get_bd_pins microblaze_0_local_memory/SYS_Rst] [get_bd_pins rst_clk_wiz_0_100M/bus_struct_reset]
  connect_bd_net -net rst_clk_wiz_0_100M_mb_reset [get_bd_pins microblaze_0/Reset] [get_bd_pins rst_clk_wiz_0_100M/mb_reset]
  connect_bd_net -net rst_clk_wiz_0_100M_peripheral_aresetn [get_bd_pins axi_bram_ctrl_0/s_axi_aresetn] [get_bd_pins axi_bram_ctrl_1/s_axi_aresetn] [get_bd_pins axi_gpio_0/s_axi_aresetn] [get_bd_pins axi_uartlite_0/s_axi_aresetn] [get_bd_pins console_gpu_axi_0/s_axi_aresetn] [get_bd_pins microblaze_0_axi_periph/ARESETN] [get_bd_pins microblaze_0_axi_periph/M00_ARESETN] [get_bd_pins microblaze_0_axi_periph/M01_ARESETN] [get_bd_pins microblaze_0_axi_periph/M02_ARESETN] [get_bd_pins microblaze_0_axi_periph/M03_ARESETN] [get_bd_pins microblaze_0_axi_periph/M04_ARESETN] [get_bd_pins microblaze_0_axi_periph/M05_ARESETN] [get_bd_pins microblaze_0_axi_periph/S00_ARESETN] [get_bd_pins rst_clk_wiz_0_100M/peripheral_aresetn] [get_bd_pins util_vector_logic_0/Op1] [get_bd_pins xadc_wiz_0/s_axi_aresetn]
  connect_bd_net -net util_vector_logic_0_Res [get_bd_pins blitter_0/rst] [get_bd_pins debounce_0/rst_i] [get_bd_pins util_vector_logic_0/Res]
  connect_bd_net -net video_out_0_fb_addr_o [get_bd_pins fb_ram_0/addr_b_i] [get_bd_pins video_out_0/fb_addr_o]
  connect_bd_net -net video_out_0_hsync_o [get_bd_ports hsync_o] [get_bd_pins video_out_0/hsync_o]
  connect_bd_net -net video_out_0_vblank_o [get_bd_pins console_gpu_axi_0/vblank_i] [get_bd_pins video_out_0/vblank_o]
  connect_bd_net -net video_out_0_vga_b_o [get_bd_ports vga_b_o] [get_bd_pins video_out_0/vga_b_o]
  connect_bd_net -net video_out_0_vga_g_o [get_bd_ports vga_g_o] [get_bd_pins video_out_0/vga_g_o]
  connect_bd_net -net video_out_0_vga_r_o [get_bd_ports vga_r_o] [get_bd_pins video_out_0/vga_r_o]
  connect_bd_net -net video_out_0_vsync_o [get_bd_ports vsync_o] [get_bd_pins video_out_0/vsync_o]
  connect_bd_net -net xlconstant_0_dout [get_bd_pins axi_bram_ctrl_0/bram_rddata_a] [get_bd_pins axi_bram_ctrl_1/bram_rddata_a] [get_bd_pins xlconstant_0/dout]
  connect_bd_net -net xlconstant_4_dout [get_bd_pins video_out_0/rst_i] [get_bd_pins xlconstant_4/dout]
  connect_bd_net -net xlconstant_5_dout [get_bd_pins blitter_0/cmd_flip] [get_bd_pins xlconstant_5/dout]
  connect_bd_net -net xlconstant_6_dout [get_bd_pins console_gpu_axi_0/coll_hit_mask_i] [get_bd_pins xlconstant_6/dout]
  connect_bd_net -net xlslice_0_Dout [get_bd_pins asset_rom_0/addr_b_i] [get_bd_pins xlslice_0/Dout]

  # Create address segments
  assign_bd_address -offset 0xC0000000 -range 0x00020000 -target_address_space [get_bd_addr_spaces microblaze_0/Data] [get_bd_addr_segs axi_bram_ctrl_0/S_AXI/Mem0] -force
  assign_bd_address -offset 0xC0020000 -range 0x00004000 -target_address_space [get_bd_addr_spaces microblaze_0/Data] [get_bd_addr_segs axi_bram_ctrl_1/S_AXI/Mem0] -force
  assign_bd_address -offset 0x40000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_0/Data] [get_bd_addr_segs axi_gpio_0/S_AXI/Reg] -force
  assign_bd_address -offset 0x40600000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_0/Data] [get_bd_addr_segs axi_uartlite_0/S_AXI/Reg] -force
  assign_bd_address -offset 0xC4000000 -range 0x00004000 -target_address_space [get_bd_addr_spaces microblaze_0/Data] [get_bd_addr_segs console_gpu_axi_0/s_axi/reg0] -force
  assign_bd_address -offset 0x00000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_0/Data] [get_bd_addr_segs microblaze_0_local_memory/dlmb_bram_if_cntlr/SLMB/Mem] -force
  assign_bd_address -offset 0x44A00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_0/Data] [get_bd_addr_segs xadc_wiz_0/s_axi_lite/Reg] -force
  assign_bd_address -offset 0x00000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_0/Instruction] [get_bd_addr_segs microblaze_0_local_memory/ilmb_bram_if_cntlr/SLMB/Mem] -force


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


