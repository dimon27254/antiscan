SHELL := /bin/bash
VERSION := $(shell sed -n 's/^ASCN_VERSION="\([^"]*\)"$$/\1/p' etc/init.d/S99ascn)

include package.mk
include repository.mk

.DEFAULT_GOAL := package

clean:
	rm -rf out/$(BUILD_DIR)
