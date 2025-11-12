#!/bin/sh

set -e

RED_COLOR="\033[1;31m"
GREEN_COLOR="\033[1;32m"
BOLD_TEXT="\033[1m"
NO_STYLE="\033[0m"
CRONTABS_DIR="/opt/var/spool/cron/crontabs"
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

print_message "notice" "Устанавливаем пакеты для доступа к репозиторию Antiscan..."
if opkg update && opkg install wget-ssl ca-bundle; then
  print_message "success" "wget-ssl и ca-bundle успешно установлены"
  print_message "notice" "Добавляем репозиторий Antiscan..."
  mkdir -p /opt/etc/opkg
  echo "src/gz antiscan ${REPO_URL}" >"/opt/etc/opkg/antiscan.conf"
  if opkg update; then
    print_message "notice" "Проверяем наличие cron..."
    if ! cron_installed; then
      print_message "notice" "Cron не найден. Устанавливаем..."
      if opkg install cron; then
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
          return 1
        fi
      else
        print_message "error" "Не удалось установить cron"
        return 1
      fi
    else
      print_message "notice" "Cron найден. Переходим к установке Antiscan..."
    fi

    if opkg install antiscan --force-reinstall; then
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
  else
    print_message "error" "Не обновить список пакетов"
  fi
else
  print_message "error" "При установке wget-ssl и ca-bundle что-то пошло не так"
fi
