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

$parameters = @{}
foreach ($entry in $PSBoundParameters.GetEnumerator()) {
  $parameters[$entry.Key] = $entry.Value
}
if (-not $parameters.ContainsKey("Action")) {
  $parameters["Action"] = $Action
}

& (Join-Path $PSScriptRoot "start-lan.ps1") @parameters
