# make check: the formatting, then every screen driven through its keys on a
# real repo (SEAM_REPO, the lab's excalidraw copy by default).
STYLUA ?= $(HOME)/.local/share/nvim/mason/bin/stylua
SEAM_REPO ?= $(CURDIR)/lab/excalidraw
SEAM_MAX ?= 10

.PHONY: check lint test

check: lint test

lint:
	$(STYLUA) --check lua plugin tests scripts

test:
	SEAM_REPO=$(SEAM_REPO) SEAM_MAX=$(SEAM_MAX) nvim --headless -c 'luafile tests/check.lua'
