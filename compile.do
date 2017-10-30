vlog drawlines.v
vlog vga_adapter/*.v

set qroot $env(QUARTUS_ROOTDIR)
set lib_files {altera_mf.v 220model.v}
foreach f $lib_files {
	vlog [file join $qroot eda sim_lib $f]
}

vsim -novopt drawlines

log {/*}
add wave {/*}
