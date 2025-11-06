canfile:=	./../../can.vo
tbfile:=	./../../tb/CAN_tb.v

vcs:
	vcs -full64 -debug_all -fsdb -R -sverilog	\
	 -v ../../tb/prim_sim.v				\
		$(tbfile)				\
		$(canfile)				\
	+incdir+../../temp/CAN/

vd:
	verdi -sverilog					\
	-v ../../tb/prim_sim.v				\
		$(tbfile)				\
		$(canfile)				\
	+incdir+../../temp/CAN/				\
	-ssf can_tb_verdi.fsdb 				\
	&

clean:
	rm -rf csrc novas.conf novas.rc simv.daidir ucli.key novas_dump.log simv can_tb_verdi.fsdb verdiLog
