create_ipsets() {
    create_ips_ban_ipsets

    if [ "$READ_NDM_LOCKOUT_IPSETS" == "1" ] && [ -z "$(ipset -q -n list ascn_ndm_lockout)" ]; then
        add_ipset "ascn_ndm_lockout" "hash:ip" $LOCKOUT_IPSET_BANTIME
    fi

    if [ "$ENABLE_HONEYPOT" == "1" ] && [ -z "$(ipset -q -n list ascn_honeypot)" ]; then
        add_ipset "ascn_honeypot" "hash:ip" $HONEYPOT_BANTIME
    fi

    if [ "$CUSTOM_LISTS_BLOCK_MODE" == "blacklist" ] || [ "$CUSTOM_LISTS_BLOCK_MODE" == "whitelist" ]; then
        local ipset_custom_name="ascn_custom_${CUSTOM_LISTS_BLOCK_MODE}"
        if [ -z "$(ipset -q -n list $ipset_custom_name)" ]; then
            load_custom_ipset "$ipset_custom_name"
        fi
    fi

    if [ "$USE_CUSTOM_EXCLUDE_LIST" == "1" ] && [ -z "$(ipset -q -n list ascn_custom_exclude)" ]; then
        load_custom_ipset "ascn_custom_exclude"
    fi

    if [ "$GEOBLOCK_MODE" == "blacklist" ] || [ "$GEOBLOCK_MODE" == "whitelist" ]; then
        local ipset_geo_name="ascn_geo_${GEOBLOCK_MODE}"
        if [ -z "$(ipset -q -n list $ipset_geo_name)" ]; then
            load_geo_ipset "$GEOBLOCK_MODE" 0
        fi
    fi

    if [ -n "$GEO_EXCLUDE_COUNTRIES" ]; then
        if [ -z "$(ipset -q -n list ascn_geo_exclude)" ]; then
            load_geo_ipset "exclude" 0
        fi
    fi
}

create_ips_ban_ipsets() {
    if [ "$ENABLE_IPS_BAN" == "1" ]; then
        if [ -z "$(ipset -q -n list ascn_candidates)" ]; then
            add_ipset "ascn_candidates" "hash:ip" $DIFFERENT_IP_CANDIDATES_STORAGETIME
        fi

        if [ -z "$(ipset -q -n list ascn_ips)" ]; then
            add_ipset "ascn_ips" "hash:ip" $RECENT_CONNECTIONS_BANTIME
        fi

        if [ -z "$(ipset -q -n list ascn_subnets)" ]; then
            add_ipset "ascn_subnets" "hash:net" $SUBNETS_BANTIME
        fi
    fi
}

add_ipset() {
    local ipset_name="$1"
    local ipset_type="$2"
    local ipset_timeout="$3"
    local ipset_timeout_string=""
    local ipset_file="$IPSETS_DIRECTORY/ipset_$ipset_name.txt"
    local should_add_ipset=1

    case $ipset_name in
    "ascn_candidates")
        ipset_timeout_string=$([ "$DIFFERENT_IP_CANDIDATES_STORAGETIME" -ne 0 ] && echo "timeout "$DIFFERENT_IP_CANDIDATES_STORAGETIME"")
        ;;
    "ascn_ips")
        ipset_timeout_string=$([ "$RECENT_CONNECTIONS_BANTIME" -ne 0 ] && echo "timeout "$RECENT_CONNECTIONS_BANTIME"")
        ;;
    "ascn_subnets")
        ipset_timeout_string=$([ "$SUBNETS_BANTIME" -ne 0 ] && echo "timeout "$SUBNETS_BANTIME"")
        ;;
    "ascn_ndm_lockout")
        ipset_timeout_string=$([ "$LOCKOUT_IPSET_BANTIME" -ne 0 ] && echo "timeout "$LOCKOUT_IPSET_BANTIME"")
        ;;
    "ascn_honeypot")
        ipset_timeout_string=$([ "$HONEYPOT_BANTIME" -ne 0 ] && echo "timeout "$HONEYPOT_BANTIME"")
        ;;
    esac

    if [ "$SAVE_IPSETS" == "1" ] && [ -s "$ipset_file" ]; then
        local ipset_old_timeout=$(grep -oP '^create.*timeout\s+\K\d+$' "$ipset_file")
        if [ -z "$ipset_old_timeout" ]; then
            ipset_old_timeout=0
        fi
        update_ipset_timeout "$ipset_name" "$ipset_old_timeout" "$ipset_timeout" "$ipset_file" 0
        if restore_ipset_from_file "$ipset_name" "$ipset_file"; then
            should_add_ipset=0
        fi
    fi

    if [ "$should_add_ipset" -eq 1 ]; then
        ipset create $ipset_name $ipset_type $ipset_timeout_string
    fi
}

destroy_ipsets() {
    local ipsets_list=""
    if [ -z "$1" ]; then
        ipsets_list="ascn_candidates ascn_ips ascn_subnets ascn_custom_exclude ascn_custom_blacklist ascn_custom_whitelist ascn_geo_blacklist ascn_geo_whitelist ascn_geo_exclude ascn_ndm_lockout ascn_honeypot"
    else
        ipsets_list="ascn_candidates ascn_ips ascn_subnets"
    fi
    for set in $ipsets_list; do
        if [ -n "$(ipset -q -n list $set)" ]; then
            ipset destroy $set
        fi
    done
}

restore_ipset_from_file() {
    if ! ipset restore <"$2"; then
        print_message "error" "Не удалось импортировать ipset $1!"
        return 1
    else
        return 0
    fi
}

load_custom_ipset() {
    local custom_ipset_tempfile="/tmp/ipset_custom.txt"
    local custom_ipset_filename="$ANTISCAN_DIR/$1.txt"
    if [ -f "$custom_ipset_filename" ]; then
        local custom_file_size="$(ls -l "$custom_ipset_filename" | awk '{print $5}')"
        if [ "$custom_file_size" -gt 4 ]; then
            echo "create $1 hash:net family inet hashsize 1024 maxelem 65536" >"$custom_ipset_tempfile"
            sed "s/^/add $1 /" "$custom_ipset_filename" >>"$custom_ipset_tempfile"
            if ! ipset -! restore <"$custom_ipset_tempfile"; then
                print_message "error" "Не удалось импортировать список $1!"
            fi
            rm "$custom_ipset_tempfile"
        else
            print_message "error" "В файле $1 отсутствуют IP-адреса."
            print_message "error" "Добавьте их и перезапустите Antiscan."
        fi
    else
        echo >"$custom_ipset_filename"
        print_message "warning" "Файл $1 отсутствовал и был создан автоматически." 1
        print_message "error" "Добавьте в него IP-адреса и перезапустите Antiscan."
    fi
}

export_ipsets() {
    if [ "$SAVE_IPSETS" == "1" ]; then
        if ascn_is_running; then
            if config_is_reloading && [ -z "$1" ]; then
                print_message "error" "Экспорт ipset в файл недоступен во время обновления конфигурации Antiscan"
                return 2
            else
                local ipsets_list=""
                [ -z "$1" ] && ipsets_list="ascn_candidates ascn_ips ascn_subnets ascn_ndm_lockout ascn_honeypot" || ipsets_list="ascn_candidates ascn_ips ascn_subnets"
                for set_name in $ipsets_list; do
                    local ipset_filename="$IPSETS_DIRECTORY/ipset_$set_name.txt"
                    local banned_count="$(ipset -q list $set_name | tail -n +8 | grep -c '^')"
                    if [ "$banned_count" -ne 0 ]; then
                        if ! ipset save "$set_name" >"$ipset_filename"; then
                            print_message "error" "Не удалось экспортировать ipset $set_name!"
                        fi
                    fi
                done
            fi
        else
            return 1
        fi
    fi
}

update_ipset_timeout() {
    local set_name="$1"
    local old_timeout="$2"
    local new_timeout="$3"
    local ipset_file="$4"
    local is_reloading="$5"

    if [ "$old_timeout" -ne "$new_timeout" ]; then

        if [ "$is_reloading" -eq 1 ]; then
            ipset_file="/tmp/${set_name}.txt"
            ipset save "$set_name" >"$ipset_file"
        fi

        if [ "$new_timeout" -eq 0 ]; then
            sed -i "s/ timeout [0-9]\+//" "$ipset_file" && print_message "notice" "Для списка $set_name удалено время хранения записей"
        else
            if [ $old_timeout -eq 0 ]; then
                sed -i "s/maxelem 65536\$/maxelem 65536 timeout $new_timeout/" "$ipset_file" && print_message "notice" "Для списка $set_name установлено время хранения записей $new_timeout"
            else
                sed -i "s/ timeout [0-9]\+/ timeout $new_timeout/" "$ipset_file" && print_message "notice" "Для списка $set_name обновлено время хранения записей. Было $old_timeout, стало $new_timeout"
            fi
        fi

        if [ "$is_reloading" -eq 1 ]; then
            ipset destroy "$set_name"
            restore_ipset_from_file "$set_name" "$ipset_file"
            rm "$ipset_file"
        fi
    fi
}

reload_custom_ipset() {
    local old_custom_mode="$1"
    local new_custom_mode="$2"
    if [ "$old_custom_mode" != "$new_custom_mode" ]; then
        if [ "$old_custom_mode" != "0" ]; then
            [ -n "$(ipset -q -n list ascn_custom_$old_custom_mode)" ] && ipset destroy ascn_custom_$old_custom_mode
        fi
        if [ "$new_custom_mode" == "blacklist" ] || [ "$new_custom_mode" == "whitelist" ]; then
            local new_custom_ipset_name="ascn_custom_$new_custom_mode"
            load_custom_ipset "$new_custom_ipset_name"
        fi
    fi
}

reload_custom_exclude_ipset() {
    local old_exclude_status="$1"
    local new_exclude_status="$2"
    if [ "$old_exclude_status" != "$new_exclude_status" ]; then
        if [ "$old_exclude_status" != "0" ]; then
            [ -n "$(ipset -q -n list ascn_custom_exclude)" ] && ipset destroy ascn_custom_exclude
        fi
        if [ "$new_exclude_status" != "0" ]; then
            load_custom_ipset "ascn_custom_exclude"
        fi
    fi
}

reload_lockout_ipset() {
    local old_lockout_state="$1"
    local new_lockout_state="$2"
    local old_lockout_timeout="$3"
    local new_lockout_timeout="$4"

    if [ "$old_lockout_state" != "$new_lockout_state" ] || [ "$old_lockout_timeout" != "$new_lockout_timeout" ]; then
        if [ "$old_lockout_state" != "0" ]; then
            [ -n "$(ipset -q -n list ascn_ndm_lockout)" ] && ipset destroy ascn_ndm_lockout
        fi
        if [ "$new_lockout_state" != "0" ]; then
            add_ipset "ascn_ndm_lockout" "hash:ip" $LOCKOUT_IPSET_BANTIME
        fi
    fi
}

reload_honeypot_ipset() {
    local old_hp_state="$1"
    local new_hp_state="$2"
    local old_hp_timeout="$3"
    local new_hp_timeout="$4"

    if [ "$old_hp_state" != "$new_hp_state" ] || [ "$old_hp_timeout" != "$new_hp_timeout" ]; then
        if [ "$old_hp_state" != "0" ]; then
            [ -n "$(ipset -q -n list ascn_honeypot)" ] && ipset destroy ascn_honeypot
        fi
        if [ "$new_hp_state" != "0" ]; then
            add_ipset "ascn_honeypot" "hash:ip" $HONEYPOT_BANTIME
        fi
    fi
}

flush_ipsets() {
    case "$1" in
    "candidates" | "ips" | "subnets" | "custom_whitelist" | "custom_blacklist" | "custom_exclude" | "geo" | "ndm_lockout" | "honeypot" | "")
        if ascn_is_running; then
            if config_is_reloading; then
                print_message "error" "Очистка списков недоступна во время обновления конфигурации Antiscan"
            elif geo_is_loading; then
                print_message "error" "Очистка списков недоступна во время загрузки подсетей стран"
            else
                local ipset_to_clear="$1"
                local question_text=""
                if [ -z "$ipset_to_clear" ]; then
                    ipset_to_clear="candidates ips subnets geo_whitelist geo_blacklist ndm_lockout honeypot"
                    question_text="Очистить все списки адресов? (Y/N): "
                else
                    ipset_readable_name=""
                    [ "$ipset_to_clear" == "candidates" ] && ipset_readable_name="список адресов-кандидатов на блокировку"
                    [ "$ipset_to_clear" == "ips" ] && ipset_readable_name="список заблокированных адресов"
                    [ "$ipset_to_clear" == "subnets" ] && ipset_readable_name="список заблокированных подсетей"
                    [ "$ipset_to_clear" == "custom_whitelist" ] && ipset_readable_name="пользовательский белый список адресов"
                    [ "$ipset_to_clear" == "custom_blacklist" ] && ipset_readable_name="пользовательский черный список адресов"
                    [ "$ipset_to_clear" == "custom_exclude" ] && ipset_readable_name="пользовательский список адресов-исключений"
                    [ "$ipset_to_clear" == "geo" ] && ipset_to_clear="geo_whitelist geo_blacklist geo_exclude" && ipset_readable_name="список подсетей стран"
                    [ "$ipset_to_clear" == "ndm_lockout" ] && ipset_readable_name="список заблокированных адресов NDMS"
                    [ "$ipset_to_clear" == "honeypot" ] && ipset_readable_name="список заблокированных ловушкой адресов"
                    question_text="Очистить ${ipset_readable_name}? (Y/N): "
                fi
                if read -p "$question_text" confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
                    local custom_cleared_list=""
                    local lockout_cleared="0"
                    local ndmset_has_ips="0"
                    for set in $ipset_to_clear; do
                        local name="ascn_$set"
                        [ -n "$(ipset -q -n list $name)" ] && ipset flush $name
                        case "$set" in
                        "geo_whitelist" | "geo_blacklist" | "geo_exclude")
                            geo_cleared="1"
                            rm -f "$IPSETS_DIRECTORY/geo/"*
                            ;;
                        "custom_whitelist" | "custom_blacklist" | "custom_exclude")
                            if [ "$set" == "custom_blacklist" ]; then
                                custom_cleared_list="blacklist"
                            elif [ "$set" == "custom_whitelist" ]; then
                                custom_cleared_list="whitelist"
                            fi
                            local custom_set_filename="$ANTISCAN_DIR/$name.txt"
                            [ -f "$custom_set_filename" ] && >"$custom_set_filename"
                            ;;
                        *)
                            local set_filename="$IPSETS_DIRECTORY/ipset_$name.txt"
                            [ -f "$set_filename" ] && rm "$set_filename"
                            [ "$set" == "ndm_lockout" ] && lockout_cleared="1"
                            ;;
                        esac
                    done
                    if [ "$SAVE_IPSETS" == "1" ]; then
                        if [ "$custom_cleared_list" == "$CUSTOM_LISTS_BLOCK_MODE" ]; then
                            delete_ipset "custom" "$custom_cleared_list"
                            local list_name=""
                            [ "$custom_cleared_list" == "blacklist" ] && list_name="черному" || list_name="белому"
                            msg_to_print="Блокировка по пользовательскому $list_name списку отключена. Внесите новые записи и перезапустите Antiscan."
                            printf "${YELLOW_COLOR}${msg_to_print}${NO_STYLE}\n"
                            print_message "warning" "${msg_to_print}"
                        fi
                        if [ "$geo_cleared" == "1" ] && [[ "$GEOBLOCK_MODE" == "blacklist" || "$GEOBLOCK_MODE" == "whitelist" || -n "$GEO_EXCLUDE_COUNTRIES" ]]; then
                            delete_ipset "geo" "$GEOBLOCK_MODE"
                            msg_to_print="Перезапустите Antiscan, чтобы повторно загрузить список подсетей стран и начать их использование."
                            printf "${YELLOW_COLOR}${msg_to_print}${NO_STYLE}\n"
                            print_message "warning" "${msg_to_print}"
                        fi
                    fi
                    if [ "$lockout_cleared" == "1" ] && [ "$READ_NDM_LOCKOUT_IPSETS" == "1" ]; then
                        local ndm_ipsets="$(ipset list -n | grep -E '^_NDM_BFD_.+4$')"
                        for ndm_ipset in $ndm_ipsets; do
                            local ndm_ipset_data="$(ipset list $ndm_ipset | tail -n +8)"
                            [ -n "$ndm_ipset_data" ] && ndmset_has_ips=1
                        done
                        if [ "$ndmset_has_ips" == "1" ]; then
                            msg_to_print="Блокировка будет снята, когда система очистит собственные списки ограничения доступа."
                            printf "${YELLOW_COLOR}${msg_to_print}${NO_STYLE}\n"
                            print_message "warning" "${msg_to_print}"
                        fi
                    fi
                fi
            fi
        else
            print_message "error" "Antiscan не запущен"
        fi
        ;;
    *)
        print_message "console" "Использование: $0 flush [candidates|ips|subnets|custom_whitelist|custom_blacklist|custom_exclude|geo|ndm_lockout|honeypot]"
        ;;
    esac
}

delete_ipset() {
    remove_rules
    local set="ascn_${1}_${2}"
    if [ -n "$(ipset -q -n list $set)" ]; then
        ipset destroy $set
    fi
    add_rules
}

update_ipsets() {
    case "$1" in
    "custom" | "geo")
        if ascn_is_running; then
            if config_is_reloading; then
                print_message "error" "Обновление ipset недоступно во время обновления конфигурации Antiscan"
                exit 2
            else
                if [ "$1" == "custom" ]; then
                    if [ "$CUSTOM_LISTS_BLOCK_MODE" == "blacklist" ] || [ "$CUSTOM_LISTS_BLOCK_MODE" == "whitelist" ]; then
                        local ipset_custom_name="ascn_custom_${CUSTOM_LISTS_BLOCK_MODE}"
                        if [ -n "$(ipset -q -n list $ipset_custom_name)" ]; then
                            ipset flush "$ipset_custom_name"
                            load_custom_ipset "$ipset_custom_name"
                        else
                            remove_rules
                            load_custom_ipset "$ipset_custom_name"
                            add_rules
                        fi
                    fi
                    if [ "$USE_CUSTOM_EXCLUDE_LIST" == "1" ]; then
                        if [ -n "$(ipset -q -n list ascn_custom_exclude)" ]; then
                            ipset flush ascn_custom_exclude
                            load_custom_ipset "ascn_custom_exclude"
                        else
                            remove_rules
                            load_custom_ipset "ascn_custom_exclude"
                            add_rules
                        fi
                    fi
                else
                    force_reload_geo_ipsets
                fi
            fi
        else
            exit 1
        fi
        ;;
    *)
        print_message "console" "Использование: $0 update_ipsets {custom|geo}"
        ;;
    esac
}

read_ip_candidates() {
    if ascn_is_running; then
        if [ "$ENABLE_IPS_BAN" == "1" ]; then
            if config_is_reloading; then
                print_message "error" "Работа с адресами-кандидатами невозможна, пока идёт обновление конфигурации Antiscan"
                exit 2
            else
                if [ -n "$(ipset -q -n list ascn_ips)" ] && [ -n "$(ipset -q -n list ascn_candidates)" ] && [ -n "$(ipset -q -n list ascn_subnets)" ]; then
                    local ipset_candidates="$(ipset save ascn_candidates | tail -n +2)"
                    local ipset_ips="$(ipset save ascn_ips | tail -n +2)"

                    local ipset_honeypot_ips=""
                    if [ -n "$(ipset -q -n list ascn_honeypot)" ]; then
                        ipset_honeypot_ips="$(ipset save ascn_honeypot | tail -n +2)"
                    fi

                    local ipset_combined_sorted="$(printf "${ipset_candidates}\n${ipset_ips}\n${ipset_honeypot_ips}" | sort -u)"

                    if [ -n "$ipset_combined_sorted" ]; then
                        [ -f "$ASCN_REGEXP_FILE" ] && rm "$ASCN_REGEXP_FILE"

                        local sorted_candidates="$(echo "$ipset_combined_sorted" | grep -oE '([0-9]{1,3}[\.]){3}' | uniq -c)"
                        local regexp_variable=""
                        local ipset_variable=""

                        while read count subnet_number; do
                            if [ "$count" -ge "$DIFFERENT_IP_THRESHOLD" ]; then
                                regexp_variable="${regexp_variable}${subnet_number}[0-9]{1,3}|"
                                ipset_variable="${ipset_variable}add ascn_subnets ${subnet_number}0/24\n"
                            fi
                        done <<EOF
$sorted_candidates
EOF

                        echo -e "$ipset_variable" | ipset -! restore

                        if [ -n "$regexp_variable" ]; then
                            local ipset_candidates_sorted="$(echo "$ipset_candidates" | sort)"
                            local ipset_ips_sorted="$(echo "$ipset_ips" | sort)"
                            local ipset_honeypot_sorted="$(echo "$ipset_honeypot_ips" | sort)"

                            local ips_regexp="$(echo "$regexp_variable" | sed 's/.$//')"

                            if [ -n "$ipset_candidates_sorted" ]; then
                                ipset flush ascn_candidates
                                echo "$ipset_candidates_sorted" | grep -vE "(${ips_regexp})" | ipset -! restore
                            fi

                            if [ -n "$ipset_ips_sorted" ]; then
                                ipset flush ascn_ips
                                echo "$ipset_ips_sorted" | grep -vE "(${ips_regexp})" | ipset -! restore
                            fi

                            if [ -n "$ipset_honeypot_sorted" ]; then
                                ipset flush ascn_honeypot
                                echo "$ipset_honeypot_sorted" | grep -vE "(${ips_regexp})" | ipset -! restore
                            fi
                        fi
                    fi
                fi
            fi
        fi
    else
        exit 1
    fi
}

read_ndm_ipsets() {
    if ascn_is_running; then
        if config_is_reloading; then
            print_message "error" "Работа с системными списками адресов невозможна, пока идёт обновление конфигурации Antiscan"
            exit 2
        else
            if [ -n "$(ipset -q -n list ascn_ndm_lockout)" ]; then
                local ndm_sets="$(ipset list -n | grep -E '^_NDM_BFD_.+4$')"
                local $ndm_set_ips=""
                for ndm_set in $ndm_sets; do
                    local ndm_set_data="$(ipset save $ndm_set -q | tail -n +2 | sed "/127.0.0.1$/d; s/$ndm_set/ascn_ndm_lockout/")"
                    if [ -n "$ndm_set_data" ]; then
                        [ -z "$ndm_set_ips" ] && ndm_set_ips="${ndm_set_data}" || ndm_set_ips="${ndm_set_ips}\n${ndm_set_data}"
                    fi
                done
                if [ -n "$ndm_set_ips" ]; then
                    echo -e "$ndm_set_ips" | ipset -! restore
                fi
            fi
        fi
    else
        exit 1
    fi
}
