# Kudos Bot

## Описание проекта

Kudos Bot — корпоративный Telegram-бот, разработанный на Swift (Vapor 4).
Он помогает сотрудникам компании выражать благодарности коллегам, отслеживать статистику и управлять внутренними активностями.

Проект построен по feature-folder архитектуре, что делает каждую часть системы — (бот-меню, каталог сотрудников, благодарности, экспорт CSV и пр.) — независимым модулем.
Бот использует PostgreSQL для хранения данных, Docker Compose для контейнеризации и CI/CD GitHub Actions для автоматического деплоя на VPS.

---

## Основные возможности

- Приветственное меню с кнопками, без необходимости ввода команд вручную.
- Передача благодарностей коллегам через пошаговый сценарий:
  - выбор сотрудника из постраничного каталога (по 10 человек на экран),
  - ввод благодарности (не менее 20 символов),
  - сохранение благодарности в базе данных.
- Статистика:
  - количество отправленных благодарностей,
  - количество полученных благодарностей.
- Экспорт всех благодарностей в CSV (доступен только администраторам).
- Хранение данных в PostgreSQL.
- Полная работа в Telegram-чате без веб-интерфейса.
- Поддержка нескольких администраторов с возможностью настройки через переменную окружения.

---

## Архитектура и фичи

Проект построен по принципу feature-folder архитектуры, где каждая функциональная область изолирована в отдельный модуль.  
Ниже приведена структура директорий:

```
Sources/
├── App/
│   ├── Configuration/              # Настройка приложения и маршрутов
│   │   ├── Boot.swift              # Инициализация, миграции, сидирование
│   │   ├── Migrations/             # Миграции БД
│   │   └── Routes.swift            # Регистрация роутов
│   │
│   ├── Core/                       # Базовые сервисы и инфраструктура
│   │   ├── BotController.swift     # Роутинг апдейтов Telegram
│   │   ├── TelegramService.swift   # Транспорт: poll, sendMessage, sendDocument
│   │   ├── SessionStore.swift      # Хранилище состояний диалогов
│   │   ├── CSVExporter.swift       # Экспорт благодарностей в CSV
│   │   └── DTO.swift               # Общие DTO и вспомогательные модели
│   │
│   ├── Features/                   # Фичи (доменные модули)
│   │   ├── BotMenu/                # Меню Telegram-бота
│   │   │   ├── Controllers/
│   │   │   │   └── BotMenuController.swift
│   │   │   └── Services/
│   │   │       └── KeyboardBuilder.swift
│   │   │
│   │   ├── Employees/              # Модуль сотрудников
│   │   │   ├── Import/
│   │   │   ├── Migrations/
│   │   │   │   └── CreateEmployees.swift
│   │   │   ├── Models/
│   │   │   │   └── Employee.swift
│   │   │   └── Services/
│   │   │       └── EmployeesRepo.swift
│   │   │
│   │   └── Kudos/                  # Модуль благодарностей
│   │       └── KudosModel.swift
│   │
│   └── Run/                        # Точка входа
│       └── Main.swift
│
├── Resources/                      # Файлы сидирования и статические данные
│   └── SeedData/
│       ├── employees.csv
│       └── employees.template.csv
│
├── exports/                        # Экспортированные CSV-файлы
│
├── Scripts/                       # SQL-скрипты для ручной синхронизации сотрудников
│   └── sync_employees.sql
│
├── docker-compose.yml
├── docker-compose.prod.yml
└── Dockerfile
```

### Каталог сотрудников

- Список сотрудников загружается из CSV-файла `Resources/SeedData/employees.csv` и автоматически сохраняется в базу при первом запуске.
- Каждая запись содержит:
  - ФИО сотрудника,
  - статус активности (Да/Нет),
  - Telegram ID для связи с ботом.
- При передаче благодарности пользователь выбирает коллегу из постраничного каталога, что исключает необходимость ручного ввода `@username`.

### Связи и подсчёт статистики

- Благодарности хранятся с привязкой к сотрудникам через внешние ключи (`employee_id`, `from_employee_id`), а не просто к никам.
- Это обеспечивает корректный подсчёт статистики и экспорт данных даже при изменении никнеймов.
- Еще есть механика, чтобы при отсутствии Telegram ID используется резервный поиск по нику, но пока закомментировано в коде, чтобы не мешалось.
- Кнопки статистики «Сколько получил» и «Количество переданных» учитывают FK-связи.

### Экспорт CSV

- Экспортированные данные содержат фамилию и имя отправителя / получателя, а не только их логины.
- Пример структуры CSV:

  ```
  Дата и время;От кого (логин);От кого (имя);Кому (имя);Причина
  ```

- Ручной ввод ника временно скрыт из интерфейса, но сохраняется в коде для совместимости.

---

## Данные и структура базы

- PostgreSQL база данных запускается как сервис `db` в Docker Compose и использует volume для хранения данных.
- Таблица сотрудников содержит данные из CSV-семпла.
- Таблица благодарностей хранит информацию с FK-связями на сотрудников.
- Экспортированные CSV-файлы сохраняются в папке `exports/` на хост-машине (примонтировано как `./exports:/exports`).

---

## Развёртывание

### Локальный запуск

**Требования:** Xcode 15+/Swift 5.10, Docker Desktop.

Запуск через Docker Compose:

```bash
docker compose up --build -d
docker compose logs -f
```

### Продакшен

- Развёртывание на VPS (Ubuntu 22/24) с Docker и Docker Compose.
- Папка приложения `/apps/kudos-bot`.
- Файл окружения `.env` с настройками бота, базы данных и администраторами.
- Пример `.env`:

  ```env
  BOT_TOKEN=ваш_токен_бота

  POSTGRES_DB=kudos
  POSTGRES_USER=postgres
  POSTGRES_PASSWORD=postgres
  POSTGRES_HOST=db
  POSTGRES_PORT=5432
  DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}?sslmode=disable

  ADMIN_IDS=12345678,12345678

  ```

- Для запуска на VPS:

  ```bash
  sudo mkdir -p /apps/kudos-bot && cd /apps/kudos-bot
  sudo nano .env  # добавить переменные окружения
  sudo chmod 600 .env
  ```

- Запуск через Docker Compose с продовым файлом:

  ```bash
  docker compose -f docker-compose.prod.yml up -d
  ```

## Обновление сотрудников на VPS
 
Подходит для добавления новых, изменения существующих и деактивации удалённых сотрудников.

---

## 1. Обновите CSV на сервере

Файл сотрудников на VPS находится здесь:

```
/apps/kudos-bot/employees.csv
```

Отредактируйте его:

```bash
nano /apps/kudos-bot/employees.csv
```

---

## 2. Скопируйте CSV в контейнер базы данных

```bash
cd /apps/kudos-bot

docker compose -f docker-compose.prod.yml exec -T db   sh -c "cat > /tmp/employees.csv" < employees.csv
```

---

## 3. Выполните синхронизацию (safe-sync)

```bash
docker compose -f docker-compose.prod.yml exec -T db   psql -U postgres -d kudos << 'SQL'
CREATE TEMP TABLE _emp(
  full_name   text,
  is_active   text,
  telegram_id bigint
);

COPY _emp FROM '/tmp/employees.csv' WITH (FORMAT csv, HEADER true);

-- 1) Обновляем существующих
UPDATE employees e
SET
  full_name = trim(c.full_name),
  is_active = CASE WHEN c.is_active ILIKE 'да' THEN true ELSE false END
FROM _emp c
WHERE e.telegram_id = c.telegram_id;

-- 2) Добавляем новых сотрудников
INSERT INTO employees(full_name, is_active, telegram_id)
SELECT
  trim(full_name),
  CASE WHEN is_active ILIKE 'да' THEN true ELSE false END,
  telegram_id
FROM _emp c
WHERE NOT EXISTS (
  SELECT 1 FROM employees e WHERE e.telegram_id = c.telegram_id
);

-- 3) Деактивируем тех, кого нет в CSV
UPDATE employees e
SET is_active = false
WHERE NOT EXISTS (
  SELECT 1 FROM _emp c WHERE c.telegram_id = e.telegram_id
);
SQL
```

---

## 4. Перезапустите бота

```bash
docker compose -f docker-compose.prod.yml restart kudos-bot
```

---

## 5. Проверка результата

```bash
docker compose -f docker-compose.prod.yml exec db   psql -U postgres -d kudos -c "SELECT COUNT(*) FROM employees;"

docker compose -f docker-compose.prod.yml exec db   psql -U postgres -d kudos -c "SELECT full_name, is_active FROM employees ORDER BY full_name LIMIT 10;"
```

---

## Примечания

- Safe-sync **не удаляет благодарности** и **не портит связи**, так как обновление выполняется по `telegram_id`.
- Сотрудники, которых нет в CSV, автоматически получают `is_active = false`.
- Для аварийного полного сброса (reset) можно использовать TRUNCATE, но это редко нужно.


## CI/CD и мониторинг

### CI/CD

- Автоматическая сборка и пуш Docker-образа в Docker Hub при пуше в ветку `main`.
- Теги образа: `latest` и SHA коммита.
- SSH-доступ к VPS для обновления контейнеров через `docker compose pull && docker compose up -d`.
- Пайплайн настроен в `.github/workflows/deploy.yml`.

### Мониторинг и healthcheck

- Эндпоинт `/health` возвращает HTTP 200 OK при успешной работе приложения.
- Используется для проверки статуса контейнера в Docker Compose и внешнего мониторинга.
- Пример команды проверки:

  ```bash
  curl -i http://127.0.0.1:8080/health
  ```

- Настройка мониторинга (например, Uptime Kuma):

  - Тип: HTTP(s)
  - URL: `http://<IP_VPS>:8080/health`
  - Метод: GET
  - Интервал: 60 секунд
  - Допустимые коды: 200–299
  - Авторизация: отсутствует

### Очистка данных в базе

Для полной очистки таблицы благодарностей и сброса счетчика ID используйте команду:

```bash
docker compose exec -it db \
  psql -U postgres -d kudos -c \
  "TRUNCATE TABLE public.kudos RESTART IDENTITY CASCADE;"
```

**Внимание:** эта операция необратима и удалит все записи.

---

## Планы развития

- Разработка тестов для повышения качества кода.
- Расширение функционала команд бота.
- Улучшение интерфейса и пользовательского опыта.

---
