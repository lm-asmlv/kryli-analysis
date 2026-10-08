# Аналитика Telegram-канала @krylikryli

Анализ вовлечённости аудитории Telegram-канала: **что влияет на реакции, комментарии и репосты**.

> 📎 **Источник чисел.** Все показатели синхронизированы с
> `notebooks/03_statistics.ipynb` (финальный прогон, HC3, n = 1404) и
> `conclusions.md`. При пересчёте ноутбука обновить README, `conclusions.md` и письмо.

---

## ⚠️ Терминология

> **В Telegram нет механизма «репоста»** — его роль выполняет **пересылка (forwards)**.
> Далее под «репостами» понимаются **форварды** (`forwards`).

Задание просит оценить влияние на **три реакции аудитории**:
- **реакции** (`reactions_total`),
- **комментарии** (`replies`),
- **репосты / пересылки** (`forwards`).

Все три анализируются **раздельно** — сводный ER маскирует механику (см. ниже).

---

## 📋 Задание

Проанализировать контент Telegram-канала @krylikryli и определить, **что влияет на реакцию аудитории** (комментарии, лайки, репосты):
- когда публиковать (час / часть дня / день недели);
- какой формат заходит (текст, фото, видео, документ);
- какова роль длины текста и «личных» постов.

**Результат:** цифры + визуализации + статистика + рекомендации + инженерный пайплайн.

---

## 🗂 Структура проекта

```
kryli-analysis/
├── data/
│   └── raw_posts.json             # снимок исходных данных (1480 постов)
├── sql/
│   ├── ddl.sql                    # схема raw_posts
│   ├── cleansed.sql               # метрики, ER, нормировка, флаги
│   ├── data_quality.sql           # DQ-проверки
│   └── marts.sql                  # ВСЕ витрины mart_* (в т.ч. factor_vs_metric)
├── src/
│   └── load_raw.py                # идемпотентная загрузка (upsert)
├── tests/
│   └── test_transform.py          # юнит-тесты трансформаций
├── notebooks/
│   ├── 01_connection_and_overview.ipynb
│   ├── 02_visualizations.ipynb
│   ├── 03_statistics.ipynb
│   ├── 04_conclusions_and_limitations.ipynb
│   └── figures/                   # артефакты графиков (.png)
├── airflow/
│   └── dags/
│       └── kryli_analysis_dag.py  # DAG пайплайна
├── docs/
│   └── dialog.md                  # выгрузка диалога с ИИ (требование сдачи)
├── docker-compose.yml             # PostgreSQL 16
├── requirements.txt
├── requirements-dev.txt
├── .gitignore
├── README.md
└── conclusions.md                 # выводы и рекомендации
```

> ℹ️ **Все витрины `mart_*` собраны в одном файле** `sql/marts.sql`
> (дубли убраны, единый источник истины). Отдельного `mart_factor_vs_metric.sql` нет.

---

## 🗄️ Данные

- **Источник:** снимок `data/raw_posts.json` — **1480 публикаций** (12 месяцев).
- **Аналитическая выборка:** **1435 постов** (45 свежих < 7 дней исключены — метрики вовлечённости ещё не устоялись).
- **Регрессия:** **n = 1404** (31 строка отсеяна из-за NaN в `log_len` / `log_interval`).
- **СУБД:** PostgreSQL 16 в Docker (`docker-compose.yml`).

### Слои

| Слой | Таблица | Назначение |
|---|---|---|
| raw | `raw_posts` | сырые посты из Telegram |
| cleansed | `cleansed_posts` | метрики, ER, нормировка, флаги, бакеты |
| marts | `mart_by_hour`, `mart_by_weekday`, … | агрегаты по факторам |
| marts | **`mart_by_factor_vs_metric`** | ⭐ три метрики раздельно |

### Контракт колонок витрин

> Витрины `mart_*` отдают **`mean_*`** и **`median_*`** (`mean_er`, `median_er`,
> `mean_views`, …). Колонка **`er`** есть **только** в `cleansed_posts`.

---

## 🧩 Архитектура пайплайна

```
raw_posts.json
   │  src/load_raw.py (upsert по post_id)
   ▼
raw_posts ──cleansed.sql──► cleansed_posts ──marts.sql──► mart_* (все витрины)
   │                             │
   │                             └── mart_by_factor_vs_metric (три метрики раздельно)
   ▼
data_quality.sql (DQ-проверки)
```

Оркестрация: `airflow/dags/kryli_analysis_dag.py` (DAG `kryli_analysis_pipeline`): `extract → cleansed → dq → marts`.

---

## 🚀 Воспроизведение

```powershell
# 1. Зависимости
pip install -r requirements.txt

# 2. Поднять PostgreSQL
docker compose up -d

# 3. Создать схему + залить данные
Get-Content sql\ddl.sql -Raw | docker exec -i kryli_postgres psql -U kryli -d kryli
python src\load_raw.py

# 4. Собрать cleansed, DQ и витрины (все витрины — в одном marts.sql)
Get-Content sql\cleansed.sql -Raw | docker exec -i kryli_postgres psql -U kryli -d kryli
Get-Content sql\data_quality.sql -Raw | docker exec -i kryli_postgres psql -U kryli -d kryli
Get-Content sql\marts.sql -Raw | docker exec -i kryli_postgres psql -U kryli -d kryli

# 5. Ноутбуки (по порядку, Run All с нуля)
jupyter lab notebooks/
```

---

## 📊 Ключевые результаты

Числа — финальный прогон HC3 (`03_statistics`, n = 1404). Подробнее — `conclusions.md`.

### 1. Общий уровень
- Медианный ER канала ≈ **0.65%**, средний ≈ **0.93%**.
- ER сильно **перекошен** (mean ≫ median) → выводы строим на **медианах**.

### 2. Время публикации
- **Утро/вечер** — наибольший медианный ER (тенденция; ANOVA p ≈ 0.11 → не строгий эффект).

### 3. Тип контента
- Разные медиа-типы дают разный ER; `photo` / `document` против `none`.

### 4. Личные vs промо (Mann–Whitney)
- Медиана ER личных **0.0125** vs промо **0.0065** — значимо (U = 44275.5, p < 0.001).
- В регрессии `is_personal_heur` = **+0.3592** → **+43%** к ER (p = 0.0012, HC3).

### 5. Топ-факторы (регрессия, HC3)
- Значимы: **`log_len`** (+0.1696, p < 0.001), **`log_interval`** (+0.0665, p < 0.001),
  **`is_personal_heur`** (+0.3592, p = 0.0012), категория `medium` (+0.3109, p = 0.0005).
- Незначимы: `is_forwarded` (p = 0.101), `is_holiday` (p = 0.655), `hour` (p = 0.066),
  `is_pinned` (p = 0.509 — большой coef, но широкий CI из-за малого n).
- **R² = 0.1769** (adj. 0.1716), n = 1404.

> ⚠️ Модель показывает **связь**, не причинность. Компоненты ER (реакции/комментарии/форварды) **исключены** из предикторов — иначе тавтология.

### 6. Комбинации «контент × время»
- Лучшая связка «личный контент × утро/день».

### 7. Три метрики раздельно
- **Реакции / комментарии / форварды** ведут себя **по-разному**.
- Пример: пост с 2 реакциями, но **307 комментариями** (ER 10,7%) — сводный ER маскирует механику.
- → смотреть `mart_by_factor_vs_metric` и графики «фактор × метрика».

---

## 📈 Графики

Все графики — в `notebooks/figures/`:

| Файл | Описание |
|---|---|
| `01_er_distribution.png` | распределение ER (mean vs median) |
| `01_monthly_posts.png` | посты по месяцам |
| `02_er_by_hour.png` | ER по часам (boxplot) |
| `02_er_by_media.png` | ER по типу медиа |
| `02_er_personal_promo.png` | личные vs промо |
| `02_length.png` | распределение длины + ER по бакетам |
| `02_er_by_part_of_day.png` | ER по части дня |
| `02_heatmap_combo.png` | heatmap контент × часть дня |
| `02_factor_metric_*.png` | ⭐ фактор × метрика (3 метрики на 1k просмотров) |
| `03_qq_resid.png` | QQ-plot остатков |
| `03_resid_fitted.png` | остатки vs предсказанные |
| `03_coefficient_plot.png` | коэффициенты регрессии + 95% CI (HC3) |

---

## 📚 Глоссарий

| Термин | Определение |
|---|---|
| `ER` | Engagement Rate = (реакции + комментарии + форварды) / просмотры |
| `er_norm` | `er` / медиана `er` по каналу |
| `is_recent` | Опубликован < 7 дней назад → исключается из анализа |
| `is_pinned` | Закреплённый пост |
| `is_forwarded` | Пост является пересылкой (forward) |
| `is_holiday` | Дата совпадает с фиксированным праздником |
| `is_personal_heur` | **Эвристика**: в тексте есть «я», «мне», «мой/моя/мои», «меня» |
| `length_bucket` | Терциль длины текста: `short` / `medium` / `long` |
| `part_of_day` | `night` (0–5) / `morning` (6–11) / `day` (12–17) / `evening` (18–23) |
| `media_type` | `none` (без медиа) / `document` / `photo` / `video` |
| `forwards` | Репосты (в Telegram аналог репоста — пересылка) |
| `forwards_per_reply` | Отношение форвардов к комментариям: >1 — «репостят больше, чем обсуждают» |

---

## ⚙️ Инженерия

### Идемпотентная загрузка
`src/load_raw.py` делает **upsert по `post_id`** (`INSERT ... ON CONFLICT DO UPDATE`) — повторный запуск не дублирует данные.

### Тесты
```powershell
pytest tests/ -v
```
Покрыты: формула ER, бакеты длины, `time_since_prev_post >= 0`, парсинг реакций.

### Airflow
DAG `kryli_analysis_pipeline` — код пайплайна `raw → cleansed → dq → marts`.
Синтаксическая валидность: `python -c "import kryli_analysis_dag"`.

> Оркестрация показана как артефакт; полный стек Airflow в задании не разворачивается.

---

## ⚠️ Ограничения

- **Причинность:** модель показывает **связь**, не причинный вклад.
- **Остатки ненормальны** (JB p = 1.6e-4; skew = −0.27, kurt = 2.96) → CLT смягчает при n > 1000.
- **Гетероскедастичность** (Breusch–Pagan p = 2.3e-5) → используются **HC3**-ошибки.
- **Дисперсии неоднородны** (Levene p = 2.5e-5) → ANOVA ограничена, опираемся на медианы.
- **Коллинеарность умеренная** (VIF макс = **6.125** у предикторов длины).
- **Эвристика «личных»** (`is_personal_heur`) — приближение по ключевым словам, n = 44.
- **`is_pinned`** незначим при большом coef → малый n, широкий CI.
- **Смысл `is_forwarded`** требует дополнительной валидации (p = 0.101).
- **Реакции/комментарии/форварды** коррелируют с ER **по построению** — не интерпретируем.

---

## 📦 Артефакты сдачи

| Артефакт | Файл |
|---|---|
| Исходные данные | `data/raw_posts.json` |
| SQL | `sql/*.sql` |
| ETL-скрипт | `src/load_raw.py` |
| Тесты | `tests/test_transform.py` |
| Ноутбуки | `notebooks/*.ipynb` |
| DAG | `airflow/dags/kryli_analysis_dag.py` |
| Выводы | `conclusions.md` |
| Выгрузка диалога | `docs/dialog.md` |
| README | `README.md` |

---

## 🔧 Стек технологий

PostgreSQL 16 · Python 3.14 · pandas · scipy · statsmodels · matplotlib · seaborn · SQLAlchemy · Airflow · Docker · pytest · Git
