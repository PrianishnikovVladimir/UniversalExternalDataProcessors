# Сборка и разбор внешних обработок платформой 8.3.27 в Windows-VM через ibcmd.
# Запускается из scripts/epf-vm.sh (ssh win pwsh -File ...), пригоден и для ручного запуска в VM.
#
#   epf-vm.ps1 build <Имя>    epf/<Имя>/src -> epf/<Имя>/<Имя>.epf   (ibcmd config import --out)
#   epf-vm.ps1 dump <Имя>     epf/<Имя>/<Имя>.epf -> epf/<Имя>/src   (ibcmd config export --file)
#   epf-vm.ps1 probe          состояние VM: ibcmd, локаль, процессы 1cv8 по сеансам
#
# Почему ibcmd, а не DESIGNER: он работает без окон, и занятая база даёт явную ошибку. Пакетный DESIGNER из ssh
# (сеанс 0, без рабочего стола) при открытом у пользователя конфигураторе виснет молча с пустым логом.
# Если в сеансе 1 открыт интерактивный 1cv8 — отказ: не запускаем и ничего не снимаем.
# Синтаксис EPF здесь не проверяется: /CheckModules -ExternalDataProcessorOrReport ничего не проверяет,
# ibcmd собирает и сломанные модули. Проверка — scripts/bsl-check.sh на маке.
param(
	[Parameter(Mandatory = $true)][string]$Cmd,
	[string]$Name = ''
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

$proj = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$cfg = (Get-Content (Join-Path $proj '.v8-project.json') -Raw -Encoding UTF8 | ConvertFrom-Json).vm
$ibcmd = Join-Path (Split-Path $cfg.v8) 'ibcmd.exe'
$tmp = 'C:\Temp\epf-vm'; New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# Аутентификация: пустой пароль не передаём вовсе — пустой аргумент съедает следующий ключ.
$auth = @()
if ($cfg.user) { $auth += "--user=$($cfg.user)"; if ($cfg.password) { $auth += "--password=$($cfg.password)" } }

function Ibcmd([string]$label, [string[]]$cmdArgs) {
	$sw = [Diagnostics.Stopwatch]::StartNew()
	$o = & $ibcmd @cmdArgs 2>&1
	$rc = $LASTEXITCODE
	Write-Host ("=== $label rc=$rc за $([int]$sw.Elapsed.TotalSeconds) с: " + (($o | Select-Object -Last 1) -join ''))
	if ($rc -ne 0) { $o | Select-Object -Last 8 | ForEach-Object { Write-Host $_ } }
	return $rc
}

if ($Cmd -eq 'probe') {
	Write-Host "ibcmd: $ibcmd -> $(Test-Path -LiteralPath $ibcmd)"
	Write-Host "локаль: $((Get-WinSystemLocale).Name)"
	Get-Process 1cv8, 1cv8c -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "$($_.ProcessName) pid=$($_.Id) сеанс=$($_.SessionId)" }
	exit 0
}

$s1 = @(Get-Process 1cv8 -ErrorAction SilentlyContinue | Where-Object SessionId -ne 0)
if ($s1) { Write-Host "СТОП: в VM открыт интерактивный 1cv8 (pid $($s1.Id -join ', ')) — закройте конфигуратор и повторите"; exit 2 }

if (-not $Name) { Write-Host 'нужно имя обработки'; exit 1 }
$src = Join-Path $cfg.projectWin "epf\$Name\src"
$epf = Join-Path $cfg.projectWin "epf\$Name\$Name.epf"

switch ($Cmd) {
	'build' {
		# Собираем во временный файл: запись .epf напрямую в общую папку Parallels иногда видна не сразу.
		$out = Join-Path $tmp "$Name.epf"; Remove-Item $out -ErrorAction SilentlyContinue
		$rc = Ibcmd "build $Name" (@('config', 'import', "--db-path=$($cfg.ib)") + $auth + @("--out=$out", $src))
		if ($rc -ne 0) { exit $rc }
		Copy-Item $out $epf -Force
		exit 0
	}
	'dump' {
		if (-not (Test-Path -LiteralPath $epf)) { Write-Host "нет файла $epf"; exit 1 }
		# Целевой путь у export — это имя корневого файла; без него корневой XML ляжет рядом с каталогом.
		$rootXml = Get-ChildItem -LiteralPath $src -Filter *.xml -File -ErrorAction SilentlyContinue | Select-Object -First 1
		$root = if ($rootXml) { $rootXml.BaseName } else { $Name }
		$rc = Ibcmd "dump $Name" (@('config', 'export', "--db-path=$($cfg.ib)") + $auth + @("--file=$epf", "$src\$root.xml"))
		exit $rc
	}
	default { Write-Host "неизвестная команда: $Cmd"; exit 1 }
}
