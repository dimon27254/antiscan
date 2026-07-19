#!/bin/sh

set -e

RED_COLOR="\033[1;31m"
GREEN_COLOR="\033[1;32m"
BOLD_TEXT="\033[1m"
NO_STYLE="\033[0m"
antiscan_string="$(opkg list-installed antiscan)"
REPO_URL="https://dimon27254.github.io/antiscan/all"

print_message() {
  msg_type="$1"
  msg_text="$2"
  case $msg_type in
  error)
    printf "${RED_COLOR}${msg_text}${NO_STYLE}\n" >&2
    ;;
  notice)
    printf "${BOLD_TEXT}${msg_text}${NO_STYLE}\n"
    ;;
  success)
    printf "${GREEN_COLOR}${msg_text}${NO_STYLE}\n"
    ;;
  esac
}

print_message "notice" "Устанавливаем пакеты для доступа к репозиторию Antiscan..."
if opkg update && opkg install wget-ssl ca-bundle; then
  print_message "success" "wget-ssl и ca-bundle успешно установлены"
  print_message "notice" "Добавляем репозиторий Antiscan..."
  mkdir -p /opt/etc/opkg
  echo "src/gz antiscan ${REPO_URL}" >"/opt/etc/opkg/antiscan.conf"
  if opkg update; then
    if opkg install antiscan --force-reinstall; then
      if [ -z "$antiscan_string" ]; then
        print_message "success" "Antiscan успешно установлен!"
        print_message "notice" "Выполните настройку в ascn.conf и перезапустите Antiscan."
      else
        print_message "success" "Antiscan успешно обновлен!"
      fi
    else
      print_message "error" "Не удалось установить Antiscan"
    fi
  else
    print_message "error" "Не обновить список пакетов"
  fi
else
  print_message "error" "При установке wget-ssl и ca-bundle что-то пошло не так"
fi
