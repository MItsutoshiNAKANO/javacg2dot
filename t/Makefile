#! /usr/bin/make -f

TARGETS=unit_test.svg init_test.svg commons-cli.svg
DOTS=$(TARGETS:.svg=.dot)

.PHONY: all check test clean
.PRECIOUS: %.dot

all: check
check: test $(TARGETS)
test:
	prove -l javacg2dot.t
	perlcritic javacg2dot.t
clean:
	rm -f $(TARGETS) $(DOTS)

%.dot: %.javacg-static.txt
	../javacg2dot.pl $< >$@
%.svg: %.dot
	dot -Tsvg $< >$@
