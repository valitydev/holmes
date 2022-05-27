REBAR := rebar3
RELDIR := $(CURDIR)/scripts

.PHONY: all

all: $(RELDIR)/observer-cli

$(RELDIR)/observer-cli: observer_cli
	cd $< && $(REBAR) escriptize
	mkdir -p $(RELDIR)
	cp $</_build/default/bin/observer_cli $(RELDIR)/observer-cli
