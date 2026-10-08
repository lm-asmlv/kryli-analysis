# ============================================================
# DAG (демонстрационный артефакт оркестрации).
# Полный стек Airflow в задании не разворачивается.
# Показан код продакшн-пайплайна: raw -> cleansed -> dq -> marts.
# Подключение: локальный Postgres (kryli_postgres, localhost:5432).
# ============================================================


from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator

# --- параметры подключения к рабочему Postgres (внут. Docker-сеть) ---
PG = "postgresql://kryli:kryli@postgres:5432/kryli_pass"
PSQL = f"psql {PG}"

default_args = {
    "owner": "kryli_analysis",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

with DAG(
    dag_id="kryli_analysis_pipeline",
    description="Telegram @krylikryli: raw -> cleansed -> dq -> marts",
    schedule_interval="0 6 * * 1",      # понедельник 06:00
    start_date=datetime(2026, 1, 1),
    catchup=False,                       # не поднимаем пропущенные недели
    max_active_runs=1,                   # нет параллельных запусков (защита upsert)
    default_args=default_args,
    tags=["kryli", "telegram", "etl"],
) as dag:

    # --- 1. Загрузка сырых постов за 12 месяцев (Telethon, инкремент) ---
    extract = BashOperator(
        task_id="extract_raw_posts",
        bash_command="cd /opt/airflow && python src/load_raw.py",
    )

    # --- 2. Cleansed: метрики, ER, нормировка, флаги (вкл. is_holiday) ---
    cleansed = BashOperator(
        task_id="build_cleansed",
        bash_command=f"{PSQL} -v ON_ERROR_STOP=1 < /opt/airflow/sql/cleansed.sql",
    )

    # --- 3. Data Quality: отчёт проверок ---
    dq = BashOperator(
        task_id="data_quality_check",
        bash_command=f"{PSQL} -v ON_ERROR_STOP=1 < /opt/airflow/sql/data_quality.sql",
    )

    # --- 4. Витрины mart_* ---
    marts = BashOperator(
        task_id="build_marts",
        bash_command=f"{PSQL} -v ON_ERROR_STOP=1 < /opt/airflow/sql/marts.sql",
    )

    # --- порядок выполнения ---
    extract >> cleansed >> dq >> marts
