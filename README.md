# Kudos Bot

Kudos Bot — это Telegram-бот на **Swift (Vapor)** для отправки благодарностей коллегам и выгрузки их в CSV.

## Возможности
- Отправка благодарностей коллеге через команду `/thanks @username причина`.
- Экспорт всех благодарностей в формате CSV через `/export`.
- Хранение данных в SQLite.
- Лёгкий деплой через Docker + Docker Compose.

## Стек технологий
- [Swift 5.10](https://swift.org)
- [Vapor 4](https://vapor.codes)
- SQLite (через Fluent)
- Docker & Docker Compose

## Данные и выгрузки
- База данных (kudos.sqlite) хранится в отдельном volume (kudos_db).
- Экспортированные CSV-файлы сохраняются в папке exports/ на хосте.

