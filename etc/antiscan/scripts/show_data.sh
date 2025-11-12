get_status() {
    printf "Версия Antiscan:\t${BOLD_TEXT}$ASCN_VERSION${NO_STYLE}\n"
    printf "Статус:\t\t\t"
    if ascn_is_running; then
        if config_is_reloading; then
            printf "${YELLOW_COLOR}обновление конфигурации${NO_STYLE}\n"
        elif geo_is_loading; then
            printf "${YELLOW_COLOR}обновление списков подсетей стран${NO_STYLE}\n"
        else
            if all_protections_disabled; then
                printf "${YELLOW_COLOR}без защиты${NO_STYLE}\n"
            else
                printf "${GREEN_COLOR}работает${NO_STYLE}\n"
            fi

            if [ "$ENABLE_IPS_BAN" == "1" ]; then
                local banned_ip_count="$(ipset list ascn_ips | tail -n +8 | grep -c '^')"
                local banned_subnets_count="$(ipset list ascn_subnets | tail -n +8 | grep -c '^')"
                printf "Заблокировано адресов:\t${BOLD_TEXT}$banned_ip_count${NO_STYLE}\n"
                printf "Заблокировано подсетей:\t${BOLD_TEXT}$banned_subnets_count${NO_STYLE}\n"
            else
                printf "Блокировка IP/подсетей:\t${RED_COLOR}отключена${NO_STYLE}\n"
            fi

            if [ "$ENABLE_HONEYPOT" == "1" ]; then
                local banned_ip_honeypot_count="$(ipset list ascn_honeypot | tail -n +8 | grep -c '^')"
                printf "Заблокировано ловушкой:\t${BOLD_TEXT}$banned_ip_honeypot_count${NO_STYLE}\n"
            else
                printf "Блокировка ловушкой:\t${RED_COLOR}отключена${NO_STYLE}\n"
            fi

            if [ "$READ_NDM_LOCKOUT_IPSETS" == "1" ]; then
                local banned_ip_ndm_count="$(ipset list ascn_ndm_lockout | tail -n +8 | grep -c '^')"
                printf "Заблокировано NDMS:\t${BOLD_TEXT}$banned_ip_ndm_count${NO_STYLE}\n"
            else
                printf "Чтение списков NDMS:\t${RED_COLOR}отключено${NO_STYLE}\n"
            fi

            if [ "$USE_CUSTOM_EXCLUDE_LIST" == "1" ] || [ "$CUSTOM_LISTS_BLOCK_MODE" == "blacklist" ] || [ "$CUSTOM_LISTS_BLOCK_MODE" == "whitelist" ]; then
                if [ "$USE_CUSTOM_EXCLUDE_LIST" == "1" ]; then
                    local excluded_count="$(ipset -q list ascn_custom_exclude | tail -n +8 | grep -c '^')"
                    if [ "$excluded_count" -gt 0 ]; then
                        printf "Список исключений:\t${BOLD_TEXT}$(get_ipset_member_text "$excluded_count")${NO_STYLE}\n"
                    else
                        printf "Список исключений:\t${RED_COLOR}не активен${NO_STYLE}\n"
                    fi
                fi

                case "$CUSTOM_LISTS_BLOCK_MODE" in
                "blacklist" | "whitelist")
                    local custom_set_name="ascn_custom_${CUSTOM_LISTS_BLOCK_MODE}"
                    local custom_set_type=""
                    [ "$CUSTOM_LISTS_BLOCK_MODE" == "blacklist" ] && custom_set_type="Черный список" || custom_set_type="Белый список"
                    local custom_ip_count="$(ipset -q list $custom_set_name | tail -n +8 | grep -c '^')"
                    if [ "$custom_ip_count" -gt 0 ]; then
                        printf "${custom_set_type}:\t\t${BOLD_TEXT}$(get_ipset_member_text "$custom_ip_count")${NO_STYLE}\n"
                    else
                        printf "${custom_set_type}:\t\t${RED_COLOR}не активен${NO_STYLE}\n"
                    fi
                    ;;
                esac
            else
                printf "Пользовательские списки ${RED_COLOR}не активны${NO_STYLE}\n"
            fi

            printf "Режим геоблокировки:\t"
            case "$GEOBLOCK_MODE" in
            "blacklist" | "whitelist")
                local geoset_name="ascn_geo_${GEOBLOCK_MODE}"
                local geoset_type=""
                [ "$GEOBLOCK_MODE" == "blacklist" ] && geoset_type="черный список" || geoset_type="белый список"

                local geo_directory="$IPSETS_DIRECTORY/geo"
                local available_countries_list=""
                local countries_list=""
                if [ ! -d "$geo_directory" ]; then
                    countries_list="${RED_COLOR}${GEOBLOCK_COUNTRIES}${NO_STYLE}"
                else
                    for country in $GEOBLOCK_COUNTRIES; do
                        local subnets_file="$geo_directory/$country.txt"
                        if [ ! -s "$subnets_file" ]; then
                            [ -z "$countries_list" ] && countries_list="${RED_COLOR}${country}${NO_STYLE}" || countries_list="${countries_list} ${RED_COLOR}${country}${NO_STYLE}"
                        else
                            [ -z "$available_countries_list" ] && available_countries_list="${country}" || available_countries_list="${available_countries_list} ${country}"
                            [ -z "$countries_list" ] && countries_list="${BOLD_TEXT}${country}${NO_STYLE}" || countries_list="${countries_list} ${BOLD_TEXT}${country}${NO_STYLE}"
                        fi
                    done
                fi

                if [ -n "$(ipset -q -n list $geoset_name)" ] && [ -n "$available_countries_list" ]; then
                    printf "${GREEN_COLOR}$geoset_type${NO_STYLE}\n"
                else
                    printf "${RED_COLOR}не работает${NO_STYLE}\n"
                fi
                printf "Страны геоблокировки:\t${countries_list}\n"
                ;;
            *)
                printf "${RED_COLOR}отключена${NO_STYLE}\n"
                ;;
            esac

            printf "Исключения по странам:\t"
            if [ -n "$GEO_EXCLUDE_COUNTRIES" ]; then
                local geo_directory="$IPSETS_DIRECTORY/geo"
                local available_countries_list=""
                local countries_list=""
                if [ ! -d "$geo_directory" ]; then
                    countries_list="${RED_COLOR}${GEO_EXCLUDE_COUNTRIES}${NO_STYLE}"
                else
                    for country in $GEO_EXCLUDE_COUNTRIES; do
                        local subnets_file="$geo_directory/$country.txt"
                        if [ ! -s "$subnets_file" ]; then
                            [ -z "$countries_list" ] && countries_list="${RED_COLOR}${country}${NO_STYLE}" || countries_list="${countries_list} ${RED_COLOR}${country}${NO_STYLE}"
                        else
                            [ -z "$available_countries_list" ] && available_countries_list="${country}" || available_countries_list="${available_countries_list} ${country}"
                            [ -z "$countries_list" ] && countries_list="${BOLD_TEXT}${country}${NO_STYLE}" || countries_list="${countries_list} ${BOLD_TEXT}${country}${NO_STYLE}"
                        fi
                    done
                fi
                printf "${countries_list}\n"
            else
                printf "${RED_COLOR}отключены${NO_STYLE}\n"
            fi
        fi
    else
        printf "${RED_COLOR}не запущен${NO_STYLE}\n"
    fi
}

get_ipset_member_text() {
    local record="записей"
    case $1 in
    *1?) true ;;
    *[2-4]) record="записи" ;;
    *1) record="запись" ;;
    esac
    echo "$1 $record"
}

show_ipsets() {
    case "$1" in
    ips | subnets | ndm_lockout | honeypot)
        if ascn_is_running; then
            if config_is_reloading; then
                print_message "error" "Просмотр данных недоступен во время обновления конфигурации Antiscan"
            else
                local text="адреса"
                local text_1="адресов"
                if [ "$1" == "subnets" ]; then
                    text="подсети"
                    text_1="подсетей"
                fi
                local ipset_data="$(ipset -q list ascn_$1 -s | tail -n +8)"
                local banned_count=0
                [ -n "$ipset_data" ] && banned_count="$(echo "$ipset_data" | grep -c '^')"
                if [ "$banned_count" -eq 0 ]; then
                    print_message "console" "Заблокированные ${text} отсутствуют"
                else
                    print_message "console" "Заблокированные ${text}:"
                    echo "$ipset_data"
                    print_message "console" "Заблокировано ${text_1}: ${banned_count}"
                fi
            fi
        else
            print_message "error" "Antiscan не запущен"
        fi
        ;;
    *)
        print_message "console" "Использование: $0 list {ips|subnets|ndm_lockout|honeypot}"
        ;;
    esac
}

show_version() {
    if [ "$1" == "opkg" ]; then
        local ascn_opkg_version="$(opkg list-installed antiscan | awk '{print $3}')"
        if [ -z "$ascn_opkg_version" ]; then
            print_message "console" "Не удалось определить версию пакета Antiscan"
        else
            print_message "console" "Версия Antiscan (OPKG): $ascn_opkg_version"
        fi
    else
        print_message "console" "Версия Antiscan: $ASCN_VERSION"
    fi
}
