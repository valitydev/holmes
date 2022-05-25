.PHONY: lib

all: submodules lib

submodules:
	@if git submodule status | egrep -q '^[-]|^[+]'; then git submodule update --init; fi

lib:
	$(MAKE) -C lib
