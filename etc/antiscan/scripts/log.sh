RED_COLOR="\033[1;31m"
GREEN_COLOR="\033[1;32m"
YELLOW_COLOR="\033[1;33m"
BOLD_TEXT="\033[1m"
NO_STYLE="\033[0m"

print_message() {
    local msg_type="$1"
    local msg_text="$2"
    local print_param="$3"
    local no_log="$4"

    local escaped_text="$(echo "$msg_text" | sed 's/%/%%/g')"

    case $msg_type in
    error)
        if [ -z "$print_param" ]; then
            printf "${RED_COLOR}${escaped_text}${NO_STYLE}\n" >&2
        fi
        ;;
    notice)
        if [ -z "$print_param" ]; then
            printf "${BOLD_TEXT}${escaped_text}${NO_STYLE}\n"
        fi
        ;;
    warning)
        if [ -z "$print_param" ]; then
            printf "${YELLOW_COLOR}${escaped_text}${NO_STYLE}\n" >&2
        fi
        ;;
    console)
        if [ -z "$print_param" ]; then
            printf "${BOLD_TEXT}${escaped_text}${NO_STYLE}\n"
        fi
        ;;
    success)
        if [ -z "$print_param" ]; then
            printf "${GREEN_COLOR}${escaped_text}${NO_STYLE}\n"
        fi
        ;;
    esac

    if [ "$msg_type" != "console" ] && [ "$no_log" != "1" ]; then
        [ "$msg_type" == "success" ] && msg_type="warning"
        logger -p "${msg_type}" -t "Antiscan" "${msg_text}"
    fi
}
