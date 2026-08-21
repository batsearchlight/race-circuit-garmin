param(
    [string]$DeveloperKey = (Join-Path $PSScriptRoot "developer_key.der")
)

$ErrorActionPreference = "Stop"

$sdkConfig = Join-Path $env:APPDATA "Garmin\ConnectIQ\current-sdk.cfg"
if (-not (Test-Path -LiteralPath $sdkConfig)) {
    throw "Kein aktives Connect-IQ-SDK gefunden. Installiere zuerst den Garmin Connect IQ SDK Manager und aktiviere ein SDK."
}

$sdkPath = (Get-Content -Raw -LiteralPath $sdkConfig).Trim()
$compilerJar = Join-Path $sdkPath "bin\monkeybrains.jar"
if (-not (Test-Path -LiteralPath $compilerJar)) {
    throw "Der Monkey-C-Compiler wurde im aktiven SDK nicht gefunden: $sdkPath"
}

$java = Get-Command java -ErrorAction SilentlyContinue
if (-not $java) {
    throw "Java wurde nicht gefunden. Connect IQ SDK 9.2.0 benötigt eine Java-Laufzeitumgebung."
}

if (-not (Test-Path -LiteralPath $DeveloperKey)) {
    $openssl = Get-Command openssl -ErrorAction SilentlyContinue
    if (-not $openssl) {
        throw "Es fehlt ein Developer Key. Erzeuge ihn in VS Code über 'Monkey C: Generate a Developer Key' oder installiere OpenSSL."
    }

    $pemKey = Join-Path $PSScriptRoot "developer_key.pem"
    & $openssl.Source genrsa -out $pemKey 4096
    & $openssl.Source pkcs8 -topk8 -inform PEM -outform DER -in $pemKey -out $DeveloperKey -nocrypt
}

$outputDirectory = Join-Path $PSScriptRoot "bin"
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$outputFile = Join-Path $outputDirectory "RaceCircuit.prg"

& $java.Source `
    "-Xms1g" `
    "-Dfile.encoding=UTF-8" `
    "-Dapple.awt.UIElement=true" `
    "-Duser.home=$env:USERPROFILE" `
    -cp $compilerJar `
    com.garmin.monkeybrains.Monkeybrains `
    -d venu3 `
    -f (Join-Path $PSScriptRoot "monkey.jungle") `
    -o $outputFile `
    -y $DeveloperKey `
    -l 1

if ($LASTEXITCODE -ne 0) {
    throw "Der Build ist fehlgeschlagen (Exitcode $LASTEXITCODE)."
}

Write-Host "Fertig: $outputFile"
