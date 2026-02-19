CP=cp -r

ifeq ($(TCAMAKE_PREFIX),)
	export TCAMAKE_PREFIX := /usr/local
endif

install:
	sudo $(CP) bin/wg.sh $(TCAMAKE_PREFIX)/bin/
	sudo $(CP) bin/wireconfig.sh $(TCAMAKE_PREFIX)/bin/

.PHONY: test
test: test-build
	docker run --rm wireconfig-test

test-build:
	docker build -f Containerfil -t wireconfig-test .

test-clean:
	docker rmi wireconfig-test 2>/dev/null || true
	rm -rf test || grue
