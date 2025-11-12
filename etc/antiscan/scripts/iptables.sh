load_kernel_modules() {
  if [ -z "$(lsmod 2>/dev/null | grep "xt_recent ")" ]; then
    local xtrecent_mod_path=$(find "/lib/modules/$KERNEL" -name "xt_recent.ko*")
    if [ -n "$xtrecent_mod_path" ]; then
      insmod "$xtrecent_mod_path" >/dev/null 2>&1
      print_message "notice" "xt_recent.ko загружен"
    else
      print_message "error" "Не удалось найти модуль ядра xt_recent.ko"
      exit 1
    fi
  fi

  if [ -z "$(lsmod 2>/dev/null | grep "xt_multiport ")" ]; then
    local multiport_mod_path=$(find "/lib/modules/$KERNEL" -name "xt_multiport.ko*")
    if [ -n "$multiport_mod_path" ]; then
      insmod "$multiport_mod_path" >/dev/null 2>&1
      print_message "notice" "xt_multiport.ko загружен"
    else
      print_message "error" "Не удалось найти модуль ядра xt_multiport.ko"
      exit 1
    fi
  fi
}

_iptables() {
  local ACTION=$1
  shift 1
  local RULE="$@"

  iptables -w -C $RULE 2>/dev/null
  local exists=$?
  local chain_exists=0

  if echo "$RULE" | grep -q '\bANTISCAN\b'; then
    iptables -L ANTISCAN -w -t filter -n >/dev/null 2>&1
    chain_exists=$?
  elif echo "$RULE" | grep -q '\bANTISCAN_HONEYPOT\b'; then
    iptables -L ANTISCAN_HONEYPOT -w -t filter -n >/dev/null 2>&1
    chain_exists=$?
  else
    chain_exists=0
  fi

  if [ "$ACTION" == "-I" ] || [ "$ACTION" == "-A" ]; then
    if [ $exists -ne 0 ] && [ $chain_exists -eq 0 ]; then
      iptables $ACTION $RULE
    fi
  elif [ "$ACTION" == "-D" ] && [ $exists -eq 0 ] && [ $chain_exists -eq 0 ]; then
    iptables $ACTION $RULE
  fi
}

add_rules() {
  if ! iptables -L ANTISCAN -w -t filter -n >/dev/null 2>&1; then
    iptables -N ANTISCAN -w -t filter

    if [ -n "$(ipset -q -n list ascn_custom_exclude)" ]; then
      _iptables -A ANTISCAN -w -t filter -m set --match-set ascn_custom_exclude src -j RETURN
    fi
    if [ -n "$(ipset -q -n list ascn_geo_exclude)" ]; then
      _iptables -A ANTISCAN -w -t filter -m set --match-set ascn_geo_exclude src -j RETURN
    fi

    if [ -n "$(ipset -q -n list ascn_custom_blacklist)" ]; then
      _iptables -A ANTISCAN -w -t filter -m set --match-set ascn_custom_blacklist src -j DROP
    elif [ -n "$(ipset -q -n list ascn_custom_whitelist)" ]; then
      _iptables -A ANTISCAN -w -t filter -m set ! --match-set ascn_custom_whitelist src -j DROP
    fi

    if [ -n "$(ipset -q -n list ascn_geo_blacklist)" ]; then
      _iptables -A ANTISCAN -w -t filter -m set --match-set ascn_geo_blacklist src -j DROP
    elif [ -n "$(ipset -q -n list ascn_geo_whitelist)" ]; then
      _iptables -A ANTISCAN -w -t filter -m set ! --match-set ascn_geo_whitelist src -j DROP
    fi

    if [ -n "$(ipset -q -n list ascn_ndm_lockout)" ]; then
      _iptables -A ANTISCAN -w -t filter -m set --match-set ascn_ndm_lockout src -j DROP
    fi

    if [ "$ENABLE_HONEYPOT" == "1" ] && [ -n "$(ipset -q -n list ascn_honeypot)" ]; then
      _iptables -A ANTISCAN -w -t filter -m set --match-set ascn_honeypot src -j DROP
    fi

    if [ "$ENABLE_IPS_BAN" == "1" ]; then
      _iptables -A ANTISCAN -w -t filter -m set --match-set ascn_subnets src -j DROP
      _iptables -A ANTISCAN -w -t filter -m set --match-set ascn_ips src -j DROP
      _iptables -A ANTISCAN -w -t filter -j SET --add-set ascn_candidates src
      _iptables -A ANTISCAN -w -t filter -m connlimit --connlimit-above $RECENT_CONNECTIONS_LIMIT --connlimit-mask $RULES_MASK -j SET --add-set ascn_ips src
      _iptables -A ANTISCAN -w -t filter -m conntrack --ctstate NEW -m recent --update --seconds $RECENT_CONNECTIONS_TIME --hitcount $RECENT_CONNECTIONS_HITCOUNT --name scanners --mask $RULES_MASK -j SET --add-set ascn_ips src
      _iptables -A ANTISCAN -w -t filter -m conntrack --ctstate NEW -m recent --set --name scanners --mask $RULES_MASK
    fi

    _iptables -A ANTISCAN -w -t filter -j RETURN
  fi

  if iptables -L ANTISCAN -w -t filter -n >/dev/null 2>&1; then
    for INTERFACE in $ISP_INTERFACES; do
      if [ -n "$PORTS" ]; then
        _iptables -I INPUT -w -t filter -i $INTERFACE -p tcp -m multiport --dports $PORTS -j ANTISCAN
      fi
      if [ -n "$PORTS_FORWARDED" ]; then
        _iptables -I FORWARD -w -t filter -i $INTERFACE -p tcp -m multiport --dports $PORTS_FORWARDED -j ANTISCAN
      fi
    done
  fi

  if [ "$ENABLE_HONEYPOT" == "1" ]; then
    if ! iptables -L ANTISCAN_HONEYPOT -w -t filter -n >/dev/null 2>&1; then
      iptables -N ANTISCAN_HONEYPOT -w -t filter

      if [ -n "$(ipset -q -n list ascn_custom_exclude)" ]; then
        _iptables -A ANTISCAN_HONEYPOT -w -t filter -m set --match-set ascn_custom_exclude src -j RETURN
      fi
      if [ -n "$(ipset -q -n list ascn_geo_exclude)" ]; then
        _iptables -A ANTISCAN_HONEYPOT -w -t filter -m set --match-set ascn_geo_exclude src -j RETURN
      fi

      if [ -n "$(ipset -q -n list ascn_custom_blacklist)" ]; then
        _iptables -A ANTISCAN_HONEYPOT -w -t filter -m set --match-set ascn_custom_blacklist src -j DROP
      elif [ -n "$(ipset -q -n list ascn_custom_whitelist)" ]; then
        _iptables -A ANTISCAN_HONEYPOT -w -t filter -m set ! --match-set ascn_custom_whitelist src -j DROP
      fi

      if [ -n "$(ipset -q -n list ascn_geo_blacklist)" ]; then
        _iptables -A ANTISCAN_HONEYPOT -w -t filter -m set --match-set ascn_geo_blacklist src -j DROP
      elif [ -n "$(ipset -q -n list ascn_geo_whitelist)" ]; then
        _iptables -A ANTISCAN_HONEYPOT -w -t filter -m set ! --match-set ascn_geo_whitelist src -j DROP
      fi

      if [ -n "$(ipset -q -n list ascn_ndm_lockout)" ]; then
        _iptables -A ANTISCAN_HONEYPOT -w -t filter -m set --match-set ascn_ndm_lockout src -j DROP
      fi

      if [ -n "$(ipset -q -n list ascn_honeypot)" ]; then
        _iptables -A ANTISCAN_HONEYPOT -w -t filter -m set --match-set ascn_honeypot src -j DROP
      fi

      if [ "$ENABLE_IPS_BAN" == "1" ]; then
        _iptables -A ANTISCAN_HONEYPOT -w -t filter -m set --match-set ascn_subnets src -j DROP
        _iptables -A ANTISCAN_HONEYPOT -w -t filter -m set --match-set ascn_ips src -j DROP
      fi

      if [ -n "$(ipset -q -n list ascn_honeypot)" ]; then
        _iptables -A ANTISCAN_HONEYPOT -w -t filter -j SET --add-set ascn_honeypot src
      fi
    fi

    if iptables -L ANTISCAN_HONEYPOT -w -t filter -n >/dev/null 2>&1; then
      for INTERFACE in $ISP_INTERFACES; do
        _iptables -I INPUT -w -t filter -i $INTERFACE -p tcp -m multiport --dports $HONEYPOT_PORTS -j ANTISCAN_HONEYPOT
      done
    fi
  fi
}

remove_rules() {
  if iptables -L ANTISCAN -w -t filter -n >/dev/null 2>&1; then
    for INTERFACE in $ISP_INTERFACES; do
      if [ -n "$PORTS" ]; then
        _iptables -D INPUT -w -t filter -i $INTERFACE -p tcp -m multiport --dports $PORTS -j ANTISCAN
      fi
      if [ -n "$PORTS_FORWARDED" ]; then
        _iptables -D FORWARD -w -t filter -i $INTERFACE -p tcp -m multiport --dports $PORTS_FORWARDED -j ANTISCAN
      fi
    done
    iptables -F ANTISCAN -w -t filter
    iptables -X ANTISCAN -w -t filter
  fi

  if [ "$ENABLE_HONEYPOT" == "1" ]; then
    if iptables -L ANTISCAN_HONEYPOT -w -t filter -n >/dev/null 2>&1; then
      for INTERFACE in $ISP_INTERFACES; do
        _iptables -D INPUT -w -t filter -i $INTERFACE -p tcp -m multiport --dports $HONEYPOT_PORTS -j ANTISCAN_HONEYPOT
      done
      iptables -F ANTISCAN_HONEYPOT -w -t filter
      iptables -X ANTISCAN_HONEYPOT -w -t filter
    fi
  fi
}

update_iptables() {
  if ! ascn_is_running; then
    exit 1
  else
    local wait_timeout=15
    local log_message="Идет обновление конфигурации Antiscan, пробуем восстановить правила за 15 секунд... "
    while config_is_reloading && [ "$wait_timeout" -gt 0 ]; do
      if [ $wait_timeout -eq 15 ]; then echo -n "$log_message" >&2; fi
      wait_timeout=$((wait_timeout - 1))
      sleep 1
    done
    if config_is_reloading; then
      log_message="${log_message} неудачно"
      print_message "warning" "${log_message}" 1
      exit 2
    else
      if [ $wait_timeout -ne 15 ]; then
        log_message="${log_message} успешно"
        print_message "warning" "${log_message}" 1
      fi
      add_rules
    fi
  fi
}
