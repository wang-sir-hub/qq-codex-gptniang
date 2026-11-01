param([switch]$ValidateOnly, [string]$ProxyUrl)
$ErrorActionPreference = 'Stop'
$localDir = Join-Path $PSScriptRoot '.local'
$credentials = Get-Content -LiteralPath (Join-Path $localDir 'credentials.json') -Raw | ConvertFrom-Json
$owner = Get-Content -LiteralPath (Join-Path $localDir 'owner.json') -Raw | ConvertFrom-Json
if ($credentials.appId -notmatch '^\d+$' -or [string]::IsNullOrWhiteSpace($credentials.appSecret)) { throw 'Invalid credentials. Run setup.ps1 first.' }
if ($owner.ownerOpenId -notmatch '^[A-Za-z0-9_-]+$') { throw 'Owner pairing missing or invalid.' }
$env:QQ_BOT_APP_ID = [string]$credentials.appId
$env:QQ_BOT_APP_SECRET = [string]$credentials.appSecret
$env:QQ_BOT_OWNER_OPENID = [string]$owner.ownerOpenId
if ($ProxyUrl) {
    $proxy = [uri]$ProxyUrl
    if ($proxy.Scheme -notin @('http','https') -or $proxy.UserInfo) { throw 'Use an HTTP(S) proxy URL without embedded credentials.' }
    $env:HTTP_PROXY = $ProxyUrl; $env:HTTPS_PROXY = $ProxyUrl; $env:ALL_PROXY = $ProxyUrl
}
$codex = Get-Command codex -ErrorAction Stop
$bridge = Join-Path $PSScriptRoot 'bin\cc-connect.exe'
if (!(Test-Path -LiteralPath $bridge)) { throw 'Download cc-connect from upstream and save as bin/cc-connect.exe.' }
$personaPath = Join-Path $PSScriptRoot 'persona.md'
if (!(Test-Path -LiteralPath $personaPath)) { throw 'Copy persona.example.md to persona.md first.' }
$persona = [System.IO.File]::ReadAllText($personaPath)
if ($persona.Contains("'''")) { throw 'Persona cannot contain triple single quotes.' }
$cmdArgs = @($codex.Source, '--disable', 'shell_tool', '--disable', 'multi_agent', '-c', 'web_search="disabled"', '-c', 'apps._default.enabled=false', '-c', 'history.persistence="none"')
$codexConfig = if ($env:CODEX_HOME) { Join-Path $env:CODEX_HOME 'config.toml' } else { Join-Path $env:USERPROFILE '.codex\config.toml' }
if (Test-Path -LiteralPath $codexConfig) {
    foreach ($line in [System.IO.File]::ReadAllLines($codexConfig)) {
        if ($line -match '^\[(plugins\."[^"]+"|mcp_servers\.[A-Za-z0-9_-]+)\]\s*$') {
            $cmdArgs += @('-c', ($Matches[1] + '.enabled=false'))
        }
    }
}
$workspace = Join-Path $localDir 'workspace'
New-Item -ItemType Directory -Path $workspace -Force | Out-Null
$template = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'config.example.toml'))
$hash = [System.Security.Cryptography.SHA256]::Create()
try { $fingerprint = ([System.BitConverter]::ToString($hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($persona + $template)))).Replace('-','').Substring(0,12) } finally { $hash.Dispose() }
$state = (Join-Path $localDir ('state-' + $fingerprint)).Replace('\','/')
$rendered = $template.Replace('__STATE_DIR__',$state).Replace('__WORKSPACE__',$workspace.Replace('\','/')).Replace('__CODEX_COMMAND__',(ConvertTo-Json -InputObject $cmdArgs -Compress)).Replace('__PERSONA__',$persona)
$runtime = Join-Path $localDir 'runtime.toml'
[System.IO.File]::WriteAllText($runtime,$rendered,[System.Text.UTF8Encoding]::new($false))
if ($ValidateOnly) { Write-Output 'Runtime configuration rendered; no QQ connection started.'; return }
Push-Location -LiteralPath $PSScriptRoot
try { & $bridge --config $runtime; $bridgeExit = $LASTEXITCODE } finally { Pop-Location }
exit $bridgeExit
