#! /usr/bin/make -f

SCRIPTS=javacg2dot.pl
TARGETS=README.md

.PHONY: all check clean

all: $(TARGETS)
README.md: $(SCRIPTS)
	pod2markdown $(SCRIPTS) > README.md
check:
	cd t && make check
	perlcritic $(SCRIPTS)
	podchecker $(SCRIPTS)
clean:
	rm -f $(TARGETS)
	cd t && make clean
