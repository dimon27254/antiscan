compare_versions() {
    local compare_result=$(awk -v A="$1" -v B="$3" '
BEGIN {
    for (i = 1; i < 256; i++) {
        ORDV[sprintf("%c", i)] = i
    }

    r = full_compare(A, B)
    print r
    exit 0
}

function charorder(c) {
    if (c == "")            return -3000
    if (c == "~")            return -4000
    if (c ~ /^[A-Za-z]$/)    return ORDV[c]
    return ORDV[c] + 10000
}

function cmp_nondigit(s1, s2,    len1, len2, maxlen, i, c1, c2, o1, o2) {
    len1 = length(s1); len2 = length(s2)
    maxlen = (len1 > len2) ? len1 : len2
    for (i = 1; i <= maxlen; i++) {
        c1 = (i <= len1) ? substr(s1, i, 1) : ""
        c2 = (i <= len2) ? substr(s2, i, 1) : ""
        o1 = charorder(c1); o2 = charorder(c2)
        if (o1 < o2) return -1
        if (o1 > o2) return 1
    }
    return 0
}

function verrevcmp(a, b,    nd1, nd2, d1, d2, r) {
    while (length(a) > 0 || length(b) > 0) {
        match(a, /^[^0-9]*/); nd1 = substr(a, 1, RLENGTH); a = substr(a, RLENGTH + 1)
        match(b, /^[^0-9]*/); nd2 = substr(b, 1, RLENGTH); b = substr(b, RLENGTH + 1)

        r = cmp_nondigit(nd1, nd2)
        if (r != 0) return r

        match(a, /^[0-9]*/); d1 = substr(a, 1, RLENGTH); a = substr(a, RLENGTH + 1)
        match(b, /^[0-9]*/); d2 = substr(b, 1, RLENGTH); b = substr(b, RLENGTH + 1)

        if (d1 == "") d1 = 0
        if (d2 == "") d2 = 0
        d1 = d1 + 0; d2 = d2 + 0

        if (d1 > d2) return 1
        if (d1 < d2) return -1
    }
    return 0
}

function split_ver(ver, out,    rest, epoch) {
    if (match(ver, /^[0-9]+:/)) {
        epoch = substr(ver, 1, RLENGTH - 1)
        rest  = substr(ver, RLENGTH + 1)
    } else {
        epoch = "0"
        rest  = ver
    }

    if (match(rest, /-[^-]*$/)) {
        out["revision"] = substr(rest, RSTART + 1)
        out["upstream"] = substr(rest, 1, RSTART - 1)
    } else {
        out["revision"] = ""
        out["upstream"] = rest
    }
    out["epoch"] = epoch
}

function full_compare(va, vb,    pa, pb, r) {
    split_ver(va, pa)
    split_ver(vb, pb)

    if ((pa["epoch"] + 0) > (pb["epoch"] + 0)) return 1
    if ((pa["epoch"] + 0) < (pb["epoch"] + 0)) return -1

    r = verrevcmp(pa["upstream"], pb["upstream"])
    if (r != 0) return r

    return verrevcmp(pa["revision"], pb["revision"])
}
')

    case "$2" in
    "<<") [ "$compare_result" -lt 0 ] && return 0 || return 1 ;;
    "<=") [ "$compare_result" -le 0 ] && return 0 || return 1 ;;
    "==") [ "$compare_result" -eq 0 ] && return 0 || return 1 ;;
    ">=") [ "$compare_result" -ge 0 ] && return 0 || return 1 ;;
    ">>") [ "$compare_result" -gt 0 ] && return 0 || return 1 ;;
    esac
}

check_firmware() {
    local rci_cache="/tmp/ascn_rci.json"

    if download_data rci; then
        local response="$(cat $rci_cache)"

        if ! echo "$response" | grep -q 'opkg-kmod-netfilter'; then
            print_message "error" "Компонент \"Модули ядра подсистемы Netfilter\" не установлен"
            return 1
        fi

        show_token_messages "$response"
    else
        print_message "error" "Не удалось определить версию ПО. Запуск Antiscan невозможен."
        return 2
    fi
}

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
                if compare_versions "$remote_legacy_version" ">>" "$ASCN_VERSION"; then
                    if [ "$print_message" == "1" ]; then
                        printf "\n"
                        print_message "warning" "Доступна новая версия Antiscan: $remote_legacy_version"
                        [ -n "$remote_legacy_update_info" ] && print_message "warning" "$remote_legacy_update_info"
                        printf "\n"
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
                                if compare_ndms_versions "$response" ">=" "$remote_min_os"; then
                                    if [ -n "$remote_main_version" ] && [ "$remote_main_version" != "null" ]; then
                                        if compare_versions "$remote_main_version" ">>" "$ASCN_VERSION"; then
                                            if [ "$print_message" == "1" ]; then
                                                printf "\n"
                                                print_message "warning" "Доступна новая версия Antiscan: $remote_main_version"
                                                [ -n "$remote_main_update_info" ] && print_message "warning" "$remote_main_update_info"
                                                printf "\n"
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
    local req_type=0

    case "$data_type" in
    update)
        data_cache="/tmp/ascn_update.json"
        data_url="https://antiscan.ru/data/update/v1/update.json"
        ;;

    rci)
        data_cache="/tmp/ascn_rci.json"
        data_url="http://127.0.0.1:79/rci/show/version"
        req_type=1
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
        if ! _checks_curl "$req_type" --connect-timeout 5 --retry 5 --retry-delay 5 --retry-connrefused --max-time 10 -kfs "$data_url" -o "$data_cache"; then
            [ -f "$data_cache" ] && rm -f "$data_cache"
            return 1
        fi
    fi

    [ ! -s "$data_cache" ] && return 1 || return 0
}

compare_ndms_versions() {
    local RCI_RESPONSE="$1"
    local operator="$2"
    local target_version="$3"
    local compare_result=0

    if NDMS_VERSION="$(echo "$RCI_RESPONSE" | jq -r '.release' 2>/dev/null)"; then
        if echo "$NDMS_VERSION" | grep -Eq '^'[0-9]{1,}.[0-9]{1,}.[a-zA-Z]{1,}.[0-9]{1,}.[0-9]{1,}-[0-9]{1,}'$'; then
            if compare_versions "$NDMS_VERSION" "$operator" "$target_version"; then
                compare_result=1
            fi
        fi
    fi
    [ "$compare_result" -eq 1 ] && return 0 || return 1
}

_checks_curl() {
    local rci_request="$1"
    shift 1
    if [ "$rci_request" -eq 1 ]; then
        _rci_curl "$@"
        return $?
    else
        curl -A "$ASCN_USERAGENT" "$@"
        return $?
    fi
}
