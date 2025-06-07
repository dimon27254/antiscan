include $(TOPDIR)/rules.mk

PKG_NAME:=antiscan
PKG_VERSION:=1.4

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
/opt/etc/antiscan/ascn.conf
/opt/etc/antiscan/ascn_crontab.conf
/opt/etc/antiscan/ascn_custom_blacklist.txt
/opt/etc/antiscan/ascn_custom_whitelist.txt
/opt/etc/antiscan/ascn_custom_exclude.txt
endef

define Package/antiscan/install
	$(INSTALL_DIR) $(1)/opt/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/S99ascn $(1)/opt/etc/init.d
	$(INSTALL_DIR) $(1)/opt/etc/antiscan
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/ascn.conf $(1)/opt/etc/antiscan
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/ascn_crontab.conf $(1)/opt/etc/antiscan
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/ascn_custom_blacklist.txt $(1)/opt/etc/antiscan
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/ascn_custom_whitelist.txt $(1)/opt/etc/antiscan
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/ascn_custom_exclude.txt $(1)/opt/etc/antiscan
	$(INSTALL_DIR) $(1)/opt/etc/ndm/netfilter.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/099-ascn.sh $(1)/opt/etc/ndm/netfilter.d
endef

define Package/antiscan/preinst
#!/bin/sh
ANTISCAN_DIR="/opt/etc/antiscan"
OLD_CONFIG_FILE="/opt/etc/ascn.conf"
CONFIG_FILE="$$ANTISCAN_DIR/ascn.conf"
BOLD_TEXT="\033[1m"
NO_STYLE="\033[0m"
if [ -s "$$OLD_CONFIG_FILE" ]; then
    if [ ! -d "$$ANTISCAN_DIR" ]; then
        mkdir "$$ANTISCAN_DIR"
    fi
    if cp -f "$$OLD_CONFIG_FILE" "$$CONFIG_FILE"; then
        printf "Имеющийся ascn.conf был перемещен в каталог $${BOLD_TEXT}/opt/etc/antiscan$${NO_STYLE}\n"
    fi
fi
if [ -s "$$CONFIG_FILE" ]; then
    rules_mask_str="$$(grep "RULES_MASK" "$$CONFIG_FILE")"
    save_ipsets_str="$$(grep "SAVE_IPSETS" "$$CONFIG_FILE")"
    ipset_save_path_old_str="$$(grep "IPSETS_SAVE_PATH" "$$CONFIG_FILE")"
    use_custom_exclude_str="$$(grep "USE_CUSTOM_EXCLUDE_LIST" "$$CONFIG_FILE")"
    custom_lists_block_mode_str="$$(grep "CUSTOM_LISTS_BLOCK_MODE" "$$CONFIG_FILE")"
    geoblock_mode_str="$$(grep "GEOBLOCK_MODE" "$$CONFIG_FILE")"
    geoblock_countries_str="$$(grep "GEOBLOCK_COUNTRIES" "$$CONFIG_FILE")"
    if [ -z "$$rules_mask_str" ]; then
        sed -i '/^RECENT_CONNECTIONS_TIME=/iRULES_MASK=\"255.255.255.255\"' "$$CONFIG_FILE"
        printf "В имеющийся ascn.conf добавлена новая строка $${BOLD_TEXT}RULES_MASK=\"255.255.255.255\"$${NO_STYLE}\n"
    fi
    if [ -n "$$ipset_save_path_old_str" ]; then
        sed -i 's/^IPSETS_SAVE_PATH/IPSETS_DIRECTORY/' "$$CONFIG_FILE"
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
ANTISCAN_DIR="/opt/etc/antiscan"
CONFIG_FILE="$$ANTISCAN_DIR/ascn.conf"
OLD_CONFIG_FILES="/opt/etc/ascn.conf-opkg /opt/etc/ascn.conf-opkg.backup"
BOLD_TEXT="\033[1m"
NO_STYLE="\033[0m"

if [ ! -L "$$ANTISCAN_LINK" ]; then
    ln -s /opt/etc/init.d/S99ascn "$$ANTISCAN_LINK"
fi

source "$$CONFIG_FILE"
if [ -n "$$IPSETS_DIRECTORY" ]; then
    ascn_custom_directory="$$IPSETS_DIRECTORY/custom"
    ascn_geo_directory="$$IPSETS_DIRECTORY/geo"
    ascn_custom_files="ascn_custom_blacklist.txt ascn_custom_whitelist.txt ascn_custom_exclude.txt"

    if [ -d "$$ascn_custom_directory" ]; then
        for custom_file in $$ascn_custom_files; do
            if [ -f "$$ascn_custom_directory/$$custom_file" ]; then
                mv -f "$$ascn_custom_directory/$$custom_file" "$$ANTISCAN_DIR/$$custom_file" && printf "Имеющийся $$custom_file был перемещен в каталог $${BOLD_TEXT}/opt/etc/antiscan$${NO_STYLE}\n"
            fi
        done
        rm -r "$$ascn_custom_directory"
    fi

    if [ ! -d "$$ascn_geo_directory" ]; then
        mkdir "$$ascn_geo_directory"
    fi
fi

for old_file in $$OLD_CONFIG_FILES; do
    if [ -f "$$old_file" ]; then
        rm "$$old_file"
    fi
done
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
crontab_bin="/opt/bin/crontab"
if [ -f "$$crontab_bin" ]; then
  crontab -l | sed '/S99ascn/d' | crontab -
else
  echo "crontab не найден! У вас не установлен cron?"
fi
endef

$(eval $(call BuildPackage,antiscan))
