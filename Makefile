include $(TOPDIR)/rules.mk

PKG_NAME:=antiscan
PKG_VERSION:=1.0

include $(INCLUDE_DIR)/package.mk

define Package/antiscan
	SECTION:=net
	CATEGORY:=Network
	DEPENDS:=+ipset +iptables
	TITLE:=antiscan utility
	PKGARCH:=all
endef

define Build/Compile
endef

define Package/antiscan/conffiles
/opt/etc/ascn.conf
endef

define Package/antiscan/install
	$(INSTALL_DIR) $(1)/opt/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/S99ascn $(1)/opt/etc/init.d
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/ascn.conf $(1)/opt/etc
	$(INSTALL_DIR) $(1)/opt/etc/ndm/netfilter.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/099-ascn.sh $(1)/opt/etc/ndm/netfilter.d
endef

define Package/antiscan/postinst
#!/bin/sh
crontab -l > "/tmp/crontasks"
echo "*/1 * * * * /opt/etc/init.d/S99ascn read_candidates &" >> "/tmp/crontasks"
crontab "/tmp/crontasks"
rm "/tmp/crontasks"
endef

define Package/antiscan/prerm
#!/bin/sh
/opt/etc/init.d/S99ascn stop
endef

define Package/antiscan/postrm
#!/bin/sh
crontab -l | sed -E '/\*\/1 \* \* \* \* \/opt\/etc\/init\.d\/S99ascn read_candidates &/d' | crontab -
endef

$(eval $(call BuildPackage,antiscan))
