ASCN_GEO_LOCK_FILE="/tmp/ascn_geo.lock"
ASCN_GEO_LOAD_ERROR_FILE="/tmp/ascn_geo_load_error"

download_geo_subnets() {
  local load_failed=0
  local unavailable_countries=""
  local geo_directory="$1"
  local is_geo_reloading="$2"
  local countries="$3"
  local all_countries_list=""

  local SUBNETS_MIRROR="https://antiscan.ru/data/geo"

  if [ "$GEOBLOCK_MODE" == "blacklist" ] || [ "$GEOBLOCK_MODE" == "whitelist" ]; then
    all_countries_list="${GEOBLOCK_COUNTRIES}"
  fi
  if [ -n "$GEO_EXCLUDE_COUNTRIES" ]; then
    [ -z "$all_countries_list" ] && all_countries_list="${GEO_EXCLUDE_COUNTRIES}" || all_countries_list="${all_countries_list} ${GEO_EXCLUDE_COUNTRIES}"
  fi

  if [ ! -d "$geo_directory" ]; then
    unavailable_countries="${countries}"
    if ! mkdir "$geo_directory"; then
      print_message "error" "Не удалось создать директорию ${geo_directory}"
      return 2
    fi
  else
    local exclude_countries=""
    for country in $all_countries_list; do
      exclude_countries="${exclude_countries}! -name ${country}.txt "
    done
    for country_na in $countries; do
      local subnets_file="$geo_directory/$country_na.txt"
      if [ ! -s "$subnets_file" ]; then
        unavailable_countries="${unavailable_countries} ${country_na}"
      fi
    done
    find "$geo_directory" -maxdepth 1 $exclude_countries -type f -delete
  fi

  [ "$is_geo_reloading" == "1" ] && unavailable_countries="${countries}"

  if [ -n "$unavailable_countries" ]; then
    local curl_temp_file_path="/tmp/curl_geo_response.txt"
    for country in $unavailable_countries; do
      local geo_subnets_file="$geo_directory/$country.txt"
      [ -f "$geo_subnets_file" ] && rm "$geo_subnets_file"
      printf "Загрузка списка подсетей для страны ${BOLD_TEXT}${country}${NO_STYLE}... "
      local log_message="Загрузка списка подсетей для страны ${country}"
      local load_result=0
      load_failed=0
      curl --connect-timeout 30 --retry 5 --retry-delay 10 -fsS "https://stat.ripe.net/data/country-resource-list/data.json?resource=${country}&v4_format=prefix" -o "$curl_temp_file_path" 2>/tmp/ascn_curl1_error
      local curl1_result=$?
      local curl2_result=254
      local curl1_error_text=""
      local curl2_error_text=""
      if [ "$curl1_result" -ne 0 ]; then
        print_message "warning" "${log_message} завершилась неудачно" 0
        printf "${RED_COLOR}неудачно${NO_STYLE}\n"
        if [ -s "/tmp/ascn_curl1_error" ]; then
          curl1_error_text="$(cat /tmp/ascn_curl1_error)"
          print_message "error" "${curl1_error_text}" 1
          printf "${RED_COLOR}${curl1_error_text}${NO_STYLE}\n"
        fi
        printf "${YELLOW_COLOR}Пробуем загрузить ${NO_STYLE}${BOLD_TEXT}${country}${NO_STYLE}${YELLOW_COLOR} с зеркала...${NO_STYLE} "
        print_message "warning" "Пробуем загрузить ${country} с зеркала..." 0
        log_message="Повторная загрузка списка подсетей для страны ${country}"
        curl --connect-timeout 30 --retry 5 --retry-delay 10 -fsS "${SUBNETS_MIRROR}/${country}.json" -o "$curl_temp_file_path" 2>/tmp/ascn_curl2_error
        curl2_result=$?
        if [ "$curl2_result" -ne 0 ]; then
          print_message "warning" "${log_message} завершилась неудачно" 0
          printf "${RED_COLOR}неудачно${NO_STYLE}\n"
          if [ -s "/tmp/ascn_curl2_error" ]; then
            curl2_error_text="$(cat /tmp/ascn_curl2_error)"
            print_message "error" "${curl2_error_text}" 1
            printf "${RED_COLOR}${curl2_error_text}${NO_STYLE}\n\n"
          fi
        fi
      fi
      [ -f "/tmp/ascn_curl1_error" ] && rm -f "/tmp/ascn_curl1_error"
      [ -f "/tmp/ascn_curl2_error" ] && rm -f "/tmp/ascn_curl2_error"
      if [ "$curl1_result" -eq 0 ] || [ "$curl2_result" -eq 0 ]; then
        jq -r '.data.resources.ipv4[]' "$curl_temp_file_path" 2>"/tmp/ascn_jq_error" >"$geo_subnets_file"
        local parse_result=$?
        if [ "$parse_result" -ne 0 ]; then
          print_message "warning" "${log_message} завершилась неудачно" 0
          printf "${RED_COLOR}неудачно${NO_STYLE}\n"
          if [ -s "/tmp/ascn_jq_error" ]; then
            jq_error_text="$(cat /tmp/ascn_jq_error)"
            print_message "error" "${jq_error_text}" 1
            printf "${RED_COLOR}${jq_error_text}${NO_STYLE}\n\n"
          fi
          load_result=1
          load_failed=1
        else
          load_result=0
        fi
        [ -f "/tmp/ascn_jq_error" ] && rm -f "/tmp/ascn_jq_error"
      else
        load_result=1
        load_failed=1
      fi

      if [ "$load_result" -eq 0 ]; then
        if [ -s "$geo_subnets_file" ]; then
          printf "${GREEN_COLOR}успешно${NO_STYLE}\n"
          print_message "notice" "${log_message} выполнена успешно" 1
        else
          printf "${RED_COLOR}неудачно${NO_STYLE}\n"
          print_message "warning" "${log_message} завершилась неудачно" 0
          print_message "warning" "Файл ${country}.txt не содержит подсетей" 1
        fi
      fi
    done
    [ -f "$curl_temp_file_path" ] && rm "$curl_temp_file_path"

    if [ "$load_failed" -eq 1 ]; then
      create_geo_error_task
      return 1
    else
      remove_geo_error_task
      return 0
    fi
  fi
}

load_geo_ipset() {
  local geo_ipset_type="$1"
  local is_geo_reloading="$2"
  local is_trying_load_geo="$3"
  local no_lock_file="$4"
  local no_download="$5"
  local geo_directory="$IPSETS_DIRECTORY/geo"
  local temp_geo_ipset_path="/tmp/temp_geo_ipset.txt"
  local load_country_failed=0
  local countries=""
  local countries_string=""

  if [ "$geo_ipset_type" == "exclude" ]; then
    countries="$GEO_EXCLUDE_COUNTRIES"
    countries_string="стран-исключений"
  else
    countries="$GEOBLOCK_COUNTRIES"
    countries_string="стран геоблокировки"
  fi

  if [ -z "$no_lock_file" ] && geo_is_loading; then
    print_message "error" "Обновление списков подсетей стран уже запущено"
  else
    [ -z "$no_lock_file" ] && create_geo_lock_file

    if [ -z "$no_download" ]; then
      download_geo_subnets "$geo_directory" "$is_geo_reloading" "$countries"
      local download_exitcode=$?
      if [ "$download_exitcode" -eq 1 ]; then
        load_country_failed=1
      elif [ "$download_exitcode" -eq 2 ]; then
        load_country_failed=2
      fi
    fi

    if [ "$is_trying_load_geo" == "1" ] && [ "$load_country_failed" -eq 1 ]; then
      :
    else
      if [ -d "$geo_directory" ]; then
        if [[ "$is_geo_reloading" != "1" && "$is_trying_load_geo" != "1" ]] || [ -z "$(ipset -q -n list ascn_geo_$geo_ipset_type)" ]; then
          echo "create ascn_geo_$geo_ipset_type hash:net family inet hashsize 1024 maxelem 1000000" >"$temp_geo_ipset_path"
        fi
        for country in $countries; do
          local subnets_file="$geo_directory/$country.txt"
          if [ -s "$subnets_file" ]; then
            sed "s/^/add ascn_geo_$geo_ipset_type /" "$subnets_file" >>"$temp_geo_ipset_path"
          fi
        done
      fi

      if [ -f "$temp_geo_ipset_path" ]; then
        local geo_subnets_count="$(grep -c '^' "$temp_geo_ipset_path")"
        if [ "$geo_subnets_count" -gt 1 ]; then
          if [ "$is_geo_reloading" == "1" ] || [ "$is_trying_load_geo" == "1" ]; then
            [ -n "$(ipset -q -n list ascn_geo_$geo_ipset_type)" ] && ipset flush ascn_geo_$geo_ipset_type
          fi

          if ! ipset -! restore <"$temp_geo_ipset_path"; then
            print_message "error" "Не удалось импортировать список ascn_geo_$geo_ipset_type!"
          fi
        else
          print_message "error" "Загруженный список подсетей ${countries_string} пуст"
        fi
        rm "$temp_geo_ipset_path"
      else
        if [ "$load_country_failed" -eq 2 ]; then
          print_message "error" "Загрузка списка подсетей ${countries_string} завершилась неудачно"
        else
          print_message "error" "Файл со списком подсетей ${countries_string} не найден"
        fi
      fi
    fi
    [ -z "$no_lock_file" ] && remove_geo_lock_file
  fi
}

create_geo_error_task() {
  if [ ! -f "$ASCN_GEO_LOAD_ERROR_FILE" ]; then
    echo "1" >"$ASCN_GEO_LOAD_ERROR_FILE"
    if [ -s "$CRONTAB_FILE" ]; then
      if ! grep -q 'S99ascn retry_load_geo' "$CRONTAB_FILE"; then
        print_message "notice" "Создаем задачу для повторного обновления списка подсетей..."
        sed -n -i '\:S99ascn:p; $a0 */1 * * * /opt/etc/init.d/S99ascn retry_load_geo &' "$CRONTAB_FILE"
        update_cron
      fi
    else
      print_message "error" "Не удалось создать задачу для повторного обновления списка подсетей"
    fi
  fi
}

remove_geo_error_task() {
  if [ -f "$ASCN_GEO_LOAD_ERROR_FILE" ]; then
    rm "$ASCN_GEO_LOAD_ERROR_FILE"
  fi
  if [ -s "$CRONTAB_FILE" ]; then
    if grep -q 'S99ascn retry_load_geo' "$CRONTAB_FILE"; then
      print_message "notice" "Удаляем задачу повторного обновления списка подсетей..."
      sed -i '/S99ascn retry_load_geo/d' "$CRONTAB_FILE"
      update_cron
    fi
  fi
}

geo_is_loading() {
  if [ -f "$ASCN_GEO_LOCK_FILE" ]; then
    return 0
  else
    return 1
  fi
}

create_geo_lock_file() {
  echo "1" >"$ASCN_GEO_LOCK_FILE"
}

remove_geo_lock_file() {
  if geo_is_loading; then
    rm "$ASCN_GEO_LOCK_FILE"
  fi
}

reload_geo_ipset() {
  local old_geo_mode="$1"
  local new_geo_mode="$2"
  local old_countries_list="$3"
  local new_countries_list="$4"

  if [ "$old_geo_mode" != "$new_geo_mode" ] || [ "$old_countries_list" != "$new_countries_list" ]; then
    if [ "$old_geo_mode" != "0" ]; then
      [ -n "$(ipset -q -n list ascn_geo_$old_geo_mode)" ] && ipset destroy ascn_geo_$old_geo_mode
    fi
    if [ "$new_geo_mode" != "0" ] && [[ "$new_geo_mode" == "blacklist" || "$new_geo_mode" == "whitelist" ]]; then
      load_geo_ipset "$new_geo_mode" 0
    fi
  fi
}

reload_geo_exclude_ipset() {
  local old_exclude_countries_list="$1"
  local new_exclude_countries_list="$2"
  if [ "$old_exclude_countries_list" != "$new_exclude_countries_list" ]; then
    if [ -n "$old_exclude_countries_list" ]; then
      [ -n "$(ipset -q -n list ascn_geo_exclude)" ] && ipset destroy ascn_geo_exclude
    fi
    if [ -n "$new_exclude_countries_list" ]; then
      load_geo_ipset "exclude" 0
    fi
  fi
}

force_reload_geo_ipsets() {
  if geo_is_loading; then
    print_message "error" "Обновление списков подсетей стран уже запущено"
    return 1
  else
    local geo_directory="$IPSETS_DIRECTORY/geo"
    local geoblock_download_failed=1
    local geoexclude_download_failed=1
    create_geo_lock_file
    if [ "$GEOBLOCK_MODE" == "blacklist" ] || [ "$GEOBLOCK_MODE" == "whitelist" ]; then
      download_geo_subnets "$geo_directory" 1 "$GEOBLOCK_COUNTRIES" && geoblock_download_failed=0
    fi
    if [ -n "$GEO_EXCLUDE_COUNTRIES" ]; then
      download_geo_subnets "$geo_directory" 1 "$GEO_EXCLUDE_COUNTRIES" && geoexclude_download_failed=0
    fi
    if [ "$geoblock_download_failed" -eq 0 ] || [ "$geoexclude_download_failed" -eq 0 ]; then
      remove_rules
      [ "$geoblock_download_failed" -eq 0 ] && load_geo_ipset "$GEOBLOCK_MODE" 0 1 1 1
      [ "$geoexclude_download_failed" -eq 0 ] && load_geo_ipset "exclude" 0 1 1 1
      add_rules
      remove_geo_lock_file
      return 0
    else
      remove_geo_lock_file
      return 1
    fi
  fi
}

retry_load_geo() {
  if ascn_is_running; then
    if config_is_reloading; then
      print_message "error" "Загрузка подсетей стран недоступна во время обновления конфигурации Antiscan"
      exit 2
    else
      if [ "$GEOBLOCK_MODE" == "blacklist" ] || [ "$GEOBLOCK_MODE" == "whitelist" ] || [ -n "$GEO_EXCLUDE_COUNTRIES" ]; then
        if [ -f "$ASCN_GEO_LOAD_ERROR_FILE" ]; then
          force_reload_geo_ipsets && remove_geo_error_task
        else
          remove_geo_error_task
        fi
      else
        remove_geo_error_task
      fi
    fi
  else
    exit 1
  fi
}
