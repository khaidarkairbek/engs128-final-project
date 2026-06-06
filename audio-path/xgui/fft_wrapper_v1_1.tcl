# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "AUDIO_DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "BRAM_READ_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "C_AXI_STREAM_DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "FFT_LENGTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "FFT_LENGTH_LOG2" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MAG_WIDTH" -parent ${Page_0}


}

proc update_PARAM_VALUE.AUDIO_DATA_WIDTH { PARAM_VALUE.AUDIO_DATA_WIDTH } {
	# Procedure called to update AUDIO_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.AUDIO_DATA_WIDTH { PARAM_VALUE.AUDIO_DATA_WIDTH } {
	# Procedure called to validate AUDIO_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.BRAM_READ_ADDR_WIDTH { PARAM_VALUE.BRAM_READ_ADDR_WIDTH } {
	# Procedure called to update BRAM_READ_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BRAM_READ_ADDR_WIDTH { PARAM_VALUE.BRAM_READ_ADDR_WIDTH } {
	# Procedure called to validate BRAM_READ_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.C_AXI_STREAM_DATA_WIDTH { PARAM_VALUE.C_AXI_STREAM_DATA_WIDTH } {
	# Procedure called to update C_AXI_STREAM_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_AXI_STREAM_DATA_WIDTH { PARAM_VALUE.C_AXI_STREAM_DATA_WIDTH } {
	# Procedure called to validate C_AXI_STREAM_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.FFT_LENGTH { PARAM_VALUE.FFT_LENGTH } {
	# Procedure called to update FFT_LENGTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FFT_LENGTH { PARAM_VALUE.FFT_LENGTH } {
	# Procedure called to validate FFT_LENGTH
	return true
}

proc update_PARAM_VALUE.FFT_LENGTH_LOG2 { PARAM_VALUE.FFT_LENGTH_LOG2 } {
	# Procedure called to update FFT_LENGTH_LOG2 when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FFT_LENGTH_LOG2 { PARAM_VALUE.FFT_LENGTH_LOG2 } {
	# Procedure called to validate FFT_LENGTH_LOG2
	return true
}

proc update_PARAM_VALUE.MAG_WIDTH { PARAM_VALUE.MAG_WIDTH } {
	# Procedure called to update MAG_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MAG_WIDTH { PARAM_VALUE.MAG_WIDTH } {
	# Procedure called to validate MAG_WIDTH
	return true
}


proc update_MODELPARAM_VALUE.C_AXI_STREAM_DATA_WIDTH { MODELPARAM_VALUE.C_AXI_STREAM_DATA_WIDTH PARAM_VALUE.C_AXI_STREAM_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_AXI_STREAM_DATA_WIDTH}] ${MODELPARAM_VALUE.C_AXI_STREAM_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.AUDIO_DATA_WIDTH { MODELPARAM_VALUE.AUDIO_DATA_WIDTH PARAM_VALUE.AUDIO_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.AUDIO_DATA_WIDTH}] ${MODELPARAM_VALUE.AUDIO_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.FFT_LENGTH { MODELPARAM_VALUE.FFT_LENGTH PARAM_VALUE.FFT_LENGTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FFT_LENGTH}] ${MODELPARAM_VALUE.FFT_LENGTH}
}

proc update_MODELPARAM_VALUE.FFT_LENGTH_LOG2 { MODELPARAM_VALUE.FFT_LENGTH_LOG2 PARAM_VALUE.FFT_LENGTH_LOG2 } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FFT_LENGTH_LOG2}] ${MODELPARAM_VALUE.FFT_LENGTH_LOG2}
}

proc update_MODELPARAM_VALUE.MAG_WIDTH { MODELPARAM_VALUE.MAG_WIDTH PARAM_VALUE.MAG_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MAG_WIDTH}] ${MODELPARAM_VALUE.MAG_WIDTH}
}

proc update_MODELPARAM_VALUE.BRAM_READ_ADDR_WIDTH { MODELPARAM_VALUE.BRAM_READ_ADDR_WIDTH PARAM_VALUE.BRAM_READ_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BRAM_READ_ADDR_WIDTH}] ${MODELPARAM_VALUE.BRAM_READ_ADDR_WIDTH}
}

