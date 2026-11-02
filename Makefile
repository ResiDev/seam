# make check: the formatting, here's, the types', the Types view's, the outline's, the names', what changed's, the Map's and the package lookups' specs,
# then every screen driven through its keys on a real repo (SEAM_REPO, the
# lab's excalidraw copy by default).
STYLUA ?= $(HOME)/.local/share/nvim/mason/bin/stylua
SEAM_REPO ?= $(CURDIR)/lab/excalidraw
SEAM_MAX ?= 10

.PHONY: check lint spec test view

check: lint test

lint:
	$(STYLUA) --check lua plugin tests scripts

spec:
	nvim --headless --clean -l tests/here.lua
	nvim --headless --clean -l tests/types.lua
	nvim --headless --clean -l tests/typesview.lua
	nvim --headless --clean -l tests/outline.lua
	nvim --headless --clean -l tests/names.lua
	nvim --headless --clean -l tests/changes.lua
	nvim --headless --clean -l tests/map.lua
	nvim --headless --clean -l tests/lookup.lua

test: spec
	SEAM_REPO=$(SEAM_REPO) SEAM_MAX=$(SEAM_MAX) nvim --headless -c 'luafile tests/check.lua'

# Drive it and see it: STEPS='j; j; <CR>' on REPO, and what it showed after
# each, as text, a picture and seam.state (tests/view.lua says the rest).
view:
	@nvim --headless --clean -l tests/view.lua
