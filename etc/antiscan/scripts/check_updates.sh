check_updates() {
    local print_message="$1"
    local ascn_update_cache="/tmp/ascn_update.json"
    local update_cache=0

    if [ -s "$ascn_update_cache" ]; then
        local cache_timestamp="$(date -r $ascn_update_cache +%s)"
        local now_time="$(date +%s)"
        local time_result=$((now_time - cache_timestamp))
        [ "$time_result" -gt 900 ] && update_cache=1
    else
        update_cache=1
    fi

    if [ "$update_cache" -eq 1 ]; then
        if ! curl -A "Antiscan $ASCN_VERSION" --connect-timeout 3 --retry 3 --retry-delay 2 -kfsS https://antiscan.ru/data/update/v1/update.json -o "$ascn_update_cache" 2>/dev/null; then
            [ -f "$ascn_update_cache" ] && rm -f "$ascn_update_cache"
            return 1
        fi
    fi

    if [ ! -s "$ascn_update_cache" ]; then
        return 2
    fi

    SERVER_RESPONSE="$(cat $ascn_update_cache)"
    if echo "$SERVER_RESPONSE" | jq -e -r '.legacy.packages[].antiscan' >/dev/null 2>&1; then
        local remote_legacy_version=$(echo "$SERVER_RESPONSE" | jq -r '.legacy.packages[].antiscan.version' 2>/dev/null)
        local remote_legacy_update_info=$(echo "$SERVER_RESPONSE" | jq -r '.legacy.packages[].antiscan.update_info' 2>/dev/null)
        if [ -n "$remote_legacy_version" ] && [ "$remote_legacy_version" != "null" ]; then
            if opkg compare-versions "$remote_legacy_version" ">>" "$ASCN_VERSION"; then
                if [ "$print_message" == "1" ]; then
                    print_message "warning" "Доступна новая версия Antiscan: $remote_legacy_version" 1
                    [ -n "$remote_legacy_update_info" ] && print_message "warning" "$remote_legacy_update_info" 1
                else
                    echo "$remote_legacy_version"
                fi
            else
                if echo "$SERVER_RESPONSE" | jq -e -r '.main.packages[].antiscan' >/dev/null 2>&1; then
                    local remote_min_os=$(echo "$SERVER_RESPONSE" | jq -r '.main.min_os' 2>/dev/null)
                    local remote_main_version=$(echo "$SERVER_RESPONSE" | jq -r '.main.packages[].antiscan.version' 2>/dev/null)
                    local remote_main_update_info=$(echo "$SERVER_RESPONSE" | jq -r '.main.packages[].antiscan.update_info' 2>/dev/null)
                    local ndms_version_valid=0
                    local ndms_is_compatible=0

                    if [ -n "$remote_min_os" ] && [ "$remote_min_os" != "null" ]; then
                        if RCI_RESPONSE="$(curl --connect-timeout 3 --retry 5 --retry-delay 3 -kfsS http://localhost:79/rci/show/version 2>/dev/null)"; then
                            if NDMS_VERSION="$(echo "$RCI_RESPONSE" | jq -r '.release' 2>/dev/null)"; then
                                if echo "$NDMS_VERSION" | grep -Eq '^'[0-9]{1,}.[0-9]{1,}.[a-zA-Z]{1,}.[0-9]{1,}.[0-9]{1,}-[0-9]{1,}'$'; then
                                    ndms_version_valid=1
                                fi
                            fi
                        fi

                        if [ "$ndms_version_valid" -eq 1 ]; then
                            opkg compare-versions "$NDMS_VERSION" ">=" "$remote_min_os" && ndms_is_compatible=1
                        fi

                        if [ "$ndms_is_compatible" -eq 1 ] && [ -n "$remote_main_version" ] && [ "$remote_main_version" != "null" ]; then
                            if opkg compare-versions "$remote_main_version" ">>" "$ASCN_VERSION"; then
                                if [ "$print_message" == "1" ]; then
                                    print_message "warning" "Доступна новая версия Antiscan: $remote_main_version" 1
                                    [ -n "$remote_main_update_info" ] && print_message "warning" "$remote_main_update_info" 1
                                else
                                    echo "$remote_main_version"
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi
}
