-- sync_employees.sql
-- Обновление списка сотрудников из CSV
-- (обновляет, добавляет новых, деактивирует отсутствующих)

CREATE TEMP TABLE _emp(full_name text, is_active text, telegram_id bigint);
COPY _emp FROM '/tmp/employees.csv' WITH (FORMAT csv, HEADER true);

-- обновляем существующих
UPDATE employees e
SET
  full_name = c.full_name,
  is_active = CASE WHEN c.is_active ILIKE 'да' THEN true ELSE false END
FROM _emp c
WHERE e.telegram_id = c.telegram_id;

-- добавляем новых
INSERT INTO employees(full_name, is_active, telegram_id)
SELECT
  full_name,
  CASE WHEN is_active ILIKE 'да' THEN true ELSE false END,
  telegram_id
FROM _emp c
WHERE NOT EXISTS (
  SELECT 1 FROM employees e WHERE e.telegram_id = c.telegram_id
);

-- деактивируем тех, кого нет в CSV
UPDATE employees e
SET is_active = false
WHERE NOT EXISTS (
  SELECT 1 FROM _emp c WHERE c.telegram_id = e.telegram_id
);
