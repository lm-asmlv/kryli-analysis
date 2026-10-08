# -*- coding: utf-8 -*-
"""
fix_03_notebook.py
==================
Точечный патчер ноутбука 03_statistics.ipynb.

Что делает (3 правки, ничего больше не трогает):
  1. Ячейка VIF: финальный print -> корректная формулировка про max VIF ≈ 6.1.
  2. Markdown "3.9. Итоги раздела статистики": "VIF < 1.5" -> "VIF до ~6.1".
  3. Опционально: нормализует execution_count = null (чистый пересчёт).

Гарантии:
  * Работает с JSON, сохраняет ВСЕ ячейки и base64-картинки как есть.
  * Делает бэкап исходника (*.bak) перед записью.
  * Идемпотентен: повторный запуск ничего не ломает.
  * Если что-то не найдено — печатает предупреждение, но файл не портит.

Запуск (PowerShell, из корня проекта):
    python fix_03_notebook.py
    python fix_03_notebook.py notebooks\03_statistics.ipynb
"""

import sys
import json
import shutil
from pathlib import Path

# ---------- 1. Определяем путь к ноутбуку ----------
DEFAULT = Path("notebooks") / "03_statistics.ipynb"

if len(sys.argv) > 1:
    nb_path = Path(sys.argv[1])
else:
    nb_path = DEFAULT

if not nb_path.exists():
    print(f"[ОШИБКА] Не найден файл: {nb_path.resolve()}")
    print("Укажи путь явно:  python fix_03_notebook.py путь\\к\\03_statistics.ipynb")
    sys.exit(1)

print(f"[i] Патчим: {nb_path.resolve()}")

# ---------- 2. Читаем ноутбук ----------
with nb_path.open("r", encoding="utf-8") as f:
    nb = json.load(f)

cells = nb.get("cells", [])
assert isinstance(cells, list), "Неожиданная структура: 'cells' не список"

def src_to_text(cell):
    s = cell.get("source", [])
    return "".join(s) if isinstance(s, list) else str(s)

def set_src_lines(cell, new_code):
    """Заменяет исходник ячейки, сохраняя построчный формат (как у Jupyter)."""
    lines = new_code.splitlines(keepends=True)
    cell["source"] = lines

# ---------- 3. Определяем целевые строки ----------
OLD_VIF_PRINT = 'print("ВЫВОД: коллинеарность слабая (VIF < 1.5) — все предикторы можно оставить.")'
NEW_VIF_BLOCK = (
    'vif_max = vif["VIF"].max()\n'
    'if vif_max < 5:\n'
    '    verdict = "низкая — мультиколлинеарности нет"\n'
    'elif vif_max < 10:\n'
    '    verdict = "УМЕРЕННАЯ (некритичная). Максимум — у предикторов длины "\n'
    '    verdict += "(log_len / length_bucket_short), они описывают один и тот же "\n'
    '    verdict += "признак. Оставляем, но фиксируем в выводах."\n'
    'else:\n'
    '    verdict = "КРИТИЧНАЯ (> 10) — предикторы надо пересмотреть"\n'
    'print(f"\\nМаксимальный VIF: {vif_max:.3f} -> коллинеарность {verdict}")'
)

OLD_39_LINE = "- **VIF < 1.5** → мультиколлинеарность не проблема."
NEW_39_LINE = ("- **VIF до ~6.1** (предикторы длины) → коллинеарность **умеренная**, "
               "не критичная; отмечено в выводах.")

# ---------- 4. Проходим по ячейкам ----------
fixes = {"vif_print": 0, "md_39": 0, "counts": 0}

for cell in cells:
    ctype = cell.get("cell_type")
    text = src_to_text(cell)

    # --- Правка 1: print про VIF в code-ячейке ---
    if ctype == "code" and OLD_VIF_PRINT in text:
        new_text = text.replace(
            'print(f"\\nМаксимальный VIF: {vif[\'VIF\'].max():.3f}")\n' + OLD_VIF_PRINT,
            NEW_VIF_BLOCK,
        )
        # если предыдущая строка не совпала — заменяем хотя бы финальный print
        if new_text == text:
            new_text = text.replace(OLD_VIF_PRINT, NEW_VIF_BLOCK)
        set_src_lines(cell, new_text)
        fixes["vif_print"] += 1
        print("[+] Правка 1: VIF-print обновлён.")

    # --- Правка 2: markdown §3.9 ---
    if ctype == "markdown" and OLD_39_LINE in text:
        set_src_lines(cell, text.replace(OLD_39_LINE, NEW_39_LINE))
        fixes["md_39"] += 1
        print("[+] Правка 2: markdown §3.9 обновлён.")

    # --- Правка 3 (мягкая): чистим execution_count в code-ячейках ---
    if ctype == "code" and "execution_count" in cell:
        cell["execution_count"] = None
        fixes["counts"] += 1

# ---------- 5. Отчёт о поиске ----------
if fixes["vif_print"] == 0:
    print("[!] Правка 1: строка OLD_VIF_PRINT не найдена — проверь вручную.")
if fixes["md_39"] == 0:
    print("[!] Правка 2: строка 'VIF < 1.5' в markdown §3.9 не найдена — проверь вручную.")

# ---------- 6. Бэкап + запись ----------
backup = nb_path.with_suffix(nb_path.suffix + ".bak")
if not backup.exists():
    shutil.copy2(nb_path, backup)
    print(f"[i] Бэкап: {backup.name}")

with nb_path.open("w", encoding="utf-8") as f:
    json.dump(nb, f, ensure_ascii=False, indent=1)

print("\n=== ГОТОВО ===")
print(f"Ячеек всего:           {len(cells)}")
print(f"Исправлен VIF-print:   {fixes['vif_print']}")
print(f"Исправлен markdown:    {fixes['md_39']}")
print(f"Очищен execution_count: {fixes['counts']}")
print(f"\nФайл сохранён: {nb_path.resolve()}")
print("Открой ноутбук и выполни Run All с нуля.")
