[CmdletBinding()]
param(
  [ValidateSet("start", "status", "stop", "restart", "firewall")]
  [string]$Action = "start",
  [string]$HostAddress,
  [string]$InterfaceAlias,
  [int]$ApiPort = 0,
  [int]$WebPort = 0,
  [switch]$LocalOnly,
  [switch]$SkipFirewall,
  [switch]$AllowPublicProfile
)

$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$ApiDir = Join-Path $RootDir "apps\api"
$WebDir = Join-Path $RootDir "apps\web"
$LogDir = Join-Path $RootDir ".logs\lan"
$PidDir = Join-Path $LogDir "pids"
$RunFile = Join-Path $LogDir "run.json"
$UvicornBin = Join-Path $ApiDir ".venv\Scripts\uvicorn.exe"
$BilinBin = Join-Path $ApiDir ".venv\Scripts\bilin.exe"

function Get-PortFromEnv {
  param([string]$Name, [int]$Fallback)
  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $Fallback
  }

  $parsed = 0
  if ([int]::TryParse($value, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 65535) {
    return $parsed
  }

  throw "$Name must be a TCP port between 1 and 65535."
}

function Test-PrivateIPv4 {
  param([string]$Address)
  try {
    $ip = [Net.IPAddress]::Parse($Address)
  } catch {
    return $false
  }
  if ($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    return $false
  }

  $bytes = $ip.GetAddressBytes()
  return (
    $bytes[0] -eq 10 -or
    ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
    ($bytes[0] -eq 192 -and $bytes[1] -eq 168)
  )
}

function Test-TcpBind {
  param([string]$Address, [int]$Port)
  $listener = $null
  try {
    $ip = [Net.IPAddress]::Parse($Address)
    $listener = [Net.Sockets.TcpListener]::new($ip, $Port)
    $listener.Start()
    return $true
  } catch {
    return $false
  } finally {
    if ($listener) {
      $listener.Stop()
    }
  }
}

function Resolve-WebPort {
  param([string]$Address, [int]$RequestedPort, [bool]$Explicit)
  if ((Test-HttpOk "http://${Address}:$RequestedPort") -or (Test-TcpBind -Address $Address -Port $RequestedPort)) {
    return $RequestedPort
  }
  if ($Explicit) {
    throw "Web port $RequestedPort is not available on $Address."
  }

  foreach ($candidate in @($RequestedPort, 4173, 6173, 7173, 8173, 9173, 10173, 12173, 15173)) {
    if ($candidate -eq $RequestedPort) {
      continue
    }
    if ((Test-HttpOk "http://${Address}:$candidate") -or (Test-TcpBind -Address $Address -Port $candidate)) {
      Write-Warning "Web port $RequestedPort is not available on $Address. Using $candidate instead."
      return $candidate
    }
  }
  throw "No usable web port found for $Address."
}

function ConvertTo-NetworkCidr {
  param([string]$Address, [int]$PrefixLength)
  if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) {
    throw "Invalid IPv4 prefix length: $PrefixLength"
  }

  $addressBytes = ([Net.IPAddress]::Parse($Address)).GetAddressBytes()
  $networkBytes = @()
  for ($index = 0; $index -lt 4; $index += 1) {
    $remaining = $PrefixLength - ($index * 8)
    if ($remaining -ge 8) {
      $mask = 255
    } elseif ($remaining -le 0) {
      $mask = 0
    } else {
      $mask = 256 - [int][Math]::Pow(2, 8 - $remaining)
    }
    $networkBytes += ($addressBytes[$index] -band $mask)
  }

  return "$($networkBytes -join ".")/$PrefixLength"
}

function Get-LanEndpoint {
  param([string]$RequestedAddress, [string]$RequestedInterfaceAlias)

  $ipInterfaceByIndex = @{}
  Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
    $ipInterfaceByIndex[$_.InterfaceIndex] = $_
  }

  $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {
    $_.IPAddress -and
    $_.IPAddress -notlike "127.*" -and
    $_.IPAddress -notlike "169.254.*" -and
    -not $_.SkipAsSource -and
    (Test-PrivateIPv4 $_.IPAddress)
  }

  $candidates = foreach ($address in $addresses) {
    $adapter = Get-NetAdapter -InterfaceIndex $address.InterfaceIndex -ErrorAction SilentlyContinue
    if ($adapter -and $adapter.Status -ne "Up") {
      continue
    }
    if ($RequestedInterfaceAlias -and $address.InterfaceAlias -ne $RequestedInterfaceAlias) {
      continue
    }

    $ipInterface = $ipInterfaceByIndex[$address.InterfaceIndex]
    $alias = [string]$address.InterfaceAlias
    $looksVirtual = $alias -match "(?i)vEthernet|WSL|Docker|VMware|VirtualBox|Loopback|Mihomo|Tailscale|ZeroTier|WireGuard|OpenVPN|Hyper-V|VPN"
    $hardware = $false
    if ($adapter) {
      $hardware = [bool]$adapter.HardwareInterface
    }

    [pscustomobject]@{
      IPAddress = [string]$address.IPAddress
      PrefixLength = [int]$address.PrefixLength
      InterfaceAlias = $alias
      InterfaceIndex = [int]$address.InterfaceIndex
      InterfaceMetric = if ($ipInterface) { [int]$ipInterface.InterfaceMetric } else { 9999 }
      HardwareScore = if ($hardware) { 0 } else { 1 }
      VirtualScore = if ($looksVirtual) { 1 } else { 0 }
      PrefixOriginScore = if ($address.PrefixOrigin -in @("Dhcp", "Manual")) { 0 } else { 1 }
    }
  }

  if ($RequestedAddress) {
    if (-not (Test-PrivateIPv4 $RequestedAddress)) {
      throw "HostAddress must be an RFC1918 private IPv4 address."
    }
    $matched = $candidates | Where-Object { $_.IPAddress -eq $RequestedAddress } | Select-Object -First 1
    if ($matched) {
      return $matched
    }
    throw "HostAddress $RequestedAddress was not found on an active private LAN interface."
  }

  $chosen = $candidates |
    Sort-Object VirtualScore, HardwareScore, PrefixOriginScore, InterfaceMetric, @{ Expression = "PrefixLength"; Descending = $true } |
    Select-Object -First 1

  if (-not $chosen) {
    throw "No active RFC1918 LAN IPv4 address was found. Pass -HostAddress or -InterfaceAlias if this machine uses a non-standard network."
  }

  return $chosen
}

function Test-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-ApiToken {
  $bytes = [byte[]]::new(32)
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($bytes)
  } finally {
    $rng.Dispose()
  }
  return [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function Read-RunState {
  if (-not (Test-Path $RunFile)) {
    return $null
  }
  try {
    return Get-Content -Path $RunFile -Raw | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Write-RunState {
  param(
    [string]$Mode,
    [string]$HostAddress,
    [int]$ApiPortValue,
    [int]$WebPortValue,
    [string]$ApiTokenValue
  )

  [pscustomobject]@{
    mode = $Mode
    host = $HostAddress
    apiPort = $ApiPortValue
    webPort = $WebPortValue
    apiToken = $ApiTokenValue
    updatedAt = [DateTimeOffset]::UtcNow.ToString("o")
  } | ConvertTo-Json | Set-Content -Path $RunFile -Encoding UTF8
}

function Test-MatchingRunState {
  param([object]$State, [string]$Mode, [string]$HostAddress)
  return (
    $State -and
    $State.mode -eq $Mode -and
    $State.host -eq $HostAddress -and
    [int]$State.apiPort -eq $ApiPort -and
    [int]$State.webPort -eq $WebPort -and
    -not [string]::IsNullOrWhiteSpace([string]$State.apiToken)
  )
}

function Ensure-LanFirewallRules {
  param(
    [object]$Endpoint,
    [string]$NetworkCidr,
    [int[]]$Ports,
    [switch]$IncludePublicProfile
  )

  if (-not (Test-Administrator)) {
    throw "LAN firewall rules require an elevated PowerShell. Re-run as administrator, or pass -SkipFirewall only if you have already restricted inbound access."
  }

  $profile = Get-NetConnectionProfile -InterfaceIndex $Endpoint.InterfaceIndex -ErrorAction SilentlyContinue
  if ($profile -and $profile.NetworkCategory -eq "Public" -and -not $IncludePublicProfile) {
    Write-Warning "The selected network profile is Public. The default firewall rules target Private/Domain only. Set the network to Private or pass -AllowPublicProfile deliberately."
  }

  $profiles = if ($IncludePublicProfile) { @("Any") } else { @("Private", "Domain") }
  foreach ($port in $Ports) {
    $ruleName = "Bilin-LAN-TCP-$port"
    Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule `
      -Name $ruleName `
      -DisplayName "Bilin LAN TCP $port" `
      -Direction Inbound `
      -Action Allow `
      -Protocol TCP `
      -LocalAddress $Endpoint.IPAddress `
      -LocalPort $port `
      -RemoteAddress $NetworkCidr `
      -Profile $profiles `
      -EdgeTraversalPolicy Block | Out-Null
  }
}

function Get-PnpmPath {
  $command = Get-Command "pnpm.cmd" -ErrorAction SilentlyContinue
  if (-not $command) {
    $command = Get-Command "pnpm" -ErrorAction Stop
  }
  return $command.Source
}

function Test-NodeExecutable {
  param([string]$NodePath)
  if (-not (Test-Path $NodePath)) {
    return $false
  }
  try {
    & $NodePath --version | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

function Get-NodeBinDir {
  $candidates = @()
  $configured = [Environment]::GetEnvironmentVariable("BILIN_NODE_BIN_DIR")
  if (-not [string]::IsNullOrWhiteSpace($configured)) {
    $candidates += $configured
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $candidates += (Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin")
  }
  foreach ($command in Get-Command "node.exe" -All -ErrorAction SilentlyContinue) {
    if ($command.Source) {
      $candidates += (Split-Path -Parent $command.Source)
    }
  }

  foreach ($candidate in ($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
    $nodePath = Join-Path $candidate "node.exe"
    if (Test-NodeExecutable $nodePath) {
      return $candidate
    }
  }

  throw "No usable node.exe found. Set BILIN_NODE_BIN_DIR to a Node.js bin directory."
}

function Get-WebEnvironment {
  param([string]$HostAddress, [string]$ApiBaseUrl)
  $nodeBinDir = Get-NodeBinDir
  return @{
    BILIN_DEV_HOST = $HostAddress
    BILIN_WEB_HOST = $HostAddress
    BILIN_WEB_PORT = [string]$WebPort
    BILIN_API_PORT = [string]$ApiPort
    VITE_BILIN_API_URL = $ApiBaseUrl
    Path = "$nodeBinDir;$env:Path"
  }
}

function Ensure-Runtime {
  if (-not (Test-Path $UvicornBin)) {
    throw "Missing $UvicornBin. Run backend setup before starting the development stack."
  }
  if (-not (Test-Path $BilinBin)) {
    throw "Missing $BilinBin. Run backend setup before starting the development stack."
  }
  if (-not (Test-Path (Join-Path $RootDir "node_modules"))) {
    throw "Missing root node_modules. Run pnpm install before starting LAN mode."
  }
  Get-PnpmPath | Out-Null
  Get-NodeBinDir | Out-Null
  New-Item -ItemType Directory -Force -Path $LogDir, $PidDir | Out-Null
}

function Get-PidFile {
  param([string]$Name)
  return Join-Path $PidDir "$Name.pid"
}

function Read-Pid {
  param([string]$Name)
  $path = Get-PidFile $Name
  if (-not (Test-Path $path)) {
    return 0
  }
  $raw = Get-Content -Path $path -TotalCount 1
  $pidValue = 0
  if ([int]::TryParse($raw, [ref]$pidValue)) {
    return $pidValue
  }
  return 0
}

function Test-PidAlive {
  param([int]$PidValue)
  if ($PidValue -le 0) {
    return $false
  }
  try {
    Get-Process -Id $PidValue -ErrorAction Stop | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Set-ProcessEnvironment {
  param([hashtable]$Environment)
  $previous = @{}
  foreach ($key in $Environment.Keys) {
    $previous[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
    [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], "Process")
  }
  return $previous
}

function Restore-ProcessEnvironment {
  param([hashtable]$Previous)
  foreach ($key in $Previous.Keys) {
    [Environment]::SetEnvironmentVariable($key, $Previous[$key], "Process")
  }
}

function Start-DetachedProcess {
  param(
    [string]$Name,
    [string]$WorkingDirectory,
    [string]$FilePath,
    [string[]]$Arguments,
    [hashtable]$Environment = @{}
  )

  $existingPid = Read-Pid $Name
  if (Test-PidAlive $existingPid) {
    Write-Host "$Name already running: pid $existingPid"
    return
  }

  $stdout = Join-Path $LogDir "$Name.out.log"
  $stderr = Join-Path $LogDir "$Name.err.log"
  $previous = Set-ProcessEnvironment $Environment
  try {
    $process = Start-Process `
      -FilePath $FilePath `
      -ArgumentList $Arguments `
      -WorkingDirectory $WorkingDirectory `
      -RedirectStandardOutput $stdout `
      -RedirectStandardError $stderr `
      -WindowStyle Hidden `
      -PassThru
  } finally {
    Restore-ProcessEnvironment $previous
  }

  Set-Content -Path (Get-PidFile $Name) -Value $process.Id
  Write-Host "$Name started: pid $($process.Id)"
}

function Test-HttpOk {
  param([string]$Url)
  try {
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method Get -TimeoutSec 2
    return ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 300)
  } catch {
    return $false
  }
}

function Wait-Http {
  param([string]$Name, [string]$Url)
  for ($index = 0; $index -lt 75; $index += 1) {
    if (Test-HttpOk $Url) {
      Write-Host "$Name ready: $Url"
      return
    }
    Start-Sleep -Milliseconds 200
  }
  throw "$Name did not become ready: $Url. Logs are in $LogDir."
}

function Stop-ByPidFile {
  param([string]$Name)
  $pidValue = Read-Pid $Name
  $pidFile = Get-PidFile $Name
  if (-not (Test-PidAlive $pidValue)) {
    Remove-Item -Path $pidFile -ErrorAction SilentlyContinue
    Write-Host "${Name}: not running"
    return
  }

  & taskkill.exe /PID $pidValue /T /F | Out-Null
  Start-Sleep -Milliseconds 400
  if (Test-PidAlive $pidValue) {
    Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -Path $pidFile -ErrorAction SilentlyContinue
  Write-Host "${Name}: stopped"
}

function Start-LanStack {
  param([object]$Endpoint, [string]$NetworkCidr)
  Ensure-Runtime

  $apiBaseUrl = "http://$($Endpoint.IPAddress):$ApiPort"
  $webUrl = "http://$($Endpoint.IPAddress):$WebPort"
  $runState = Read-RunState
  $matchingRun = Test-MatchingRunState -State $runState -Mode "lan" -HostAddress $Endpoint.IPAddress
  if (((Test-HttpOk "$apiBaseUrl/health") -or (Test-HttpOk $webUrl)) -and -not $matchingRun) {
    throw "A service is already reachable on the requested LAN endpoint, but it was not started by the matching Bilin LAN run. Stop it or run .\scripts\start.ps1 restart."
  }

  $apiToken = if ($matchingRun) { [string]$runState.apiToken } else { New-ApiToken }
  $allowedOrigins = @(
    $webUrl,
    "http://127.0.0.1:$WebPort",
    "http://localhost:$WebPort"
  ) -join ","

  if (Test-HttpOk "$apiBaseUrl/health") {
    Write-Host "api already running: $apiBaseUrl/health"
  } else {
    Start-DetachedProcess `
      -Name "api" `
      -WorkingDirectory $ApiDir `
      -FilePath $UvicornBin `
      -Arguments @("bilin_api.main:app", "--reload", "--host", $Endpoint.IPAddress, "--port", [string]$ApiPort) `
      -Environment @{
        BILIN_DEV_HOST = $Endpoint.IPAddress
        BILIN_API_PORT = [string]$ApiPort
        BILIN_API_TOKEN = $apiToken
        BILIN_ALLOWED_ORIGINS = $allowedOrigins
        BILIN_RESTRICT_PROVIDER_BASE_URLS = "1"
      }
    Wait-Http -Name "api" -Url "$apiBaseUrl/health"
  }

  Start-DetachedProcess `
    -Name "worker" `
    -WorkingDirectory $ApiDir `
    -FilePath $BilinBin `
    -Arguments @("jobs", "run-worker")

  if (Test-HttpOk $webUrl) {
    Write-Host "web already running: $webUrl"
  } else {
    Start-DetachedProcess `
      -Name "web" `
      -WorkingDirectory $RootDir `
      -FilePath (Get-PnpmPath) `
      -Arguments @("--dir", $WebDir, "dev", "--host", $Endpoint.IPAddress, "--port", [string]$WebPort) `
      -Environment (Get-WebEnvironment -HostAddress $Endpoint.IPAddress -ApiBaseUrl $apiBaseUrl)
    Wait-Http -Name "web" -Url $webUrl
  }

  if (-not $SkipFirewall) {
    Ensure-LanFirewallRules -Endpoint $Endpoint -NetworkCidr $NetworkCidr -Ports @($ApiPort, $WebPort) -IncludePublicProfile:$AllowPublicProfile
  }

  Write-RunState -Mode "lan" -HostAddress $Endpoint.IPAddress -ApiPortValue $ApiPort -WebPortValue $WebPort -ApiTokenValue $apiToken
  Write-Host "LAN web: $webUrl/?bilin_token=$apiToken"
  Write-Host "Allowed remote subnet: $NetworkCidr"
  Write-Host "Logs: $LogDir"
}

function Start-LocalStack {
  Ensure-Runtime

  $hostAddress = "127.0.0.1"
  $apiBaseUrl = "http://${hostAddress}:$ApiPort"
  if (Test-HttpOk "$apiBaseUrl/health") {
    Write-Host "api already running: $apiBaseUrl/health"
  } else {
    Start-DetachedProcess `
      -Name "api" `
      -WorkingDirectory $ApiDir `
      -FilePath $UvicornBin `
      -Arguments @("bilin_api.main:app", "--reload", "--host", $hostAddress, "--port", [string]$ApiPort) `
      -Environment @{
        BILIN_DEV_HOST = $hostAddress
        BILIN_API_PORT = [string]$ApiPort
        BILIN_ALLOW_LAN_ORIGINS = "0"
        BILIN_API_TOKEN = ""
        BILIN_ALLOWED_ORIGINS = ""
        BILIN_RESTRICT_PROVIDER_BASE_URLS = ""
      }
    Wait-Http -Name "api" -Url "$apiBaseUrl/health"
  }

  Start-DetachedProcess `
    -Name "worker" `
    -WorkingDirectory $ApiDir `
    -FilePath $BilinBin `
    -Arguments @("jobs", "run-worker")

  $webUrl = "http://${hostAddress}:$WebPort"
  if (Test-HttpOk $webUrl) {
    Write-Host "web already running: $webUrl"
  } else {
    Start-DetachedProcess `
      -Name "web" `
      -WorkingDirectory $RootDir `
      -FilePath (Get-PnpmPath) `
      -Arguments @("--dir", $WebDir, "dev", "--host", $hostAddress, "--port", [string]$WebPort) `
      -Environment (Get-WebEnvironment -HostAddress $hostAddress -ApiBaseUrl $apiBaseUrl)
    Wait-Http -Name "web" -Url $webUrl
  }

  Write-Host "Local web: $webUrl"
  Write-Host "LAN was not enabled for this run."
  Write-RunState -Mode "local" -HostAddress $hostAddress -ApiPortValue $ApiPort -WebPortValue $WebPort -ApiTokenValue ""
  Write-Host "Logs: $LogDir"
}

function Show-Status {
  param([object]$Endpoint)
  New-Item -ItemType Directory -Force -Path $LogDir, $PidDir | Out-Null
  $apiUrl = "http://$($Endpoint.IPAddress):$ApiPort/health"
  $webUrl = "http://$($Endpoint.IPAddress):$WebPort"
  if ($Endpoint.InterfaceAlias -eq "loopback") {
    Write-Host "mode: local only"
  } else {
    Write-Host "LAN interface: $($Endpoint.InterfaceAlias) $($Endpoint.IPAddress)/$($Endpoint.PrefixLength)"
  }
  Write-Host "api: $(if (Test-HttpOk $apiUrl) { "healthy $apiUrl" } else { "not reachable, pid $(Read-Pid "api")" })"
  Write-Host "web: $(if (Test-HttpOk $webUrl) { "healthy $webUrl" } else { "not reachable, pid $(Read-Pid "web")" })"
  Write-Host "worker: pid $(Read-Pid "worker")"
  Write-Host "logs: $LogDir"
}

$apiPortExplicit = $ApiPort -gt 0 -or -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("BILIN_API_PORT"))
$webPortExplicit = $WebPort -gt 0 -or -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("BILIN_WEB_PORT"))
$ApiPort = if ($ApiPort -gt 0) { $ApiPort } else { Get-PortFromEnv "BILIN_API_PORT" 8000 }
$WebPort = if ($WebPort -gt 0) { $WebPort } else { Get-PortFromEnv "BILIN_WEB_PORT" 5173 }
if ($ApiPort -gt 65535 -or $WebPort -gt 65535) {
  throw "Ports must be between 1 and 65535."
}

if ($Action -eq "stop") {
  Stop-ByPidFile "web"
  Stop-ByPidFile "worker"
  Stop-ByPidFile "api"
  Remove-Item -Path $RunFile -ErrorAction SilentlyContinue
  return
}

$localEndpoint = [pscustomobject]@{
  IPAddress = "127.0.0.1"
  PrefixLength = 8
  InterfaceAlias = "loopback"
  InterfaceIndex = 0
}

$mode = "lan"
$networkCidr = $null
if ($LocalOnly) {
  if ($Action -eq "firewall") {
    throw "Firewall setup is only meaningful in LAN mode."
  }
  $endpoint = $localEndpoint
  $mode = "local"
} else {
  try {
    $endpoint = Get-LanEndpoint -RequestedAddress $HostAddress -RequestedInterfaceAlias $InterfaceAlias
    $networkCidr = ConvertTo-NetworkCidr -Address $endpoint.IPAddress -PrefixLength $endpoint.PrefixLength
  } catch {
    if ($HostAddress -or $InterfaceAlias -or $Action -eq "firewall") {
      throw
    }
    Write-Warning "No active private LAN IPv4 address was detected. Falling back to local-only mode."
    $endpoint = $localEndpoint
    $mode = "local"
  }
}

if ($mode -eq "lan" -and -not $SkipFirewall -and -not (Test-Administrator)) {
  if ($HostAddress -or $InterfaceAlias -or $Action -eq "firewall") {
    throw "LAN firewall rules require an elevated PowerShell. Re-run as administrator, or pass -SkipFirewall only if you have already restricted inbound access."
  }
  Write-Warning "LAN was detected, but firewall rules require an elevated PowerShell. Falling back to local-only mode."
  $endpoint = $localEndpoint
  $mode = "local"
  $networkCidr = $null
}

if ($Action -eq "status") {
  $statusRunState = Read-RunState
  if ($statusRunState) {
    if (-not $apiPortExplicit -and $statusRunState.apiPort) {
      $ApiPort = [int]$statusRunState.apiPort
    }
    if (-not $webPortExplicit -and $statusRunState.webPort) {
      $WebPort = [int]$statusRunState.webPort
    }
    if ([string]$statusRunState.mode -eq "local") {
      $endpoint = $localEndpoint
      $mode = "local"
    }
  }
}

if ($Action -eq "start" -or $Action -eq "restart") {
  $WebPort = Resolve-WebPort -Address $endpoint.IPAddress -RequestedPort $WebPort -Explicit:$webPortExplicit
}

switch ($Action) {
  "status" {
    Show-Status -Endpoint $endpoint
  }
  "firewall" {
    Ensure-LanFirewallRules -Endpoint $endpoint -NetworkCidr $networkCidr -Ports @($ApiPort, $WebPort) -IncludePublicProfile:$AllowPublicProfile
    Write-Host "Firewall ready for $($endpoint.IPAddress) from $networkCidr on TCP $ApiPort,$WebPort."
  }
  "restart" {
    Stop-ByPidFile "web"
    Stop-ByPidFile "worker"
    Stop-ByPidFile "api"
    Remove-Item -Path $RunFile -ErrorAction SilentlyContinue
    if ($mode -eq "lan") {
      Start-LanStack -Endpoint $endpoint -NetworkCidr $networkCidr
    } else {
      Start-LocalStack
    }
  }
  default {
    if ($mode -eq "lan") {
      Start-LanStack -Endpoint $endpoint -NetworkCidr $networkCidr
    } else {
      Start-LocalStack
    }
  }
}
