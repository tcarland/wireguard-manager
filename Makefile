CP=cp -r

ifeq ($(TCAMAKE_PREFIX),)
	export TCAMAKE_PREFIX := /usr/local
endif

install:
	sudo $(CP) bin/wg.sh $(TCAMAKE_PREFIX)/bin/
	sudo $(CP) bin/wireconfig.sh $(TCAMAKE_PREFIX)/bin/
