BINARY_NAME := CheLiveDocsMCP

.PHONY: build test clean verify-developer-id install install-signed release-signed

build:
	swift build

test:
	swift test

clean:
	swift package clean

# Fail-fast if DEVELOPER_ID is missing (left-most dep on signed targets so a
# missing env var aborts before the ~30s `swift build -c release`).
verify-developer-id:
	@: $${DEVELOPER_ID:?DEVELOPER_ID not set. See README 'Signing & Notarization'.}

# Local dev install, ad-hoc signed. LiveDocs is network-only (no TCC), so unlike
# the Apple-app MCPs an ad-hoc binary works fine for personal use — no FDA grant
# to lose on rebuild. rm -f forces a fresh inode (avoids "load code signature
# error 2" SIGKILL when an old inode is held open by a running process).
install: build
	rm -f ~/bin/$(BINARY_NAME)
	cp .build/debug/$(BINARY_NAME) ~/bin/$(BINARY_NAME)
	chmod +x ~/bin/$(BINARY_NAME)
	codesign --force --sign - ~/bin/$(BINARY_NAME)
	@echo "Installed: ~/bin/$(BINARY_NAME) (ad-hoc — fine for network-only local use)"

# Dev install with a Developer ID signature (no notarization). Needed only if you
# want the distribution-identical signature locally.
install-signed: verify-developer-id
	swift build -c release
	rm -f ~/bin/$(BINARY_NAME)
	cp .build/release/$(BINARY_NAME) ~/bin/$(BINARY_NAME)
	chmod +x ~/bin/$(BINARY_NAME)
	codesign --force --options runtime --identifier "$(BINARY_NAME)" --sign "$$DEVELOPER_ID" ~/bin/$(BINARY_NAME)
	@echo "Installed: ~/bin/$(BINARY_NAME) (Developer ID signed)"

# Distribution release: universal build + Developer ID sign + notarize + publish
# to GitHub. Wraps scripts/release.sh with REQUIRE_CODESIGN=1.
# Usage: make release-signed VERSION=vX.Y.Z
release-signed: verify-developer-id
	@: $${VERSION:?VERSION not set. Usage: make release-signed VERSION=vX.Y.Z}
	@: $${NOTARY_PROFILE:?NOTARY_PROFILE not set. See README 'Signing & Notarization'.}
	REQUIRE_CODESIGN=1 ./scripts/release.sh "$(VERSION)"
