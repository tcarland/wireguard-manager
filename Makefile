CP=cp -r

ifeq ($(TCAMAKE_PREFIX),)
	export TCAMAKE_PREFIX := /usr/local
endif

install:
	$(CP bin/wg.sh $(TCAMAKE_PREFIX)/bin/
	$(CP bin/wireconfig.sh $(TCAMAKE_PREFIX)/bin/
