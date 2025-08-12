#!/bin/sh

set -e

RED_COLOR="\033[1;31m"
GREEN_COLOR="\033[1;32m"
BOLD_TEXT="\033[1m"
NO_STYLE="\033[0m"
CRONTABS_DIR="/opt/var/spool/cron/crontabs"
API_URL="https://api.github.com/repos/dimon27254/antiscan/releases/latest"
antiscan_string="$(opkg list-installed antiscan)"

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

cron_installed() {
  cron_string="$(opkg list-installed cron)"
  crond_busybox_string="$(opkg list-installed crond-busybox)"
  if [ -z "$cron_string" ] && [ -z "$crond_busybox_string" ]; then
    cron_init_scripts="$(find /opt/etc/init.d -regex '.*\/[sS][0-9]+cron.*')"
    if [ -z "$cron_init_scripts" ]; then
      return 1
    else
      if [ ! -d "$CRONTABS_DIR" ]; then
        return 1
      else
        return 0
      fi
    fi
  else
    return 0
  fi
}

print_message "notice" "Запрашиваем данные с GitHub..."

API_RESPONSE="$(curl -fsSL "$API_URL")"
if [ -z "$API_RESPONSE" ]; then
  print_message "error" "Не удалось получить данные"
  exit 1
else
  PACKAGE_URL="$(echo "$API_RESPONSE" | grep 'browser_download_url' | grep '\.ipk' | cut -d '"' -f4)"
  PACKAGE_VERSION="$(echo "$API_RESPONSE" | grep 'tag_name' | cut -d '"' -f4)"
  if [ -z "$PACKAGE_URL" ]; then
    print_message "error" "Не удалось найти файл пакета Antiscan"
    exit 1
  else
    print_message "success" "Данные успешно получены"
    print_message "notice" "Актуальная версия Antiscan: $PACKAGE_VERSION"
  fi
fi

PACKAGE_FILE="$(basename "$PACKAGE_URL")"
PACKAGE_PATH="/tmp/$PACKAGE_FILE"
print_message "notice" "Загрузка $PACKAGE_URL ..."
if curl -# -L -o "$PACKAGE_PATH" "$PACKAGE_URL"; then
  print_message "success" "Файл пакета Antiscan успешно загружен"
else
  print_message "error" "Не удалось загрузить файл пакета Antiscan"
  exit 1
fi

print_message "notice" "Проверяем наличие cron..."
if ! cron_installed; then
  print_message "notice" "Cron не найден. Устанавливаем..."
  if opkg update && opkg install cron; then
    print_message "success" "Cron успешно установлен"
    print_message "notice" "Настраиваем cron..."
    if [ ! -d "$CRONTABS_DIR" ]; then
      mkdir -p "$CRONTABS_DIR"
    fi
    if ! crontab -l >/dev/null 2>&1; then
      echo | crontab -
    fi
    sed -i 's/="-s"/=""/' "/opt/etc/init.d/S10cron"
    if "/opt/etc/init.d/S10cron" start; then
      print_message "success" "Cron готов к работе"
      print_message "notice" "Переходим к установке Antiscan..."
    else
      print_message "error" "Не удалось запустить cron"
      exit 1
    fi
  else
    print_message "error" "Не удалось установить cron"
    exit 1
  fi
else
  print_message "notice" "Cron найден. Переходим к установке Antiscan..."
fi

print_message "notice" "Установка $PACKAGE_FILE ..."
if opkg install "$PACKAGE_PATH" --force-reinstall; then
  if [ -z "$antiscan_string" ]; then
    print_message "success" "Antiscan успешно установлен!"
    print_message "notice" "Выполните настройку в ascn.conf и запустите Antiscan."
  else
    print_message "success" "Antiscan успешно обновлен!"
    print_message "notice" "Не забудьте его запустить."
  fi
else
  print_message "error" "Не удалось установить Antiscan"
fi
rm -f "$PACKAGE_PATH"