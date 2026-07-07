.DEFAULT_GOAL := build

APP := vsnap
BUILD_DIR := build
VMODULES_DIR := $(CURDIR)/$(BUILD_DIR)/vmodules
TMP_DIR := $(CURDIR)/$(BUILD_DIR)/tmp
VENV := VMODULES=$(VMODULES_DIR) TMPDIR=$(TMP_DIR)

.PHONY: build test fmt prod smoke edge corruption clean prepare

prepare:
	mkdir -p $(BUILD_DIR) $(BUILD_DIR)/vmodules $(BUILD_DIR)/tmp

build: prepare
	$(VENV) v -o $(BUILD_DIR)/$(APP) src

prod: prepare
	$(VENV) v -prod -o $(BUILD_DIR)/$(APP) src

fmt:
	v fmt -w src scripts

test: build smoke edge corruption

smoke:
	$(VENV) v run scripts/smoke.vsh

edge:
	$(VENV) v run scripts/edge.vsh

corruption:
	$(VENV) v run scripts/corruption.vsh

clean:
	rm -rf $(BUILD_DIR)
