#!/bin/bash
# Обёртка над scripts/epf-vm.ps1: выполняет его в Windows-VM по ssh платформой 8.3.27 (ibcmd).
# База видна из VM через общую папку Parallels; пока идёт сборка, с мака её не открывать.
#
#   scripts/epf-vm.sh build <ИмяОбработки>   — epf/<Имя>/src -> epf/<Имя>/<Имя>.epf
#   scripts/epf-vm.sh dump  <ИмяОбработки>   — epf/<Имя>/<Имя>.epf -> epf/<Имя>/src (затем git status)
#   scripts/epf-vm.sh probe                  — ibcmd, локаль и процессы 1cv8 в VM
#
# Синтаксис здесь не проверяется — это делает scripts/bsl-check.sh. Параметры VM — .v8-project.json → vm (в .gitignore).

set -euo pipefail

PROJ_MAC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(python3 "$PROJ_MAC/scripts/vmconf.py" "$PROJ_MAC/.v8-project.json")"

run_vm() {
	local args=""
	for a in "$@"; do args="$args '$a'"; done
	ssh "$SSH_HOST" "pwsh -NoProfile -File '$PROJ_WIN\\scripts\\epf-vm.ps1'$args; exit \$LASTEXITCODE" 2>&1 | tr -d '\r' | grep -v '^\s*$'
	return "${PIPESTATUS[0]}"
}

CMD="${1:-}"; NAME="${2:-}"
case "$CMD" in
	build)
		[ -n "$NAME" ] || { echo "нужно имя обработки" >&2; exit 1; }
		run_vm build "$NAME"
		ls -la "$PROJ_MAC/epf/$NAME/$NAME.epf"
		;;
	dump)
		[ -n "$NAME" ] || { echo "нужно имя обработки" >&2; exit 1; }
		run_vm dump "$NAME"
		git -C "$PROJ_MAC" -c core.quotepath=false status --short "epf/$NAME/src"
		;;
	probe)
		run_vm probe
		;;
	*)
		sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's|^# \?||'
		exit 1
		;;
esac
