include $(TOPDIR)/rules.mk

PKG_NAME:=antiscan
PKG_VERSION:=1.1

include $(INCLUDE_DIR)/package.mk

define Package/antiscan
	SECTION:=net
	CATEGORY:=Network
	DEPENDS:=+ipset +iptables
	TITLE:=Antiscan utility
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

define Package/antiscan/preinst
#!/bin/sh
CONFIG_FILE="/opt/etc/ascn.conf"
BOLD_TEXT="\033[1m"
NO_STYLE="\033[0m"
echo "$$CONFIG_FILE"
if [ -f "$$CONFIG_FILE" ]; then
  save_ipsets_str="$$(cat "$$CONFIG_FILE" | grep "SAVE_IPSETS")"
  ipset_save_path_str="$$(cat "$$CONFIG_FILE" | grep "IPSETS_SAVE_PATH")"
  if [ -z "$$save_ipsets_str" ]; then
    printf "\nSAVE_IPSETS=0\n" >>"$$CONFIG_FILE"
    printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}SAVE_IPSETS=0$${NO_STYLE}\n"
  fi
  if [ -z "$$ipset_save_path_str" ]; then
    printf "IPSETS_SAVE_PATH=\"\"\n" >>"$$CONFIG_FILE"
    printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}IPSETS_SAVE_PATH=\"\"$${NO_STYLE}\n"
  fi
fi
endef

define Package/antiscan/postinst
#!/bin/sh
crontab -l > "/tmp/crontasks"
echo "*/1 * * * * /opt/etc/init.d/S99ascn read_candidates &" >> "/tmp/crontasks"
echo "0 0 */5 * * /opt/etc/init.d/S99ascn save_ipsets &" >> "/tmp/crontasks"
crontab "/tmp/crontasks"
rm "/tmp/crontasks"
endef

define Package/antiscan/prerm
#!/bin/sh
/opt/etc/init.d/S99ascn stop
endef

define Package/antiscan/postrm
#!/bin/sh
crontab -l | sed '/S99ascn/d' | crontab -
endef

$(eval $(call BuildPackage,antiscan))
