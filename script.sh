#!/usr/bin/env bash

readonly INTERVAL=5
readonly LOG_FILE="monitor.log"

fail() {
    printf 'Ошибка: %s\n' "$1" >&2
    exit 1
}

stop() {
    printf '\nМониторинг остановлен.\n' >&2
    exit 0
}

if (( $# != 0 )); then
    fail "Аргументы не нужны. Запуск: bash script.sh"
fi

for program in date free df uptime sleep; do
    command -v "$program" >/dev/null 2>&1 || fail "Не найдена команда $program."
done

if [[ -e "$LOG_FILE" && ! -f "$LOG_FILE" ]]; then
    fail "$LOG_FILE должен быть обычным файлом."
fi

if ! { : >> "$LOG_FILE"; } 2>/dev/null; then
    fail "Нет доступа для записи в $LOG_FILE."
fi

trap stop INT TERM

printf 'Запись в %s, интервал %s с. Для остановки нажмите Ctrl+C.\n' "$LOG_FILE" "$INTERVAL"

while true; do
    if ! timestamp=$(date '+%Y-%m-%d %H:%M:%S'); then
        fail "Не удалось получить время."
    fi
    if ! memory=$(free -h); then
        fail "Не удалось получить сведения о памяти."
    fi
    if ! disks=$(df -h); then
        fail "Не удалось получить сведения о файловых системах."
    fi
    if ! system_uptime=$(uptime); then
        fail "Не удалось получить время работы системы."
    fi

    # Добавляем блок после успешного выполнения всех трех команд.
    if ! {
        printf '%s\n' \
            "--- $timestamp ---" \
            'free -h:' "$memory" \
            'df -h:' "$disks" \
            'uptime:' "$system_uptime" \
            '' >> "$LOG_FILE"
    } 2>/dev/null; then
        fail "Не удалось дописать данные в $LOG_FILE."
    fi

    sleep "$INTERVAL" || fail "Не удалось выдержать интервал $INTERVAL с."
done
