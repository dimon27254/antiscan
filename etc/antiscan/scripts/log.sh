RED_COLOR="\033[1;31m"
GREEN_COLOR="\033[1;32m"
YELLOW_COLOR="\033[1;33m"
BOLD_TEXT="\033[1m"
NO_STYLE="\033[0m"

print_message() {
    local msg_type="$1"
    local msg_text="$2"
    if [ "$msg_type" != "console" ]; then
        logger -p "${msg_type}" -t "Antiscan" "${msg_text}"
    fi
    case $msg_type in
    error)
        [ -z "$3" ] && printf "${RED_COLOR}${msg_text}${NO_STYLE}\n" >&2
        ;;
    notice)
        [ -z "$3" ] && printf "${BOLD_TEXT}${msg_text}${NO_STYLE}\n"
        ;;
    warning)
        [ "$3" == "1" ] && printf "${YELLOW_COLOR}${msg_text}${NO_STYLE}\n" >&2
        ;;
    console)
        printf "${BOLD_TEXT}${msg_text}${NO_STYLE}\n"
        ;;
    esac
}
