include $(TOPDIR)/rules.mk

PKG_NAME:=antiscan
PKG_VERSION:=1.3.1

include $(INCLUDE_DIR)/package.mk

define Package/antiscan
	SECTION:=net
	CATEGORY:=Network
	DEPENDS:=+ipset +iptables +curl +jq
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
if [ -s "$$CONFIG_FILE" ]; then
  rules_mask_str="$$(grep "RULES_MASK" "$$CONFIG_FILE")"
  save_ipsets_str="$$(grep "SAVE_IPSETS" "$$CONFIG_FILE")"
  ipset_save_path_old_str="$$(grep "IPSETS_SAVE_PATH" "$$CONFIG_FILE")"
  use_custom_exclude_str="$$(grep "USE_CUSTOM_EXCLUDE_LIST" "$$CONFIG_FILE")"
  custom_lists_block_mode_str="$$(grep "CUSTOM_LISTS_BLOCK_MODE" "$$CONFIG_FILE")"
  geoblock_mode_str="$$(grep "GEOBLOCK_MODE" "$$CONFIG_FILE")"
  geoblock_countries_str="$$(grep "GEOBLOCK_COUNTRIES" "$$CONFIG_FILE")"

  if [ -z "$$rules_mask_str" ]; then
	sed -i '/^RECENT_CONNECTIONS_TIME=/iRULES_MASK=\"255.255.255.255\"' "/opt/etc/ascn.conf"
	printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}RULES_MASK=\"255.255.255.255\"$${NO_STYLE}\n"
  fi
  if [ -n "$$ipset_save_path_old_str" ]; then
	sed -i 's/^IPSETS_SAVE_PATH/IPSETS_DIRECTORY/' "/opt/etc/ascn.conf"
    printf "В имеющемся ascn.conf строка $${BOLD_TEXT}IPSETS_SAVE_PATH$${NO_STYLE} заменена на $${BOLD_TEXT}IPSETS_DIRECTORY$${NO_STYLE}\n"
  fi
  if [ -z "$$(grep "IPSETS_DIRECTORY" "$$CONFIG_FILE")" ]; then
    printf "\n\nIPSETS_DIRECTORY=\"\"\n" >>"$$CONFIG_FILE"
    printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}IPSETS_DIRECTORY=\"\"$${NO_STYLE}\n"
  fi
  if [ -z "$$save_ipsets_str" ]; then
    printf "SAVE_IPSETS=0\n" >>"$$CONFIG_FILE"
    printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}SAVE_IPSETS=0$${NO_STYLE}\n"
  fi
  if [ -z "$$use_custom_exclude_str" ]; then
    printf "\nUSE_CUSTOM_EXCLUDE_LIST=0\n" >>"$$CONFIG_FILE"
    printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}USE_CUSTOM_EXCLUDE_LIST=0$${NO_STYLE}\n"
  fi
  if [ -z "$$custom_lists_block_mode_str" ]; then
    printf "CUSTOM_LISTS_BLOCK_MODE=0\n" >>"$$CONFIG_FILE"
    printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}CUSTOM_LISTS_BLOCK_MODE=0$${NO_STYLE}\n"
  fi
  if [ -z "$$geoblock_mode_str" ]; then
    printf "GEOBLOCK_MODE=0\n" >>"$$CONFIG_FILE"
    printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}GEOBLOCK_MODE=0$${NO_STYLE}\n"
  fi
  if [ -z "$$geoblock_countries_str" ]; then
    printf "GEOBLOCK_COUNTRIES=\"\"\n" >>"$$CONFIG_FILE"
    printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}GEOBLOCK_COUNTRIES=\"\"$${NO_STYLE}\n"
  fi
fi
endef

define Package/antiscan/postinst
#!/bin/sh
ANTISCAN_LINK="/opt/bin/antiscan"
CONFIG_FILE="/opt/etc/ascn.conf"
if [ ! -L "$$ANTISCAN_LINK" ]; then
  ln -s /opt/etc/init.d/S99ascn "$$ANTISCAN_LINK"
fi

if [ -s "$$CONFIG_FILE" ]; then
  source "$$CONFIG_FILE"
  if [ -n "$$IPSETS_DIRECTORY" ]; then
    ascn_custom_directory="$$IPSETS_DIRECTORY/custom"
    ascn_geo_directory="$$IPSETS_DIRECTORY/geo"
	ascn_custom_blacklist_file="$$ascn_custom_directory/ascn_custom_blacklist.txt"
	ascn_custom_whitelist_file="$$ascn_custom_directory/ascn_custom_whitelist.txt"
	ascn_custom_exclude_file="$$ascn_custom_directory/ascn_custom_exclude.txt"
	[ ! -d "$$ascn_custom_directory" ] && mkdir "$$ascn_custom_directory"
	[ ! -f "$$ascn_custom_blacklist_file" ] && echo >"$$ascn_custom_blacklist_file"
	[ ! -f "$$ascn_custom_whitelist_file" ] && echo >"$$ascn_custom_whitelist_file"
	[ ! -f "$$ascn_custom_exclude_file" ] && echo >"$$ascn_custom_exclude_file"
	[ ! -d "$$ascn_geo_directory" ] && mkdir "$$ascn_geo_directory"
  fi
fi

crontab -l > "/tmp/crontasks"
echo "*/1 * * * * /opt/etc/init.d/S99ascn read_candidates &" >> "/tmp/crontasks"
echo "0 0 */5 * * /opt/etc/init.d/S99ascn save_ipsets &" >> "/tmp/crontasks"
echo "0 5 */15 * * /opt/etc/init.d/S99ascn update_ipsets geo &" >> "/tmp/crontasks"
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
