"""
Юнит-тесты трансформаций (чек-лист п. 11).

Запуск:
    pytest -q
или
    python -m pytest tests/ -v

Тесты автономны: не требуют подключения к БД — проверяют
чистую логику (формулы, бакеты, парсинг).
"""

import numpy as np
import pandas as pd
import pytest


# ============================================================
# 1. Формула ER
# ============================================================
def calc_er(reactions: float, replies: float, forwards: float, views: float) -> float:
    if views == 0:
        return np.nan
    return round((reactions + replies + forwards) / views, 6)


class TestERFormula:
    def test_simple(self):
        assert calc_er(10, 5, 3, 100) == 0.18

    def test_zero_views_returns_nan(self):
        assert np.isnan(calc_er(10, 5, 3, 0))

    def test_zero_engagement(self):
        assert calc_er(0, 0, 0, 500) == 0.0

    def test_negative_not_expected_but_calculable(self):
        # ER не должен быть отрицательным при корректных данных
        assert calc_er(1, 1, 1, 100) > 0


# ============================================================
# 2. Бакеты длины текста (терцили)
# ============================================================
def length_bucket(tertile: int) -> str:
    return {1: "short", 2: "medium", 3: "long"}[tertile]


class TestLengthBucket:
    def test_mapping(self):
        assert length_bucket(1) == "short"
        assert length_bucket(2) == "medium"
        assert length_bucket(3) == "long"

    def test_ntile_produces_three_groups(self):
        s = pd.Series(range(300))
        buckets = pd.qcut(s, 3, labels=["short", "medium", "long"])
        assert set(buckets.unique()) == {"short", "medium", "long"}
        assert len(buckets.value_counts()) == 3


# ============================================================
# 3. time_since_prev_post >= 0
# ============================================================
def interval_hours(t1: pd.Timestamp, t2: pd.Timestamp) -> float:
    """t2 — предыдущий, t1 — текущий (t1 позже t2)."""
    return (t1 - t2).total_seconds() / 3600.0


class TestInterval:
    def test_positive_interval(self):
        t2 = pd.Timestamp("2026-01-01 10:00", tz="UTC")
        t1 = pd.Timestamp("2026-01-01 13:30", tz="UTC")
        assert interval_hours(t1, t2) == pytest.approx(3.5)

    def test_sorted_series_never_negative(self):
        ts = pd.to_datetime([
            "2026-01-01 10:00", "2026-01-01 13:00",
            "2026-01-02 09:00", "2026-01-02 09:00",
        ], utc=True).to_series()
        diffs = ts.diff().dt.total_seconds().dropna()
        assert (diffs >= 0).all()


# ============================================================
# 4. Парсинг реакций (breakdown vs total)
# ============================================================
def reactions_total(breakdown: dict) -> int:
    return int(sum(breakdown.values()))


class TestReactionsParsing:
    def test_sum_breakdown(self):
        assert reactions_total({"👍": 10, "❤️": 5, "🔥": 2}) == 17

    def test_empty_breakdown(self):
        assert reactions_total({}) == 0

    def test_total_matches_manual(self):
        bd = {"a": 1, "b": 2, "c": 3}
        assert reactions_total(bd) == 6


# ============================================================
# 5. Часть дня (part_of_day)
# ============================================================
def part_of_day(hour: int) -> str:
    if 0 <= hour < 6:
        return "night"
    if 6 <= hour < 12:
        return "morning"
    if 12 <= hour < 18:
        return "day"
    return "evening"


class TestPartOfDay:
    @pytest.mark.parametrize("hour,expected", [
        (0, "night"), (5, "night"),
        (6, "morning"), (11, "morning"),
        (12, "day"), (17, "day"),
        (18, "evening"), (23, "evening"),
    ])
    def test_boundaries(self, hour, expected):
        assert part_of_day(hour) == expected


# ============================================================
# 6. Нормировка ER (er_norm)
# ============================================================
def er_norm(er: float, median_er: float) -> float:
    if median_er == 0 or np.isnan(median_er):
        return np.nan
    return round(er / median_er, 4)


class TestERNorm:
    def test_above_median(self):
        assert er_norm(0.02, 0.01) == 2.0

    def test_exactly_median(self):
        assert er_norm(0.01, 0.01) == 1.0

    def test_zero_median(self):
        assert np.isnan(er_norm(0.01, 0.0))
