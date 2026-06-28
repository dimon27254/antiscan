check_updates() {
    local print_message="$1"
    local ascn_update_cache="/tmp/ascn_update.json"

    if download_data update; then
        SERVER_RESPONSE="$(cat $ascn_update_cache)"
        local ascn_legacy_update_available=0
        local ascn_main_update_available=0
        if echo "$SERVER_RESPONSE" | jq -e -r '.legacy.packages[].antiscan' >/dev/null 2>&1; then
            local remote_legacy_version=$(echo "$SERVER_RESPONSE" | jq -r '.legacy.packages[].antiscan.version' 2>/dev/null)
            local remote_legacy_update_info=$(echo "$SERVER_RESPONSE" | jq -r '.legacy.packages[].antiscan.update_info' 2>/dev/null)
            if [ -n "$remote_legacy_version" ] && [ "$remote_legacy_version" != "null" ]; then
                if opkg compare-versions "$remote_legacy_version" ">>" "$ASCN_VERSION"; then
                    if [ "$print_message" == "1" ]; then
                        print_message "warning" "Доступна новая версия Antiscan: $remote_legacy_version" 1
                        [ -n "$remote_legacy_update_info" ] && print_message "warning" "$remote_legacy_update_info" 1
                    fi
                    ascn_legacy_update_available=1
                else
                    if echo "$SERVER_RESPONSE" | jq -e -r '.main.packages[].antiscan' >/dev/null 2>&1; then
                        local remote_min_os=$(echo "$SERVER_RESPONSE" | jq -r '.main.min_os' 2>/dev/null)
                        local remote_main_version=$(echo "$SERVER_RESPONSE" | jq -r '.main.packages[].antiscan.version' 2>/dev/null)
                        local remote_main_update_info=$(echo "$SERVER_RESPONSE" | jq -r '.main.packages[].antiscan.update_info' 2>/dev/null)

                        if [ -n "$remote_min_os" ] && [ "$remote_min_os" != "null" ]; then
                            if download_data rci; then
                                local rci_cache="/tmp/ascn_rci.json"
                                local response="$(cat $rci_cache)"
                                if ndms_is_compatible "$response" "$remote_min_os"; then
                                    if [ -n "$remote_main_version" ] && [ "$remote_main_version" != "null" ]; then
                                        if opkg compare-versions "$remote_main_version" ">>" "$ASCN_VERSION"; then
                                            if [ "$print_message" == "1" ]; then
                                                print_message "warning" "Доступна новая версия Antiscan: $remote_main_version" 1
                                                [ -n "$remote_main_update_info" ] && print_message "warning" "$remote_main_update_info" 1
                                            fi
                                            ascn_main_update_available=1
                                        fi
                                    fi
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        fi
        if [ "$print_message" != "1" ]; then
            printf "$ascn_legacy_update_available $ascn_main_update_available\n"
        fi
    else
        return 2
    fi
}

download_data() {
    local data_type="$1"
    local update_cache=0
    local data_cache=""
    local data_url=""
    local max_timeout=""

    case "$data_type" in
    rci)
        data_cache="/tmp/ascn_rci.json"
        data_url="http://localhost:79/rci/show/version"
        ;;

    update)
        data_cache="/tmp/ascn_update.json"
        data_url="https://antiscan.ru/data/update/v1/update.json"
        ;;
    esac

    if [ -s "$data_cache" ]; then
        local cache_timestamp="$(date -r $data_cache +%s)"
        local now_time="$(date +%s)"
        local time_result=$((now_time - cache_timestamp))
        [ "$time_result" -gt 900 ] && update_cache=1
    else
        update_cache=1
    fi

    if [ "$update_cache" -eq 1 ]; then
        if ! curl -A "Antiscan $ASCN_VERSION" --connect-timeout 5 --retry 5 --retry-delay 3 --max-time 10 -kfsS "$data_url" -o "$data_cache" 2>/dev/null; then
            [ -f "$data_cache" ] && rm -f "$data_cache"
            return 1
        fi
    fi

    [ ! -s "$data_cache" ] && return 1 || return 0
}

ndms_is_compatible() {
    local RCI_RESPONSE="$1"
    local target_version="$2"
    local version_is_compatible=0

    if NDMS_VERSION="$(echo "$RCI_RESPONSE" | jq -r '.release' 2>/dev/null)"; then
        if echo "$NDMS_VERSION" | grep -Eq '^'[0-9]{1,}.[0-9]{1,}.[a-zA-Z]{1,}.[0-9]{1,}.[0-9]{1,}-[0-9]{1,}'$'; then
            if opkg compare-versions "$NDMS_VERSION" ">=" "$target_version"; then
                version_is_compatible=1
            fi
        fi
    fi
    [ "$version_is_compatible" -eq 1 ] && return 0 || return 1
}
