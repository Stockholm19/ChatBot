# Kudos Bot

Kudos Bot — это Telegram-бот на **Swift (Vapor)** для отправки благодарностей коллегам и экспорта их в CSV. Разворачивается через Docker.

## Оглавление
- [Kudos Bot](#kudos-bot)
  - [Возможности](#возможности)
  - [Стек технологий](#стек-технологий)
  - [Данные и выгрузки](#данные-и-выгрузки)
  - [Быстрый старт (локально)](#быстрый-старт-локально)
  - [Продакшен через Docker Hub + GitHub Actions (CI/CD)](#продакшен-через-docker-hub--github-actions-cicd)
    - [Что подготовить один раз](#что-подготовить-один-раз)
    - [Переменные окружения (env)](#переменные-окружения-env)
    - [Что делает workflow](#что-делает-workflow)
    - [Ручная проверка на VPS](#ручная-проверка-на-vps)
    - [Роллбек версии](#роллбек-версии)
  - [Структура данных и экспорт](#структура-данных-и-экспорт)
  - [Архитектура проекта](#архитектура-проекта)
  - [Планы развития](#планы-развития)



## Скриншоты

<div align="center">
  <img src="Screenshots/Screenshots1.jpg" alt="Скриншот 1" height="420">
  &nbsp;&nbsp;
  <img src="Screenshots/Screenshots2.jpg" alt="Скриншот 2" height="420">
</div>

## Возможности
- Отправка благодарностей коллеге через команду `/thanks @username причина`.
- Экспорт всех благодарностей в формате CSV через `/export`.
- Хранение данных в SQLite.
- Лёгкий деплой через Docker + Docker Compose.
- Полностью работает в чате Telegram, управление только через команды (без веб-интерфейса).


## Стек технологий
- [Swift 5.10](https://swift.org)
- [Vapor 4](https://vapor.codes)
- Fluent ORM (с драйвером SQLite)
- Docker & Docker Compose
- GitHub Actions (CI/CD)

## Данные и выгрузки
- База данных (kudos.sqlite) хранится в отдельном volume (kudos_db).
- Экспортированные CSV-файлы сохраняются в папке exports/ на хосте.

---

## Быстрый старт (локально)

**Требования**: Xcode 15+/Swift 5.10, Docker Desktop (для контейнеров).
  
### Запуск в Docker
```bash
docker compose up --build -d
docker compose logs -f
```

## Продакшен через Docker Hub + GitHub Actions (CI/CD)

Пайплайн:
1. `git push` в ветку `main`;
2. GitHub Actions собирает Docker‑образ и пушит в Docker Hub: `helsinki253/kudos-bot:latest`;
3. Тот же workflow по SSH заходит на VPS и выполняет `docker compose pull && up -d`.

### Что подготовить один раз

**На VPS (Ubuntu 22/24):**
```bash
# Docker + Compose plugin
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Папка приложения + переменные окружения
sudo mkdir -p /apps/kudos-bot && cd /apps/kudos-bot
sudo nano .env     # добавить BOT_TOKEN=... и другие переменные (см. ниже)
sudo chmod 600 .env
```

**Secrets в GitHub (Settings → Secrets and variables → Actions):**
- `DOCKERHUB_USERNAME` — `helsinki253`
- `DOCKERHUB_TOKEN` — персональный токен Docker Hub (Read & Write)
- `VPS_HOST` — IP или хостнейм VPS
- `VPS_USER` — пользователь SSH (например, `root`)
- `VPS_SSH_KEY` — содержимое приватного SSH‑ключа (OpenSSH, BEGIN/END)

### Переменные окружения (.env)

Обязательные:
```env
BOT_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Опциональные (пример):
```env
LOG_LEVEL=info
STORAGE_DIR=/exports
```

### Что делает workflow

Файл: `.github/workflows/deploy.yml`  
- Сборка Docker образа (с кэшем слоёв через GitHub Actions Cache);
- Пуш в Docker Hub (`latest` и тег коммита);
- SSH на VPS + запуск/обновление Compose в `/apps/kudos-bot/docker-compose.prod.yml`.

### Ручная проверка на VPS

```bash
cd /apps/kudos-bot
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs --tail 200
```

### Роллбек версии

В логе Actions виден тег образа с SHA. На VPS:
```bash
docker pull helsinki253/kudos-bot:<SHA>
# при необходимости изменить image: в docker-compose.prod.yml на точный тег
docker compose -f docker-compose.prod.yml up -d
```



## Структура данных и экспорт

- SQLite база хранится в volume `kudos_db` (смонтирована в контейнер по пути `/data`).
- Экспортированные CSV складываются на хосте в `/apps/kudos-bot/exports` (том примонтирован как `./exports:/exports`).

---

## Архитектура проекта

Проект организован по feature-folder структуре, где каждый функциональный модуль содержит свои модели, контроллеры и сервисы. Это упрощает поддержку и масштабирование приложения.

Пример структуры папок:

```
Sources/
├── App/
│   ├── Features/
│   │   ├── Kudos/
│   │   │   ├── Models/
│   │   │   ├── Controllers/
│   │   │   └── Services/
│   │   ├── Users/
│   │   │   ├── Models/
│   │   │   ├── Controllers/
│   │   │   └── Services/
│   ├── Configure.swift
│   └── main.swift
```

## HTTP эндпоинты

- `GET /health` — проверка статуса сервера, возвращает HTTP 200 OK, используется для healthcheck контейнера.

## Планы развития (TODO)

- Заменить SQLite на PostgreSQL.
- Улучшить логирование и мониторинг приложения.
- Расширить функционал команд бота.


