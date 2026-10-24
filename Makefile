PREFIX ?= /usr/local

.PHONY: install uninstall test check status validate lint clean

install:
	./install.sh

uninstall:
	./uninstall.sh

validate:
	python3 tools/validate_devices.py devices

test: validate
	python3 -m py_compile bin/honorfnpp tools/validate_devices.py
	bash -n install.sh uninstall.sh tools/power-test.sh
	@echo "syntax OK"

lint: validate
	python3 -m py_compile bin/honorfnpp tools/validate_devices.py
	bash -n install.sh uninstall.sh tools/power-test.sh
	@command -v shellcheck >/dev/null && shellcheck install.sh uninstall.sh tools/power-test.sh || \
		echo "shellcheck not installed; skipped"

check:
	./bin/honorfnpp check

status:
	./bin/honorfnpp status

clean:
	rm -rf bin/__pycache__ tools/__pycache__ __pycache__
