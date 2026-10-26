#!/bin/bash
# Проверка исходников анализатором bsl-analyzer (itrous/bsl-analyzer) в контексте конфигурации (без платформы и базы).
#
#   scripts/bsl-check.sh <каталог исходников> [--all] [--ls]
#
# Анализируется весь проект по bsl-analyzer.toml (конфигурация - выгрузка демо-БСП src/bsp), обработка добавляется ключом
# --external, поэтому резолвятся вызовы общих модулей БСП; в отчет попадают только файлы из указанного каталога.
# Печатает ошибки, из-за которых модуль не скомпилируется или упадет (ParseError, неопределенное имя, несуществующий или
# неэкспортный метод, число и обязательность параметров, API не того контекста, поля запроса), и прочие Blocker/Critical/Major.
# Код возврата 1 - есть ошибки. Известные ложные срабатывания анализатора отфильтровываются (с отдельной строкой в выводе).
# С --all - сводка по всем кодам; с --ls - вторым проходом BSL Language Server (scripts/bsl-check-ls.sh): он один ловит
# методы не того типа (ТаблицаЗначений.Выгрузить(), Строка.Добавить()), но шумит на реквизитах формы.
# Полный отчет JSONL - build/bsl/bsl-analyzer.jsonl (в .gitignore). /CheckModules -ExternalDataProcessorOrReport не использовать.
#
# Общая проверка: ~/Documents/1C/Claud/tools/bsl-analyzer/bsl-check.py, анализатор там же (лаунчер, сам обновляется).

set -euo pipefail
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -n "${1:-}" ] && [ -d "$1" ] || { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's|^# \?||'; exit 1; }
exec python3 "$HOME/Documents/1C/Claud/tools/bsl-analyzer/bsl-check.py" --project "$PROJ" "$@"
