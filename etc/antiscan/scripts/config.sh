CONFIG_FILE="$ANTISCAN_DIR/ascn.conf"
CONFIG_FILE_TEMP="/tmp/ascn.conf.tmp"

ASCN_LOCK_FILE="/tmp/ascn.lock"

create_lock_file() {
  echo "1" >"$ASCN_LOCK_FILE"
}

remove_lock_file() {
  if config_is_reloading; then
    rm "$ASCN_LOCK_FILE"
  fi
}

read_config() {
  case "$1" in
  edit | config | conf | crontab | cron)
    :
    ;;
  *)
    source "$CONFIG_FILE"
    check_config
    if [ -f "$CONFIG_FILE_TEMP" ]; then
      source "$CONFIG_FILE_TEMP"
    fi
    ;;
  esac
}

check_config() {
  if [ -z "$ISP_INTERFACES" ]; then
    print_message "error" "В ascn.conf не указаны интерфейсы!"
    exit 3
  fi

  [ -z "$ENABLE_IPS_BAN" ] && ENABLE_IPS_BAN=1
  [ -z "$ENABLE_HONEYPOT" ] && ENABLE_HONEYPOT=0

  if [ -z "$PORTS" ] && [ -z "$PORTS_FORWARDED" ]; then
    print_message "error" "В ascn.conf не указаны порты!"
    exit 3
  else
    local ports_count=0
    local ports_forwarded_count=0
    local ports_honeypot_count=0
    local need_to_exit=0
    if [ -n "$PORTS" ]; then
      ports_count=$(
        set -- $(echo "$PORTS" | tr ',:' ' ')
        echo $#
      )
    fi
    if [ -n "$PORTS_FORWARDED" ]; then
      ports_forwarded_count=$(
        set -- $(echo "$PORTS_FORWARDED" | tr ',:' ' ')
        echo $#
      )
    fi
    if [ "$ENABLE_HONEYPOT" == "1" ] && [ -n "$HONEYPOT_PORTS" ]; then
      ports_honeypot_count=$(
        set -- $(echo "$HONEYPOT_PORTS" | tr ',:' ' ')
        echo $#
      )
    fi
    if [ "$ports_count" -gt 15 ]; then
      print_message "error" "Количество указанных портов превышает 15"
      need_to_exit=1
    fi
    if [ "$ports_forwarded_count" -gt 15 ]; then
      print_message "error" "Количество указанных переадресованных портов превышает 15"
      need_to_exit=1
    fi
    if [ "$ports_honeypot_count" -gt 15 ]; then
      print_message "error" "Количество указанных портов для ловушки превышает 15"
      need_to_exit=1
    fi
    [ "$need_to_exit" -eq 1 ] && exit 4
  fi

  if [ "$ENABLE_IPS_BAN" == "1" ]; then
    if [ -z "$RECENT_CONNECTIONS_TIME" ] || [ -z "$RECENT_CONNECTIONS_HITCOUNT" ] || [ -z "$RECENT_CONNECTIONS_LIMIT" ] ||
      [ -z "$DIFFERENT_IP_THRESHOLD" ] || [ -z "$RECENT_CONNECTIONS_BANTIME" ] || [ -z "$DIFFERENT_IP_CANDIDATES_STORAGETIME" ] || [ -z "$SUBNETS_BANTIME" ]; then
      print_message "error" "В ascn.conf не указаны параметры работы Antiscan!"
      exit 3
    fi
    [ -z "$RULES_MASK" ] && RULES_MASK="255.255.255.255"
    if [ "$RECENT_CONNECTIONS_BANTIME" -gt 2147483 ] || [ "$DIFFERENT_IP_CANDIDATES_STORAGETIME" -gt 2147483 ] || [ "$SUBNETS_BANTIME" -gt 2147483 ]; then
      print_message "error" "Срок хранения записей в списках не может превышать 2147483 секунды"
      exit 4
    fi
  fi

  [ -z "$SAVE_IPSETS" ] && SAVE_IPSETS=0
  [ -z "$USE_CUSTOM_EXCLUDE_LIST" ] && USE_CUSTOM_EXCLUDE_LIST=0
  [ -z "$READ_NDM_LOCKOUT_IPSETS" ] && READ_NDM_LOCKOUT_IPSETS=0
  [ -z "$LOCKOUT_IPSET_BANTIME" ] && LOCKOUT_IPSET_BANTIME=0
  [ -z "$HONEYPOT_BANTIME" ] && HONEYPOT_BANTIME=0

  if [ "$LOCKOUT_IPSET_BANTIME" -gt 2147483 ] || [[ "$ENABLE_HONEYPOT" == "1" && "$HONEYPOT_BANTIME" -gt 2147483 ]]; then
    print_message "error" "Срок хранения записей в списках не может превышать 2147483 секунды"
    exit 4
  fi

  if [ -z "$CUSTOM_LISTS_BLOCK_MODE" ]; then
    CUSTOM_LISTS_BLOCK_MODE=0
  else
    case "$CUSTOM_LISTS_BLOCK_MODE" in
    0 | blacklist | whitelist)
      :
      ;;
    *)
      print_message "error" "Указан недопустимый режим блокировки по пользовательским спискам"
      exit 4
      ;;
    esac
  fi

  if [ -z "$GEOBLOCK_MODE" ]; then
    GEOBLOCK_MODE=0
  else
    case "$GEOBLOCK_MODE" in
    0 | blacklist | whitelist)
      :
      ;;
    *)
      print_message "error" "Указан недопустимый режим геоблокировки"
      exit 4
      ;;
    esac
  fi

  if [ -z "$GEO_EXCLUDE_COUNTRIES" ]; then
    GEO_EXCLUDE_COUNTRIES=""
  else
    echo "$GEO_EXCLUDE_COUNTRIES" | grep -Eq '^([A-Z]{2})( +[A-Z]{2} {0,})*$'
    local validation_result=$?
    if [ "$validation_result" -eq 0 ]; then
      local count=$(
        set -- $GEO_EXCLUDE_COUNTRIES
        echo $#
      )
      if [ "$count" -gt 8 ]; then
        print_message "error" "Количество указанных стран-исключений превышает 8"
        exit 4
      fi
    else
      print_message "error" "Список стран-исключений содержит недопустимые символы"
      exit 3
    fi
  fi

  if [ -z "$IPSETS_DIRECTORY" ] && [[ "$SAVE_IPSETS" == "1" || "$GEOBLOCK_MODE" != "0" || "$GEO_EXCLUDE_COUNTRIES" != "" ]]; then
    print_message "error" "В ascn.conf не указан путь для сохранения ipset!"
    exit 3
  else
    if [ "$GEOBLOCK_MODE" != "0" ]; then
      if [ -z "$GEOBLOCK_COUNTRIES" ]; then
        print_message "error" "В ascn.conf не указаны страны для геоблокировки!"
        exit 3
      else
        echo "$GEOBLOCK_COUNTRIES" | grep -Eq '^([A-Z]{2})( +[A-Z]{2} {0,})*$'
        local validation_result=$?
        if [ "$validation_result" -eq 0 ]; then
          local count=$(
            set -- $GEOBLOCK_COUNTRIES
            echo $#
          )
          if [ "$count" -gt 8 ]; then
            print_message "error" "Количество указанных стран для геоблокировки превышает 8"
            exit 4
          fi
        else
          print_message "error" "Список стран геоблокировки содержит недопустимые символы"
          exit 3
        fi
      fi
    fi
  fi

  if [ -z "$SAVE_ON_EXIT" ]; then
    SAVE_ON_EXIT=0
  fi
}

write_temp_config() {
  echo "ISP_INTERFACES=\"$ISP_INTERFACES\"" >"$CONFIG_FILE_TEMP"
  echo "PORTS=\"$PORTS\"" >>"$CONFIG_FILE_TEMP"
  echo "PORTS_FORWARDED=\"$PORTS_FORWARDED\"" >>"$CONFIG_FILE_TEMP"
  echo "ENABLE_HONEYPOT=\"$ENABLE_HONEYPOT\"" >>"$CONFIG_FILE_TEMP"
  echo "HONEYPOT_PORTS=\"$HONEYPOT_PORTS\"" >>"$CONFIG_FILE_TEMP"
  echo "HONEYPOT_BANTIME=\"$HONEYPOT_BANTIME\"" >>"$CONFIG_FILE_TEMP"
  echo "ENABLE_IPS_BAN=\"$ENABLE_IPS_BAN\"" >>"$CONFIG_FILE_TEMP"
  echo "RECENT_CONNECTIONS_TIME=$RECENT_CONNECTIONS_TIME" >>"$CONFIG_FILE_TEMP"
  echo "RECENT_CONNECTIONS_HITCOUNT=$RECENT_CONNECTIONS_HITCOUNT" >>"$CONFIG_FILE_TEMP"
  echo "RECENT_CONNECTIONS_LIMIT=$RECENT_CONNECTIONS_LIMIT" >>"$CONFIG_FILE_TEMP"
  echo "RECENT_CONNECTIONS_BANTIME=$RECENT_CONNECTIONS_BANTIME" >>"$CONFIG_FILE_TEMP"
  echo "DIFFERENT_IP_CANDIDATES_STORAGETIME=$DIFFERENT_IP_CANDIDATES_STORAGETIME" >>"$CONFIG_FILE_TEMP"
  echo "DIFFERENT_IP_THRESHOLD=$DIFFERENT_IP_THRESHOLD" >>"$CONFIG_FILE_TEMP"
  echo "SUBNETS_BANTIME=$SUBNETS_BANTIME" >>"$CONFIG_FILE_TEMP"
  echo "RULES_MASK=\"$RULES_MASK\"" >>"$CONFIG_FILE_TEMP"
  echo "IPSETS_DIRECTORY=\"$IPSETS_DIRECTORY\"" >>"$CONFIG_FILE_TEMP"
  echo "SAVE_IPSETS=$SAVE_IPSETS" >>"$CONFIG_FILE_TEMP"
  echo "SAVE_ON_EXIT=$SAVE_ON_EXIT" >>"$CONFIG_FILE_TEMP"
  echo "USE_CUSTOM_EXCLUDE_LIST=$USE_CUSTOM_EXCLUDE_LIST" >>"$CONFIG_FILE_TEMP"
  echo "CUSTOM_LISTS_BLOCK_MODE=\"$CUSTOM_LISTS_BLOCK_MODE\"" >>"$CONFIG_FILE_TEMP"
  echo "GEOBLOCK_MODE=\"$GEOBLOCK_MODE\"" >>"$CONFIG_FILE_TEMP"
  echo "GEOBLOCK_COUNTRIES=\"$GEOBLOCK_COUNTRIES\"" >>"$CONFIG_FILE_TEMP"
  echo "GEO_EXCLUDE_COUNTRIES=\"$GEO_EXCLUDE_COUNTRIES\"" >>"$CONFIG_FILE_TEMP"
  echo "READ_NDM_LOCKOUT_IPSETS=$READ_NDM_LOCKOUT_IPSETS" >>"$CONFIG_FILE_TEMP"
  echo "LOCKOUT_IPSET_BANTIME=$LOCKOUT_IPSET_BANTIME" >>"$CONFIG_FILE_TEMP"
}

destroy_temp_config() {
  IPSETS_DIRECTORY=""
  SAVE_IPSETS=0
  SAVE_ON_EXIT=0
  RULES_MASK="255.255.255.255"
  CUSTOM_LISTS_BLOCK_MODE=0
  USE_CUSTOM_EXCLUDE_LIST=0
  GEOBLOCK_MODE=0
  GEOBLOCK_COUNTRIES=""
  GEO_EXCLUDE_COUNTRIES=""
  READ_NDM_LOCKOUT_IPSETS=0
  LOCKOUT_IPSET_BANTIME=0
  HONEYPOT_BANTIME=0
  ENABLE_HONEYPOT=0
  ENABLE_IPS_BAN=1
  rm -f "$CONFIG_FILE_TEMP"
  source "$CONFIG_FILE"
}

config_is_reloading() {
  if [ -f "$ASCN_LOCK_FILE" ]; then
    return 0
  else
    return 1
  fi
}

reload_config() {
  if ! ascn_is_running; then
    print_message "error" "Antiscan не запущен"
    exit 1
  else
    if config_is_reloading; then
      print_message "error" "Процесс обновления конфигурации Antiscan уже запущен"
      exit 2
    elif geo_is_loading; then
      print_message "error" "Обновление конфигурации невозможно, пока идет загрузка списков подсетей стран"
      exit 2
    else
      create_lock_file

      local enable_ips_ban_old=$ENABLE_IPS_BAN
      local ascn_old_timeout=$RECENT_CONNECTIONS_BANTIME
      local ascn_candidates_old_timeout=$DIFFERENT_IP_CANDIDATES_STORAGETIME
      local ascn_subnets_old_timeout=$SUBNETS_BANTIME
      local custom_lists_block_mode_old="$CUSTOM_LISTS_BLOCK_MODE"
      local use_custom_exclude_list_old=$USE_CUSTOM_EXCLUDE_LIST
      local geoblock_mode_old="$GEOBLOCK_MODE"
      local geo_countries_old="$GEOBLOCK_COUNTRIES"
      local geo_exclude_countries_old="$GEO_EXCLUDE_COUNTRIES"
      local read_ndm_lockout_old="$READ_NDM_LOCKOUT_IPSETS"
      local ndm_lockout_timeout_old="$LOCKOUT_IPSET_BANTIME"
      local enable_honeypot_old="$ENABLE_HONEYPOT"
      local honeypot_ports_old="$HONEYPOT_PORTS"
      local honeypot_timeout_old="$HONEYPOT_BANTIME"
      local ipsets_dir_old="$IPSETS_DIRECTORY"

      remove_rules
      destroy_temp_config
      read_config
      write_temp_config
      update_cron

      if [ "$enable_ips_ban_old" == "1" ] && [ "$ENABLE_IPS_BAN" == "1" ]; then
        update_ipset_timeout "ascn_candidates" "$ascn_candidates_old_timeout" "$DIFFERENT_IP_CANDIDATES_STORAGETIME" "" 1
        update_ipset_timeout "ascn_ips" "$ascn_old_timeout" "$RECENT_CONNECTIONS_BANTIME" "" 1
        update_ipset_timeout "ascn_subnets" "$ascn_subnets_old_timeout" "$SUBNETS_BANTIME" "" 1
      else
        if [ "$enable_ips_ban_old" == "0" ] && [ "$ENABLE_IPS_BAN" == "1" ]; then
          create_ips_ban_ipsets
        elif [ "$enable_ips_ban_old" == "1" ] && [ "$ENABLE_IPS_BAN" == "0" ]; then
          export_ipsets 1
          destroy_ipsets 1
        fi
      fi

      reload_lockout_ipset "$read_ndm_lockout_old" "$READ_NDM_LOCKOUT_IPSETS" "$ndm_lockout_timeout_old" "$LOCKOUT_IPSET_BANTIME"
      reload_custom_ipset "$custom_lists_block_mode_old" "$CUSTOM_LISTS_BLOCK_MODE"
      reload_custom_exclude_ipset "$use_custom_exclude_list_old" "$USE_CUSTOM_EXCLUDE_LIST"

      reload_geo_ipset "$geoblock_mode_old" "$GEOBLOCK_MODE" "$geo_countries_old" "$GEOBLOCK_COUNTRIES"
      reload_geo_exclude_ipset "$geo_exclude_countries_old" "$GEO_EXCLUDE_COUNTRIES"

      reload_honeypot_ipset "$enable_honeypot_old" "$ENABLE_HONEYPOT" "$honeypot_timeout_old" "$HONEYPOT_BANTIME"

      show_no_protection_warning

      if [ -n "$IPSETS_DIRECTORY" ] && [ "$ipsets_dir_old" != "$IPSETS_DIRECTORY" ]; then
        msg_to_print="Перезапустите Antiscan, чтобы начать работу с новым каталогом хранения списков."
        printf "${YELLOW_COLOR}${msg_to_print}${NO_STYLE}\n"
        print_message "warning" "${msg_to_print}"
      fi

      add_rules
      remove_lock_file
    fi
  fi
}
