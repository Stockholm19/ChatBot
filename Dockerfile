# ---------- Stage 1: build ----------
FROM swift:5.10-jammy AS build
WORKDIR /app

# кеш зависимостей
COPY Package.swift ./
COPY Package.resolved ./
RUN swift package resolve

# копируем исходники И ресурсы в build-стейдж
COPY Sources Sources
COPY Resources Resources

RUN swift build -c release --static-swift-stdlib

# ---------- Stage 2: runtime ----------
FROM ubuntu:22.04
WORKDIR /run

# Минимум зависимостей для бинарника
RUN apt-get update && apt-get install -y \
    ca-certificates tzdata curl \
    && rm -rf /var/lib/apt/lists/*

# бинарь и ресурсы из build-стейджа
COPY --from=build /app/.build/release/Run /run/Run
COPY --from=build /app/Resources /run/Resources

# (опционально) health-check порт
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

ENTRYPOINT ["/run/Run"]
