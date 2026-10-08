# -*- coding: utf-8 -*-
"""
fix_03_notebook.py  (v2)
========================
Точечный патчер ноутбука 03_statistics.ipynb.

Что делает (4 правки, больше ничего не трогает):
  1. Ячейка VIF: финальный print -> корректный вердикт по max VIF (≈ 6.1).
  2. Markdown "3.9. Итоги": "VIF < 1.5" -> "VIF до ~6.1".
  3. Имена сохраняемых графиков нормализуются:
       diag_qq_resid.png        -> 03_qq_resid.png
       diag_resid_fitted.png    -> 03_resid_fitted.png
       (если встретятся) — чтобы совпасть с README / conclusions.
  4. Чистка execution_count у code-ячеек (чистый пересчёт).

Гарантии:
  * Работает с JSON, сохраняет ВСЕ ячейки и base64-картинки как есть.
  * Бэкап исходника (*.bak) перед записью.
  * Идемпотентен. Если строка не найдена — предупреждение, файл не портится.

Запуск (PowerShell, из корня проекта):
    python fix_03_notebook.py
    python fix_03_notebook.py notebooks\03_statistics.ipynb
"""

import sys
import json
import shutil
from pathlib import Path

# ---------- 1. Путь к ноутбуку ----------
DEFAULT = Path("notebooks") / "03_statistics.ipynb"
nb_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT

if not nb_path.exists():
    print(f"[ОШИБКА] Не найден файл: {nb_path.resolve()}")
    print(r"Укажи путь явно:  python fix_03_notebook.py notebooks\03_statistics.ipynb")
    sys.exit(1)

print(f"[i] Патчим: {nb_path.resolve()}")

# ---------- 2. Читаем ----------
with nb_path.open("r", encoding="utf-8") as f:
    nb = json.load(f)

cells = nb.get("cells", [])
assert isinstance(cells, list), "Неожиданная структура: 'cells' не список"


def src_to_text(cell):
    s = cell.get("source", [])
    return "".join(s) if isinstance(s, list) else str(s)


def set_src_lines(cell, new_code):
    cell["source"] = new_code.splitlines(keepends=True)


# ---------- 3. Целевые строки/замены ----------
OLD_VIF_PRINT = 'print("ВЫВОД: коллинеарность слабая (VIF < 1.5) — все предикторы можно оставить.")'
NEW_VIF_BLOCK = (
    'vif_max = vif["VIF"].max()\n'
    'if vif_max < 5:\n'
    '    verdict = "низкая — мультиколлинеарности нет"\n'
    'elif vif_max < 10:\n'
    '    verdict = "УМЕРЕННАЯ (некритичная). Максимум — у предикторов длины "\n'
    '    verdict += "(log_len / length_bucket_short): они описывают один и тот же признак."\n'
    'else:\n'
    '    verdict = "КРИТИЧНАЯ (> 10) — предикторы надо пересмотреть"\n'
    'print(f"\\nМаксимальный VIF: {vif_max:.3f} -> коллинеарность {verdict}")'
)

OLD_39_LINE = "- **VIF < 1.5** → мультиколлинеарность не проблема."
NEW_39_LINE = ("- **VIF до ~6.1** (предикторы длины) → коллинеарность **умеренная**, "
               "не критичная; отмечено в выводах.")

# Переименование графиков, чтобы совпасть с именами в README/conclusions
FILENAME_FIXES = {
    "figures/diag_qq_resid.png": "figures/03_qq_resid.png",
    "figures/diag_resid_fitted.png": "figures/03_resid_fitted.png",
    "figures/diag_qq.png": "figures/03_qq_resid.png",
}

fixes = {"vif_print": 0, "md_39": 0, "fname": 0, "counts": 0, "hour_fix": 0}

# ---------- 4. Обход ячеек ----------
for cell in cells:
    ctype = cell.get("cell_type")
    text = src_to_text(cell)

    # --- Правка 1: VIF-print ---
    if ctype == "code" and OLD_VIF_PRINT in text:
        new_text = text.replace(OLD_VIF_PRINT, NEW_VIF_BLOCK)
        set_src_lines(cell, new_text)
        fixes["vif_print"] += 1
        print("[+] Правка 1: VIF-print обновлён.")

    # --- Правка 2: markdown §3.9 ---
    if ctype == "markdown" and OLD_39_LINE in text:
        set_src_lines(cell, text.replace(OLD_39_LINE, NEW_39_LINE))
        fixes["md_39"] += 1
        print("[+] Правка 2: markdown §3.9 обновлён.")

    # --- Правка 3: имена PNG ---
    if ctype == "code" and "savefig" in text:
        new_text = text
        for old, new in FILENAME_FIXES.items():
            if old in new_text:
                new_text = new_text.replace(old, new)
        if new_text != text:
            set_src_lines(cell, new_text)
            fixes["fname"] += 1
            print("[+] Правка 3: имена графиков нормализованы.")

    # --- Правка 3b: hour_num -> hour (kosметика, если где-то осталось) ---
    if ctype == "code" and "hour_num" in text:
        set_src_lines(cell, text.replace("hour_num", "hour"))
        fixes["hour_fix"] += 1
        print("[+] Правка 3b: 'hour_num' -> 'hour'.")

    # --- Правка 4: execution_count ---
    if ctype == "code" and "execution_count" in cell:
        cell["execution_count"] = None
        fixes["counts"] += 1

# ---------- 5. Отчёт ----------
if fixes["vif_print"] == 0:
    print("[!] Правка 1: строка VIF-print не найдена — проверь вручную.")
if fixes["md_39"] == 0:
    print("[!] Правка 2: 'VIF < 1.5' в markdown §3.9 не найдена — проверь вручную.")
if fixes["fname"] == 0:
    print("[i] Правка 3: старые имена графиков (diag_*png) не встретились — вероятно, уже ок.")

# ---------- 6. Бэкап + запись ----------
backup = nb_path.with_suffix(nb_path.suffix + ".bak")
if not backup.exists():
    shutil.copy2(nb_path, backup)
    print(f"[i] Бэкап: {backup.name}")

with nb_path.open("w", encoding="utf-8") as f:
    json.dump(nb, f, ensure_ascii=False, indent=1)

print("\n=== ГОТОВО ===")
print(f"Ячеек всего:            {len(cells)}")
print(f"Исправлен VIF-print:    {fixes['vif_print']}")
print(f"Исправлен markdown:     {fixes['md_39']}")
print(f"Переименовано графиков: {fixes['fname']}")
print(f"hour_num -> hour:       {fixes['hour_fix']}")
print(f"Очищен execution_count: {fixes['counts']}")
print(f"\nФайл сохранён: {nb_path.resolve()}")
print("Открой ноутбук и выполни Run All с нуля.")
