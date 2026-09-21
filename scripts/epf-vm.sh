#!/bin/bash
# Сборка и разбор внешних обработок платформой 8.3.27 в Windows-VM.
#
# На маке конфигуратор 8.3.27 падает на больших базах (SIGSEGV), поэтому собираем в VM:
# платформа x86 под ARM-Windows, база подключается через общую папку Parallels.
#
#   scripts/epf-vm.sh build <ИмяОбработки>   — src/ -> .epf
#   scripts/epf-vm.sh check <ИмяОбработки>   — синтаксическая проверка собранного .epf
#   scripts/epf-vm.sh dump  <путь к .epf> <каталог назначения>

set -euo pipefail

PROJ_MAC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Параметры VM и учётка базы — в .v8-project.json, он в .gitignore: пароль в репозиторий не попадает.
eval "$(python3 "$PROJ_MAC/scripts/vmconf.py" "$PROJ_MAC/.v8-project.json")"

# Выполняет PowerShell в VM. Кодируем в UTF-16LE/base64: иначе кириллица и кавычки не доезжают.
run_ps() {
	local b64
	b64=$(printf '%s' "$1" | iconv -f UTF-8 -t UTF-16LE | base64)
	ssh "$SSH_HOST" "pwsh -NoProfile -EncodedCommand $b64" 2>&1 | tr -d '\r' | grep -v '^#< CLIXML$' | grep -v '^<Objs ' || true
}

# Собирает вызов 1cv8 и ждёт реального завершения процесса: конфигуратор отдаёт управление раньше.
# Переменную процесса нельзя называть $p — PowerShell не различает регистр и затрёт $P.
ps_1cv8() {
	local log="$1"; shift
	local args=""
	for a in "$@"; do args="$args,\"$a\""; done
	local auth=""
	# Пустой пользователь — база без списка пользователей, /N и /P не передаём вовсе.
	# Пустой пароль — /P не передаём тоже: Start-Process выбрасывает пустой аргумент,
	# и /P съедает следующий ключ как пароль, после чего конфигуратор молча ждёт ввода.
	if [ -n "$IB_USER" ]; then
		auth=",\"/N\",\"$IB_USER\""
		[ -n "$IB_PWD" ] && auth="$auth,\"/P\",\"$IB_PWD\""
	fi
	cat <<PSEOF
\$argv = @("DESIGNER","/F","$IB"${auth},"/DisableStartupDialogs"${args},"/Out","$log")
Remove-Item -LiteralPath "$log" -ErrorAction SilentlyContinue
\$proc = Start-Process -FilePath "$V8" -ArgumentList \$argv -Wait -PassThru -NoNewWindow
while (Get-Process -Name 1cv8 -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 300 }
"ExitCode=" + \$proc.ExitCode
if (Test-Path -LiteralPath "$log") { "LOG64:" + [Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$log")) }
PSEOF
}

show_log() {
	printf '%s\n' "$1" | grep -v '^LOG64:' || true
	printf '%s\n' "$1" | grep '^LOG64:' | sed 's/^LOG64://' | base64 -d || true
}

# Путь на маке -> путь, по которому его видит VM через общую папку Parallels.
to_win() {
	python3 -c 'import sys,os;p=os.path.abspath(sys.argv[1]);h=os.path.expanduser("~")+"/";assert p.startswith(h),"путь должен быть внутри домашнего каталога";print("C:\\Mac\\Home\\"+p[len(h):].replace("/","\\"))' "$1"
}

CMD="${1:-}"; NAME="${2:-}"

case "$CMD" in
	build)
		[ -n "$NAME" ] || { echo "нужно имя обработки" >&2; exit 1; }
		show_log "$(run_ps "$(ps_1cv8 'C:\Temp\epf-build.log' \
			'/LoadExternalDataProcessorOrReportFromFiles' \
			"$PROJ_WIN\\epf\\$NAME\\src\\$NAME.xml" \
			"$PROJ_WIN\\epf\\$NAME\\$NAME.epf")")"
		ls -la "$PROJ_MAC/epf/$NAME/$NAME.epf"
		;;
	check)
		[ -n "$NAME" ] || { echo "нужно имя обработки" >&2; exit 1; }
		show_log "$(run_ps "$(ps_1cv8 'C:\Temp\epf-check.log' \
			'/CheckModules' '-ExternalDataProcessorOrReport' "$PROJ_WIN\\epf\\$NAME\\$NAME.epf" \
			'-ThinClient' '-Server')")"
		;;
	dump)
		DEST="${3:-}"
		[ -n "$NAME" ] && [ -n "$DEST" ] || { echo "использование: dump <путь к .epf> <каталог назначения>" >&2; exit 1; }
		mkdir -p "$DEST"
		show_log "$(run_ps "$(ps_1cv8 'C:\Temp\epf-dump.log' \
			'/DumpExternalDataProcessorOrReportToFiles' "$(to_win "$DEST")" "$(to_win "$NAME")" \
			'-Format' 'Hierarchical')")"
		find "$DEST" -type f | sort
		;;
	*)
		sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's|^# \?||'
		exit 1
		;;
esac
