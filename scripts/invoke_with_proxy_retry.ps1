[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Command,

  [string]$Proxy = "http://127.0.0.1:7890",

  [int]$MaxProxyRetries = 1,

  [switch]$ForceProxyRetry
)

$ErrorActionPreference = "Stop"

function Invoke-CommandWithCapture {
  param(
    [Parameter(Mandatory = $true)][string]$CommandText
  )

  Write-Host "`n>>> $CommandText" -ForegroundColor Cyan

  $output = @()
  try {
    $output = Invoke-Expression "$CommandText 2>&1" | Tee-Object -Variable captured
    $exitCode = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }
  } catch {
    $captured = @($_.Exception.Message)
    $exitCode = 1
  }

  $allText = (($captured | ForEach-Object { "$_" }) -join "`n")
  return [PSCustomObject]@{
    ExitCode = $exitCode
    Output   = $allText
  }
}

function Test-NetworkFailure {
  param([string]$Text)

  if (-not $Text) { return $false }

  $patterns = @(
    'Failed to connect',
    'Connection timed out',
    'timed out',
    'ECONNRESET',
    'ETIMEDOUT',
    'ENOTFOUND',
    'EAI_AGAIN',
    'TLS handshake timeout',
    'unable to access',
    'Could not resolve host',
    'proxy',
    'SSL_ERROR_SYSCALL',
    'Connection reset'
  )

  foreach ($pattern in $patterns) {
    if ($Text -match [Regex]::Escape($pattern)) {
      return $true
    }
  }

  return $false
}

function Get-ProxiedCommand {
  param(
    [string]$CommandText,
    [string]$ProxyUrl
  )

  if ($CommandText -match '^\s*git\s+') {
    return ($CommandText -replace '^\s*git\s+', "git -c http.proxy=$ProxyUrl -c https.proxy=$ProxyUrl ")
  }

  return $CommandText
}

function Invoke-WithTemporaryProxy {
  param(
    [string]$CommandText,
    [string]$ProxyUrl
  )

  $envKeys = @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy')
  $backup = @{}

  foreach ($key in $envKeys) {
    $backup[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
    [Environment]::SetEnvironmentVariable($key, $ProxyUrl, 'Process')
  }

  try {
    $proxied = Get-ProxiedCommand -CommandText $CommandText -ProxyUrl $ProxyUrl
    return Invoke-CommandWithCapture -CommandText $proxied
  } finally {
    foreach ($key in $envKeys) {
      [Environment]::SetEnvironmentVariable($key, $backup[$key], 'Process')
    }
  }
}

Write-Host "Running command without proxy..." -ForegroundColor Yellow
$first = Invoke-CommandWithCapture -CommandText $Command

if ($first.ExitCode -eq 0) {
  Write-Host "Command succeeded without proxy." -ForegroundColor Green
  exit 0
}

$shouldRetry = $ForceProxyRetry -or (Test-NetworkFailure -Text $first.Output)
if (-not $shouldRetry) {
  Write-Host "Command failed, but output did not match network-failure patterns. Skip proxy retry." -ForegroundColor Red
  exit $first.ExitCode
}

for ($i = 1; $i -le [Math]::Max(1, $MaxProxyRetries); $i++) {
  Write-Host "`nRetry with temporary proxy ($i/$MaxProxyRetries): $Proxy" -ForegroundColor Yellow
  $retry = Invoke-WithTemporaryProxy -CommandText $Command -ProxyUrl $Proxy

  if ($retry.ExitCode -eq 0) {
    Write-Host "Command succeeded with temporary proxy." -ForegroundColor Green
    exit 0
  }
}

Write-Host "Command still failed after proxy retries." -ForegroundColor Red
exit 1
