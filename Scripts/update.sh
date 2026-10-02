#!/usr/bin/env bash
#
# Обновление бота на домашнем сервере до свежего образа из Docker Hub.
# Ищет docker-compose.prod.yml и .env в текущей папке, а если их там нет — в корне репозитория рядом со скриптом.
#   cd /путь/к/боту && ./Scripts/update.sh
#   или: bash update.sh (если скрипт скопирован рядом с compose-файлом)
#
# Базу (сервис db и том kudos_pgdata) скрипт не трогает. Миграции применяются автоматически при старте бота.

set -euo pipefail

COMPOSE_FILE="docker-compose.prod.yml"

if [ ! -f "${COMPOSE_FILE}" ]; then
  cd "$(dirname "$0")/.."
fi
if [ ! -f "${COMPOSE_FILE}" ]; then
  echo "ERROR: не нашёл ${COMPOSE_FILE} ни в текущей папке, ни рядом со скриптом" >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "ERROR: рядом с ${COMPOSE_FILE} нет файла .env" >&2
  exit 1
fi

echo "⬇️  Скачиваю свежий образ…"
# Сеть через домашний прокси иногда рвёт соединение — пробуем несколько раз
pulled=false
for attempt in 1 2 3 4 5; do
  if docker compose -f "${COMPOSE_FILE}" pull kudos-bot; then
    pulled=true
    break
  fi
  echo "   попытка ${attempt} не удалась, повторю через 5 секунд…"
  sleep 5
done
if [ "${pulled}" != true ]; then
  echo "⚠️  Не удалось скачать образ — запускаю с тем, что уже есть локально." >&2
fi

echo "🗄  Проверяю базу и autoheal (при первом запуске — создаю)…"
docker compose -f "${COMPOSE_FILE}" up -d db autoheal

echo "🔁 Пересоздаю контейнер бота (подхватит и новый .env)…"
docker compose -f "${COMPOSE_FILE}" up -d --force-recreate --no-deps kudos-bot

echo "🧹 Удаляю старые образы…"
docker image prune -f > /dev/null

echo "⏳ Жду healthcheck…"
for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8080/healthz > /dev/null 2>&1; then
    echo "✅ Бот обновлён и здоров"
    docker compose -f "${COMPOSE_FILE}" logs --tail=15 kudos-bot
    exit 0
  fi
  sleep 3
done

echo "⚠️  /healthz не ответил за 90 секунд. Логи:" >&2
docker compose -f "${COMPOSE_FILE}" logs --tail=50 kudos-bot >&2
exit 1
