# Оркестрация: Airflow DAG `kryli_analysis_pipeline`

Описание демонстрационного DAG'а для канала **@krylikryli**.

> ℹ️ **Статус.** Полный стек Airflow в рамках тестового задания **не
> разворачивался** (оркестрация не является обязательным требованием).
> DAG приложен как **готовый продакшн-артефакт** и является **синтаксически
> валидным** — проверка в разделе «Проверка» ниже.

---

## 📌 Что делает DAG

Пайплайн: **`extract → cleansed → dq → marts`**

| # | Task ID | Что делает | Инструмент |
|---|---------|-----------|------------|
| 1 | `extract_raw_posts` | выгрузка сырых постов (12 мес, инкремент) | `python src/load_raw.py` (Telethon) |
| 2 | `build_cleansed` | метрики, ER, нормировка, флаги (вкл. `is_holiday`) | `sql/cleansed.sql` |
| 3 | `data_quality_check` | отчёт проверок качества данных | `sql/data_quality.sql` |
| 4 | `build_marts` | пересборка витрин `mart_*` | `sql/marts.sql` |

Порядок задан линейно: `extract >> cleansed >> dq >> marts`.

## ⚙️ Параметры запуска

| Параметр | Значение | Зачем |
|---|---|---|
| `schedule_interval` | `0 6 * * 1` (пн 06:00) | еженедельный пересчёт — данных мало, чаще не нужно |
| `catchup` | `False` | не поднимаем пропущенные недели |
| `max_active_runs` | `1` | **защита upsert** — нет параллельных запусков |
| `retries` | `2`, задержка 5 мин | устойчивость к сбоям сети/БД |
| `start_date` | 2026-01-01 | старт окна |

> 💡 `max_active_runs=1` — важная деталь: параллельные прогоны могли бы
> конфликтовать при пересборке `cleansed_posts`/витрин (`DROP TABLE` +
> `CREATE TABLE`). Здесь это исключено.

## 🔌 Подключение к Postgres

DAG использует `BashOperator` и обращается к базе внутри docker-сети:

```python
PG = "postgresql://kryli:kryli_pass@postgres:5432/kryli"
```

- хост **`postgres`** — имя сервиса в `docker-compose.yml`;
- пользователь/пароль — `kryli` / `kryli_pass`;
- база — `kryli`.

> ⚠️ **Проверь пароль!** В `docker-compose.yml` задано
> `POSTGRES_PASSWORD: kryli_pass`. В строке подключения должно стоять
> именно `kryli_pass` (а не `kryli`), иначе `psql` не подключится.

---

## ✅ Проверка валидности (без развёртывания)

DAG — это обычный Python-модуль. Проверяем по шагам.

### 1. Синтаксис (1 минута)

```powershell
python -m py_compile airflow/dags/kryli_analysis_dag.py
```

Пустой вывод = синтаксис корректен.

### 2. Импорт без ошибок (если Airflow установлен)

```bash
airflow dags list-import-errors      # не должно быть kryli_analysis_pipeline
airflow tasks list kryli_analysis_pipeline
```

Ожидаемый список задач:
```
extract_raw_posts
build_cleansed
data_quality_check
build_marts
```

### 3. Тест прогона «на месте»

```bash
airflow dags test kryli_analysis_pipeline 2026-01-06
```

### 4. Полное развёртывание (опционально)

```powershell
docker compose -f airflow/docker-compose.airflow.yml up -d
# http://localhost:8080  →  airflow / airflow
```

---

## 📁 Структура

```
airflow/
├── dags/
│   └── kryli_analysis_dag.py      # сам DAG (dag_id=kryli_analysis_pipeline)
├── docker-compose.airflow.yml     # локальный Airflow (опционально)
└── README_airflow.md              # этот файл
```

## 🐛 Известные ограничения

1. **Не развёрнут** в production-контуре — по условиям задания.
2. **Ручной docker-compose** для Airflow есть, но не тестировался end-to-end.
3. `extract_raw_posts` вызывает `src/load_raw.py` — при развёртывании нужно
   смонтировать проект внутрь контейнера (`/opt/airflow`).
