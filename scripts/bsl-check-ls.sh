#!/bin/bash
# Проверка исходников BSL Language Server'ом в контексте конфигурации (без платформы и базы).
#
#   scripts/bsl-check.sh <каталог исходников> [--all]
#
# Анализируется весь проект (configurationRoot = src/bsp — выгрузка демо-БСП, см. .bsl-language-server.json), поэтому
# для обработок резолвятся вызовы общих модулей БСП; в отчёт попадают только файлы из указанного каталога.
# По умолчанию печатает синтаксические ошибки (ParseError) и замечания уровня Error; с --all — сводку по всем кодам.
# Код возврата 1 — есть ParseError или вызовы несуществующих методов (MissingCommonModuleMethod).
# Полный отчёт JSON — build/bsl/bsl-json.json (в .gitignore). Это единственная работающая проверка EPF:
# /CheckModules -ExternalDataProcessorOrReport конфигуратора ничего не проверяет — не использовать.
#
# Анализатор: ~/Documents/1C/Claud/tools/bsl-language-server (нативная сборка для macOS arm64, Java внутри).

set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$HOME/Documents/1C/Claud/tools/bsl-language-server/Contents/MacOS/bsl-language-server"
SRC="${1:-}"; MODE="${2:-}"
[ -n "$SRC" ] && [ -d "$SRC" ] || { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's|^# \?||'; exit 1; }
[ -x "$BIN" ] || { echo "нет анализатора: $BIN" >&2; exit 1; }
SRC_ABS="$(cd "$SRC" && pwd)"

OUT="$PROJ/build/bsl"
mkdir -p "$OUT"
"$BIN" --analyze --srcDir "$PROJ" --configuration "$PROJ/.bsl-language-server.json" --reporter json --outputDir "$OUT" >/dev/null 2>&1 || true
[ -f "$OUT/bsl-json.json" ] || { echo "анализатор не создал отчёт в $OUT" >&2; exit 1; }

python3 - "$OUT/bsl-json.json" "$SRC_ABS" "$MODE" "$PROJ" <<'EOF'
import json, sys, collections, os
from urllib.parse import unquote
d = json.load(open(sys.argv[1], encoding="utf-8")); mode = sys.argv[3]
prefix = sys.argv[2].rstrip("/") + "/"; proj = sys.argv[4].rstrip("/") + "/"
rel_prefix = prefix[len(proj):] if prefix.startswith(proj) else prefix
files = []
for f in d.get("fileinfos", []):
    p = unquote(f["path"]).replace("file://", "")
    if not os.path.isabs(p): p = os.path.normpath(os.path.join(proj, p))
    if p.startswith(prefix): f["path"] = p; files.append(f)
diags = [(f["path"][len(prefix):], x) for f in files for x in f.get("diagnostics", [])]
def code(x): return x["code"] if not isinstance(x.get("code"), dict) else x["code"].get("left")
parse = [(p, x) for p, x in diags if code(x) == "ParseError"]
missing = [(p, x) for p, x in diags if code(x) == "MissingCommonModuleMethod"]
errors = [(p, x) for p, x in diags if x.get("severity") == "Error" and code(x) not in ("ParseError", "MissingCommonModuleMethod")]
print(f"файлов: {len(files)}, замечаний: {len(diags)}, ParseError: {len(parse)}, MissingCommonModuleMethod: {len(missing)}, прочих Error: {len(errors)}")
def show(items):
    for p, x in items: print(f"  {p}:{x['range']['start']['line'] + 1}: [{code(x)}] {x['message'][:150]}")
if parse: print("--- синтаксические ошибки:"); show(parse)
if missing: print("--- вызовы несуществующих методов общих модулей:"); show(missing)
if errors:
    print("--- Error:")
    by = collections.defaultdict(list)
    for p, x in errors: by[code(x)].append((p, x))
    for c, items in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print(f" [{c}] x{len(items)}"); show(items[:5])
if mode == "--all":
    cnt = collections.Counter(code(x) for p, x in diags)
    print("--- все коды:", ", ".join(f"{k}={v}" for k, v in cnt.most_common()))
sys.exit(1 if (parse or missing) else 0)
EOF
