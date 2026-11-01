$ErrorActionPreference = 'Stop'
$localDir = Join-Path $PSScriptRoot '.local'
$credentialFile = Join-Path $localDir 'credentials.json'
if (Test-Path -LiteralPath $credentialFile) { throw 'Credentials already exist. Back them up and update locally instead of silently overwriting.' }
$appId = Read-Host 'QQ Bot AppID'
if ($appId -notmatch '^\d+$') { throw 'AppID must contain digits only.' }
$secureSecret = Read-Host 'QQ Bot AppSecret (hidden)' -AsSecureString
$secret = [System.Net.NetworkCredential]::new('', $secureSecret).Password
if ([string]::IsNullOrWhiteSpace($secret)) { throw 'AppSecret is empty.' }
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
$json = @{appId=$appId; appSecret=$secret} | ConvertTo-Json
[System.IO.File]::WriteAllText($credentialFile, $json, [System.Text.UTF8Encoding]::new($false))
if (!(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'persona.md'))) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'persona.example.md') -Destination (Join-Path $PSScriptRoot 'persona.md')
}
$secret = $null; $json = $null
Write-Output 'Saved local credentials. Run: node ./pair.mjs'
