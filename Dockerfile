# ---------- Stage 1: build ----------
FROM swift:5.10-jammy AS build
WORKDIR /app

# Кешируем зависимости (быстрые повторы сборки)
COPY Package.swift ./
COPY Package.resolved ./
RUN swift package resolve

# Копируем исходники и собираем релиз
COPY Sources Sources
RUN swift build -c release --static-swift-stdlib

# ---------- Stage 2: runtime ----------
FROM ubuntu:22.04
WORKDIR /run

# Минимум зависимостей для бинарника
RUN apt-get update && apt-get install -y \
    ca-certificates tzdata curl \
    && rm -rf /var/lib/apt/lists/*

# Кладём бинарник
COPY --from=build /app/.build/release/Run /run/Run

# (опционально) health-check порт
EXPOSE 8080

ENTRYPOINT ["/run/Run"]
