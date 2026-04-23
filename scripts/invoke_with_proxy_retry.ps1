[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Command,

  [string]$Proxy = "",

  [int]$MaxProxyRetries = 1,

  [switch]$ForceProxyRetry
)

$ErrorActionPreference = "Stop"

function Normalize-ProxyUrl {
  param([string]$Value)

  if (-not $Value) { return $null }
  $trimmed = $Value.Trim()
  if (-not $trimmed) { return $null }
  if ($trimmed -match '^[a-zA-Z][a-zA-Z0-9+\-.]*://') {
    return $trimmed
  }
  return "http://$trimmed"
}

function Get-ProxyFromEnvironment {
  $keys = @("HTTPS_PROXY","HTTP_PROXY","ALL_PROXY","https_proxy","http_proxy","all_proxy")
  $scopes = @("Process","User","Machine")
  foreach ($scope in $scopes) {
    foreach ($key in $keys) {
      $value = [Environment]::GetEnvironmentVariable($key, $scope)
      $normalized = Normalize-ProxyUrl -Value $value
      if ($normalized) {
        return [PSCustomObject]@{
          Proxy  = $normalized
          Source = "env:$scope/$key"
        }
      }
    }
  }
  return $null
}

function Get-ProxyFromWindowsInternetSettings {
  try {
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    $settings = Get-ItemProperty -Path $regPath -ErrorAction Stop
    if ($settings.ProxyEnable -ne 1) { return $null }
    $serverRaw = "$($settings.ProxyServer)".Trim()
    if (-not $serverRaw) { return $null }

    if ($serverRaw -match "=") {
      $pairs = $serverRaw.Split(";") | Where-Object { $_ -match "=" }
      $map = @{}
      foreach ($pair in $pairs) {
        $parts = $pair.Split("=", 2)
        if ($parts.Count -eq 2) {
          $map[$parts[0].Trim().ToLower()] = $parts[1].Trim()
        }
      }
      $candidate = $null
      foreach ($k in @("https","http","socks","socks5")) {
        if ($map.ContainsKey($k) -and $map[$k]) {
          $candidate = $map[$k]
          break
        }
      }
      $normalized = Normalize-ProxyUrl -Value $candidate
      if ($normalized) {
        return [PSCustomObject]@{
          Proxy  = $normalized
          Source = "wininet:ProxyServer"
        }
      }
      return $null
    }

    $normalizedFlat = Normalize-ProxyUrl -Value $serverRaw
    if ($normalizedFlat) {
      return [PSCustomObject]@{
        Proxy  = $normalizedFlat
        Source = "wininet:ProxyServer"
      }
    }
    return $null
  } catch {
    return $null
  }
}

function Resolve-PreferredProxy {
  param(
    [string]$ExplicitProxy
  )

  $explicitNormalized = Normalize-ProxyUrl -Value $ExplicitProxy
  if ($explicitNormalized) {
    return [PSCustomObject]@{
      Proxy  = $explicitNormalized
      Source = "arg:-Proxy"
    }
  }

  $fromEnv = Get-ProxyFromEnvironment
  if ($fromEnv) { return $fromEnv }

  $fromSystem = Get-ProxyFromWindowsInternetSettings
  if ($fromSystem) { return $fromSystem }

  return [PSCustomObject]@{
    Proxy  = "http://127.0.0.1:7890"
    Source = "fallback:default"
  }
}

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

$proxySelection = Resolve-PreferredProxy -ExplicitProxy $Proxy
$effectiveProxy = $proxySelection.Proxy
Write-Host ("Proxy selection: {0} ({1})" -f $effectiveProxy, $proxySelection.Source) -ForegroundColor DarkCyan

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
  Write-Host "`nRetry with temporary proxy ($i/$MaxProxyRetries): $effectiveProxy" -ForegroundColor Yellow
  $retry = Invoke-WithTemporaryProxy -CommandText $Command -ProxyUrl $effectiveProxy

  if ($retry.ExitCode -eq 0) {
    Write-Host "Command succeeded with temporary proxy." -ForegroundColor Green
    exit 0
  }
}

Write-Host "Command still failed after proxy retries." -ForegroundColor Red
exit 1
