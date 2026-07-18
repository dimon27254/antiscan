curl_timeout_args="--connect-timeout 5 --retry 5 --retry-delay 3 --max-time 10"
rci_url="http://127.0.0.1:79/rci"
token_loc="$ANTISCAN_DIR/$(printf '\x4c\x6e\x52\x72\x62\x67\x3d\x3d' | base64 -d)"
key_loc="$ANTISCAN_DIR/$(printf '\x4c\x6d\x73\x3d' | base64 -d)"
ksn="$(printf '\x72\x6f\x75\x74\x65\x72\x5f\x73\x6e')"
ASCN_RCI_AUTH_FILE="/tmp/ascn_rci_auth"
ASCN_IGNORE_TOKEN_FILE="/tmp/ascn_ignore_token"

encode_token() {
    local RCI_RESPONSE=""
    local token="$1"
    local curl_headers="header = \"Accept: application/json\"\nheader = \"X-Ndma-Tkn: $token\"\n"
    if RCI_RESPONSE=$(printf "$curl_headers" | curl -A "$ASCN_USERAGENT" $curl_timeout_args \
        -X GET -kfs -K - $rci_url/show/identification); then
        if key=$(echo "$RCI_RESPONSE" | jq -r .serial); then
            if process_data "encode" "$key" "$ksn" | base64 >"$key_loc"; then
                if ! process_data "encode" "$token" "$key" | base64 >"$token_loc"; then
                    print_message "error" "Не удалось сохранить токен доступа"
                    return 1
                else
                    print_message "success" "Токен доступа успешно сохранен"
                fi
            else
                print_message "error" "Не удалось сохранить ключ"
                return 1
            fi
        else
            print_message "error" "Не удалось получить ключ"
            return 1
        fi
    else
        print_message "error" "Проверка токена доступа завершилась неудачно. Убедитесь в его корректности и повторите попытку."
        return 1
    fi
}

decode_token() {
    local return_errors="$1"
    local no_write_to_log="$2"
    if [ -s "$token_loc" ]; then
        if [ -s "$key_loc" ]; then
            local key=$(process_data "decode" "$(cat $key_loc | base64 -d 2>/dev/null)" "$ksn")
            local token=$(process_data "decode" "$(cat $token_loc | base64 -d 2>/dev/null)" "$key")
            if ! echo "$token" | grep -E '^[A-Za-z0-9]{56}$'; then
                print_message "error" "Декодированный токен доступа невалиден" "" "$no_write_to_log"
                return 2
            fi
        else
            [ "$return_errors" == "1" ] && print_message "error" "Ключ не найден" "" "$no_write_to_log"
            return 1
        fi
    else
        [ "$return_errors" == "1" ] && print_message "error" "Токен доступа не найден" "" "$no_write_to_log"
        return 1
    fi
}

rci_auth_required() {
    if [ ! -s "$ASCN_RCI_AUTH_FILE" ]; then
        if ! curl -kfs $curl_timeout_args -o /dev/null $rci_url/whoami; then
            echo "1" >"$ASCN_RCI_AUTH_FILE"
            return 0
        else
            echo "0" >"$ASCN_RCI_AUTH_FILE"
            return 1
        fi
    else
        local auth_required_result="$(cat $ASCN_RCI_AUTH_FILE)"
        [ "$auth_required_result" == "1" ] && return 0 || return 1
    fi
}

check_rci_auth() {
    if rci_auth_required; then
        if ! token_exists && [ "$ASCN_START_AFTER_INSTALL" == "1" ]; then
            print_message "console" "Добро пожаловать в Antiscan!\n"
            print_message "console" "Перед началом работы, пожалуйста, создайте в веб-интерфейсе или CLI роутера токен доступа и введите его в Antiscan.\n"
            if ! set_token; then
                printf "${YELLOW_COLOR}Вызовите команду${NO_STYLE} ${BOLD_TEXT}antiscan token set${NO_STYLE} ${YELLOW_COLOR}для повторного ввода токена.${NO_STYLE}\n"
                return 1
            fi
        else
            if [ ! -s "$token_loc" ]; then
                print_message "error" "Токен доступа не найден. Задайте его и перезапустите Antiscan."
                return 1
            else
                if [ ! -s "$key_loc" ]; then
                    print_message "error" "Ключ не найден. Повторно задайте токен доступа для генерации нового ключа."
                    return 1
                else
                    local token=""
                    if token="$(decode_token)"; then
                        if ! validate_token 0 "$token"; then
                            print_message "error" "Сохраненный токен доступа не прошел проверку. Задайте новый и перезапустите Antiscan."
                            return 1
                        fi
                    else
                        print_message "error" "Не удалось прочитать токен доступа. Задайте новый и перезапустите Antiscan."
                        return 1
                    fi
                fi
            fi
        fi
    fi
}

set_token() {
    local input_allowed=0

    local token_temp=""
    local token=""

    local rci_cache="/tmp/ascn_rci.json"

    if download_data rci; then
        local response="$(cat $rci_cache)"

        if compare_ndms_versions "$response" "<<" "5.02"; then
            print_message "warning" "Установка токена доступна только для ПО версии 5.2 и выше" "" 1
            return 2
        fi
    fi

    if [ -s "$token_loc" ]; then
        print_message "warning" "Токен доступа уже установлен." "" 1
        if read -p "Вы уверены, что хотите задать новый? (Y/N): " confirm && [[ $confirm == [yY] ]]; then
            input_allowed=1
        else
            return 1
        fi
    else
        input_allowed=1
    fi

    if [ "$input_allowed" -eq 1 ]; then
        if [ -z "$1" ]; then
            read -p "Введите токен доступа: " token_temp
        else
            token_temp="$1"
        fi
    fi

    if [ -z "$token_temp" ]; then
        print_message "error" "Токен доступа не может быть пустым. Повторите попытку ввода." "" 1
        return 1
    else
        token=$(echo "$token_temp" | tr -d ' ')
        if ! echo "$token" | grep -qE '^[A-Za-z0-9]{56}$'; then
            print_message "error" "Указанный токен доступа не корректен. Повторите попытку ввода." "" 1
            return 1
        else
            encode_token "$token"
            return "$?"
        fi
    fi
}

delete_token() {
    if [ -f "$token_loc" ] || [ -f "$key_loc" ]; then
        local delete_confirm=0

        rci_auth_required && print_message "warning" "Antiscan перестанет работать, если вы удалите токен доступа." "" 1
        if read -p "Вы уверены, что хотите удалить токен? (Y/N): " confirm && [[ $confirm == [yY] ]]; then
            delete_confirm=1
        else
            return 1
        fi

        if [ "$delete_confirm" -eq 1 ]; then
            [ -f "$token_loc" ] && rm -f "$token_loc"
            [ -f "$key_loc" ] && rm -f "$key_loc"
            [ -f "$ASCN_IGNORE_TOKEN_FILE" ] && rm -f "$ASCN_IGNORE_TOKEN_FILE"
            print_message "warning" "Токен доступа удален"
            if ascn_is_running && rci_auth_required; then
                /opt/etc/init.d/S99ascn stop
            fi
        fi
    else
        print_message "warning" "Нет токенов для удаления" "" 1
        return 1
    fi
}

check_token() {
    local token=""
    local rci_cache="/tmp/ascn_rci.json"

    if download_data rci; then
        local response="$(cat $rci_cache)"

        if compare_ndms_versions "$response" "<<" "5.02"; then
            print_message "warning" "Проверка токена доступна только в ПО версии 5.2 и выше" "" 1
            return 1
        fi
    fi

    token=$(decode_token 1 1) && validate_token 1 "$token"
}

validate_token() {
    local return_errors="$1"
    local token="$2"
    local curl_headers="header = \"Accept: application/json\"\nheader = \"X-Ndma-Tkn: $token\"\n"
    if printf "$curl_headers" | curl -A "$ASCN_USERAGENT" $curl_timeout_args \
        -X GET -kfs -o /dev/null -K - $rci_url/whoami; then
        [ "$return_errors" == "1" ] && print_message "success" "Токен доступа ${token:0:3}...${token: -3} валиден" "" 1
        return 0
    else
        [ "$return_errors" == "1" ] && print_message "error" "Токен доступа ${token:0:3}...${token: -3} не прошел проверку в системе" "" 1
        return 1
    fi
}

token_handler() {
    local action="$1"
    local data="$2"
    case "$action" in
    set)
        set_token "$data"
        ;;
    delete)
        delete_token
        ;;
    check)
        check_token
        ;;
    *)
        print_message "console" "Использование: $0 token {set|delete|check}"
        exit 1
        ;;
    esac
}

token_exists() {
    if [ -s "$token_loc" ]; then
        return 0
    else
        return 1
    fi
}

show_token_messages() {
    local response="$1"

    if token_exists && compare_ndms_versions "$response" "<<" "5.02"; then
        print_message "warning" "Токены доступа не поддерживаются в вашей версии ПО. Рекомендуется удалить токен из Antiscan для корректной работы."
        echo "1" >"$ASCN_IGNORE_TOKEN_FILE"
    fi

    if ! token_exists && compare_ndms_versions "$response" ">=" "5.02"; then
        print_message "warning" "Для корректной работы Antiscan необходимо создать и установить токен доступа."
    fi
}

_rci_curl() {
    if token_exists && [ ! -f "$ASCN_IGNORE_TOKEN_FILE" ]; then
        local token=""
        if token="$(decode_token 1)"; then
            local curl_headers="header = \"X-Ndma-Tkn: $token\"\n"
            printf "$curl_headers" | curl -A "$ASCN_USERAGENT" -K - "$@"
            return $?
        else
            return 1
        fi
    else
        if ! rci_auth_required; then
            curl -A "$ASCN_USERAGENT" "$@"
            curl_exitcode="$?"
        else
            return 2
        fi
    fi
}

process_data() {
    local mode="$1"
    local token="$2"
    local key="$3"
    awk -v mode="$mode" -v str="$token" -v key="$key" '
function xor_byte(a, b,    r, bit, abit, bbit) {
    r = 0; bit = 1
    while (a > 0 || b > 0) {
        abit = a % 2; bbit = b % 2
        if (abit != bbit) r += bit
        a = int(a / 2); b = int(b / 2)
        bit *= 2
    }
    return r
}
function hex_digit(v) {
    return substr("0123456789abcdef", v + 1, 1)
}
function hex_val(c,    p) {
    p = index("0123456789abcdef", tolower(c))
    return p - 1
}
BEGIN {
    for (i = 0; i < 256; i++) {
        ch = sprintf("%c", i)
        ord[ch] = i
    }
    klen = length(key)
    if (klen == 0) { exit 1 }

    if (mode == "encode") {
        n = length(str)
        out = ""
        for (i = 1; i <= n; i++) {
            c = substr(str, i, 1)
            k = substr(key, ((i - 1) % klen) + 1, 1)
            v = xor_byte(ord[c], ord[k])
            out = out hex_digit(int(v / 16)) hex_digit(v % 16)
        }
        print out
    } else if (mode == "decode") {
        n = length(str)
        out = ""
        j = 1
        for (i = 1; i + 1 <= n; i += 2) {
            hi = hex_val(substr(str, i, 1))
            lo = hex_val(substr(str, i + 1, 1))
            v = hi * 16 + lo
            k = substr(key, ((j - 1) % klen) + 1, 1)
            orig = xor_byte(v, ord[k])
            out = out sprintf("%c", orig)
            j++
        }
        print out
    } else {
        exit 1
    }
}
'
}
