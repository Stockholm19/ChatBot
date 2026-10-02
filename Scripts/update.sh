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
# --wait: бот стартует только когда Postgres принимает подключения, иначе миграции при старте упадут
docker compose -f "${COMPOSE_FILE}" up -d --wait db
docker compose -f "${COMPOSE_FILE}" up -d autoheal

echo "🔁 Пересоздаю контейнер бота (подхватит и новый .env)…"
docker compose -f "${COMPOSE_FILE}" up -d --force-recreate --no-deps kudos-bot

echo "🧹 Удаляю старые образы…"
docker image prune -f > /dev/null

echo "⏳ Жду первого успешного обращения к Telegram…"
# В первые минуты /healthz отвечает 200 и без связи с Telegram (startup grace),
# поэтому ждём, пока в ответе появится last_poll_ok_at
for _ in $(seq 1 40); do
  if curl -fsS http://127.0.0.1:8080/healthz 2>/dev/null | grep -q '"last_poll_ok_at"'; then
    if docker compose -f "${COMPOSE_FILE}" logs kudos-bot 2>/dev/null | grep -q "Migrate/Sync failed"; then
      echo "⚠️  Бот запущен, но миграции базы упали. Логи:" >&2
      docker compose -f "${COMPOSE_FILE}" logs --tail=30 kudos-bot >&2
      exit 1
    fi
    echo "✅ Бот обновлён, база и Telegram на связи"
    docker compose -f "${COMPOSE_FILE}" logs --tail=15 kudos-bot
    exit 0
  fi
  sleep 3
done

echo "⚠️  Бот не связался с Telegram за 2 минуты. Логи:" >&2
docker compose -f "${COMPOSE_FILE}" logs --tail=50 kudos-bot >&2
exit 1
