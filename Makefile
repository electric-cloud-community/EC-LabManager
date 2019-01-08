#
# Makefile responsible for building the EC-LabManager plugin
#
# Copyright (c) 2005-2012 Electric Cloud, Inc.
# All rights reserved

SRCTOP=..

include $(SRCTOP)/build/vars.mak

build: buildJavaPlugin
unittest: modtest
systemtest:

include $(SRCTOP)/build/rules.mak

TEST_SERVER_PORT         ?= 0

modtest:
		$(EC_PERL) $(NTEST) $(NTESTARGS) --testout $(OUTDIR)/ntest --auxport $(TEST_SERVER_PORT) src/test/ntest
