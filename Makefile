include $(TOPDIR)/rules.mk

PKG_NAME:=antiscan
PKG_VERSION:=1.2

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
if [ -f "$$CONFIG_FILE" ]; then
  save_ipsets_str="$$(grep "SAVE_IPSETS" "$$CONFIG_FILE")"
  ipset_save_path_str="$$(grep "IPSETS_SAVE_PATH" "$$CONFIG_FILE")"
  rules_mask_str="$$(grep "RULES_MASK" "$$CONFIG_FILE")"
  if [ -z "$$save_ipsets_str" ]; then
    printf "\nSAVE_IPSETS=0\n" >>"$$CONFIG_FILE"
    printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}SAVE_IPSETS=0$${NO_STYLE}\n"
  else
	source "$$CONFIG_FILE"
	if [ "$$SAVE_IPSETS" -eq 1 ] && [ -n "$$IPSETS_SAVE_PATH" ]; then
		[ "$$RECENT_CONNECTIONS_BANTIME" -ne 0 ] && sed -i 's/RECENT_CONNECTIONS_BANTIME=[0-9]\+/RECENT_CONNECTIONS_BANTIME=0/' "$$CONFIG_FILE"
		[ "$$SUBNETS_BANTIME" -ne 0 ] && sed -i 's/SUBNETS_BANTIME=[0-9]\+/SUBNETS_BANTIME=0/' "$$CONFIG_FILE"
	fi
  fi
  if [ -z "$$ipset_save_path_str" ]; then
    printf "IPSETS_SAVE_PATH=\"\"\n" >>"$$CONFIG_FILE"
    printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}IPSETS_SAVE_PATH=\"\"$${NO_STYLE}\n"
  fi
  if [ -z "$$rules_mask_str" ]; then
	sed -i '/^RECENT_CONNECTIONS_TIME=/iRULES_MASK=\"255.255.255.255\"' "/opt/etc/ascn.conf"
	printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}RULES_MASK=\"255.255.255.255\"$${NO_STYLE}\n"
  fi
fi
endef

define Package/antiscan/postinst
#!/bin/sh
ANTISCAN_LINK="/opt/bin/antiscan"
if [ ! -L "$$ANTISCAN_LINK" ]; then
ln -s /opt/etc/init.d/S99ascn "$$ANTISCAN_LINK"
fi
crontab -l > "/tmp/crontasks"
echo "*/1 * * * * /opt/etc/init.d/S99ascn read_candidates &" >> "/tmp/crontasks"
echo "0 0 */5 * * /opt/etc/init.d/S99ascn save_ipsets &" >> "/tmp/crontasks"
crontab "/tmp/crontasks"
rm "/tmp/crontasks"
endef

define Package/antiscan/prerm
#!/bin/sh
ANTISCAN_LINK="/opt/bin/antiscan"
/opt/etc/init.d/S99ascn stop
if [ -L "$$ANTISCAN_LINK" ]; then
rm "$$ANTISCAN_LINK"
fi
endef

define Package/antiscan/postrm
#!/bin/sh
crontab -l | sed '/S99ascn/d' | crontab -
endef

$(eval $(call BuildPackage,antiscan))
