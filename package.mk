_clean:
	rm -rf out/$(BUILD_DIR)
	mkdir -p out/$(BUILD_DIR)/control
	mkdir -p out/$(BUILD_DIR)/data

_conffiles:
	cp ipk/conffiles out/$(BUILD_DIR)/control/conffiles

_control:
	echo "Package: antiscan" > out/$(BUILD_DIR)/control/control
	echo "Version: $(VERSION)" >> out/$(BUILD_DIR)/control/control
	echo "Depends: libc, libssp, librt, libpthread, ipset, iptables, curl, jq" >> out/$(BUILD_DIR)/control/control
	echo "License: MIT" >> out/$(BUILD_DIR)/control/control
	echo "Section: net" >> out/$(BUILD_DIR)/control/control
	echo "URL: https://github.com/dimon27254/antiscan" >> out/$(BUILD_DIR)/control/control
	echo "Architecture: all" >> out/$(BUILD_DIR)/control/control
	echo "Description: Antiscan utility" >> out/$(BUILD_DIR)/control/control
	echo "" >> out/$(BUILD_DIR)/control/control

_scripts:
	cp ipk/preinst out/$(BUILD_DIR)/control/preinst
	cp ipk/postinst out/$(BUILD_DIR)/control/postinst
	cp ipk/prerm out/$(BUILD_DIR)/control/prerm
	cp ipk/postrm out/$(BUILD_DIR)/control/postrm
	chmod +x out/$(BUILD_DIR)/control/preinst
	chmod +x out/$(BUILD_DIR)/control/postinst
	chmod +x out/$(BUILD_DIR)/control/prerm
	chmod +x out/$(BUILD_DIR)/control/postrm

_startup:
	cp -r etc/init.d out/$(BUILD_DIR)/data/opt/etc/init.d
	
	chmod +x out/$(BUILD_DIR)/data/opt/etc/init.d/S99ascn

_hook:
	cp -r etc/ndm out/$(BUILD_DIR)/data/opt/etc/ndm
	chmod +x out/$(BUILD_DIR)/data/opt/etc/ndm/netfilter.d/099-ascn.sh

_ipk:
	make _clean

	# control.tar.gz
	make _conffiles
	make _control
	make _scripts
	cd out/$(BUILD_DIR)/control; tar czvf ../control.tar.gz .; cd ../../..

	# data.tar.gz
	mkdir -p out/$(BUILD_DIR)/data/opt/etc
	
	make _startup
	
	cp -r etc/antiscan out/$(BUILD_DIR)/data/opt/etc/antiscan
	chmod +x -R out/$(BUILD_DIR)/data/opt/etc/antiscan/scripts
	
	make _hook

	cd out/$(BUILD_DIR)/data; tar czvf ../data.tar.gz .; cd ../../..

	# ipk
	echo 2.0 > out/$(BUILD_DIR)/debian-binary
	cd out/$(BUILD_DIR); \
	tar czvf ../$(FILENAME) control.tar.gz data.tar.gz debian-binary; \
	cd ../..

package:
	@make \
		BUILD_DIR=antiscan \
		FILENAME=antiscan_$(VERSION)_all.ipk \
		_ipk