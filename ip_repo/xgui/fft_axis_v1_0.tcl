# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "FFT_N" -parent ${Page_0}
  ipgui::add_param $IPINST -name "LOG2_N" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PIPE_DUBINA" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SIRINA_PODATAKA" -parent ${Page_0}


}

proc update_PARAM_VALUE.FFT_N { PARAM_VALUE.FFT_N } {
	# Procedure called to update FFT_N when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FFT_N { PARAM_VALUE.FFT_N } {
	# Procedure called to validate FFT_N
	return true
}

proc update_PARAM_VALUE.LOG2_N { PARAM_VALUE.LOG2_N } {
	# Procedure called to update LOG2_N when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.LOG2_N { PARAM_VALUE.LOG2_N } {
	# Procedure called to validate LOG2_N
	return true
}

proc update_PARAM_VALUE.PIPE_DUBINA { PARAM_VALUE.PIPE_DUBINA } {
	# Procedure called to update PIPE_DUBINA when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PIPE_DUBINA { PARAM_VALUE.PIPE_DUBINA } {
	# Procedure called to validate PIPE_DUBINA
	return true
}

proc update_PARAM_VALUE.SIRINA_PODATAKA { PARAM_VALUE.SIRINA_PODATAKA } {
	# Procedure called to update SIRINA_PODATAKA when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SIRINA_PODATAKA { PARAM_VALUE.SIRINA_PODATAKA } {
	# Procedure called to validate SIRINA_PODATAKA
	return true
}


proc update_MODELPARAM_VALUE.FFT_N { MODELPARAM_VALUE.FFT_N PARAM_VALUE.FFT_N } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FFT_N}] ${MODELPARAM_VALUE.FFT_N}
}

proc update_MODELPARAM_VALUE.LOG2_N { MODELPARAM_VALUE.LOG2_N PARAM_VALUE.LOG2_N } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.LOG2_N}] ${MODELPARAM_VALUE.LOG2_N}
}

proc update_MODELPARAM_VALUE.SIRINA_PODATAKA { MODELPARAM_VALUE.SIRINA_PODATAKA PARAM_VALUE.SIRINA_PODATAKA } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SIRINA_PODATAKA}] ${MODELPARAM_VALUE.SIRINA_PODATAKA}
}

proc update_MODELPARAM_VALUE.PIPE_DUBINA { MODELPARAM_VALUE.PIPE_DUBINA PARAM_VALUE.PIPE_DUBINA } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PIPE_DUBINA}] ${MODELPARAM_VALUE.PIPE_DUBINA}
}

