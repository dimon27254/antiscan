_repo-clean:
	rm -rf out/_pages/$(BUILD_DIR)
	mkdir -p out/_pages/$(BUILD_DIR)

_repo-copy:
	cp "out/$(FILENAME)" "out/_pages/$(BUILD_DIR)/"

_repo-html:
	echo '<html><head><title>Antiscan repo</title></head><body>' > out/_pages/$(BUILD_DIR)/index.html
	echo '<h1>Index of /$(BUILD_DIR)/</h1><hr>' >> out/_pages/$(BUILD_DIR)/index.html
	echo '<pre>' >> out/_pages/$(BUILD_DIR)/index.html
	echo '<a href="../">../</a>' >> out/_pages/$(BUILD_DIR)/index.html
	echo '<a href="Packages">Packages</a>' >> out/_pages/$(BUILD_DIR)/index.html
	echo '<a href="Packages.gz">Packages.gz</a>' >> out/_pages/$(BUILD_DIR)/index.html
	echo '<a href="$(FILENAME)">$(FILENAME)</a>' >> out/_pages/$(BUILD_DIR)/index.html
	echo '</pre>' >> out/_pages/$(BUILD_DIR)/index.html
	echo '<hr></body></html>' >> out/_pages/$(BUILD_DIR)/index.html

_repo-index:
	echo '<html><head><title>Antiscan repo</title></head><body>' > out/_pages/index.html
	echo '<h1>Index of /</h1><hr>' >> out/_pages/index.html
	echo '<pre>' >> out/_pages/index.html
	echo '<a href="all/">all/</a>' >> out/_pages/index.html
	echo '</pre>' >> out/_pages/index.html
	echo '<hr></body></html>' >> out/_pages/index.html

_repository:
	make _repo-clean
	make _repo-copy

	echo "Package: antiscan" > out/_pages/$(BUILD_DIR)/Packages
	echo "Version: $(VERSION)" >> out/_pages/$(BUILD_DIR)/Packages
	echo "Depends: libc, libssp, librt, libpthread, ipset, iptables, curl, jq" >> out/_pages/$(BUILD_DIR)/Packages
	echo "Section: net" >> out/_pages/$(BUILD_DIR)/Packages
	echo "Architecture: all" >> out/_pages/$(BUILD_DIR)/Packages
	echo "Filename: $(FILENAME)" >> out/_pages/$(BUILD_DIR)/Packages
	echo "Size: $(shell wc -c out/$(FILENAME) | awk '{print $$1}')" >> out/_pages/$(BUILD_DIR)/Packages
	echo "SHA256sum: $(shell sha256sum out/$(FILENAME) | awk '{print $$1}')" >> out/_pages/$(BUILD_DIR)/Packages
	echo "Description:  Antiscan utility" >> out/_pages/$(BUILD_DIR)/Packages
	echo "" >> out/_pages/$(BUILD_DIR)/Packages

	gzip -k out/_pages/$(BUILD_DIR)/Packages

	@make _repo-html

repo:
	@make \
		BUILD_DIR=all \
		FILENAME=antiscan_$(VERSION)_all.ipk \
		_repository

repository: repo _repo-index
