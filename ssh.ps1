param([ValidateSet('setup','stop','help')][string]$Action = 'setup')
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
if ($args.Count) { throw 'Too many arguments' }
if ($Action -eq 'help') {
    Write-Host 'Usage: .\ssh.ps1 [setup|stop|help] (Administrator PowerShell)'
    Write-Host 'Setup starts Windows OpenSSH with Private / LocalSubnet firewall access only.'
    Write-Host 'No auto-start, network profile changes, passwords, or authorized keys are configured.'
    return
}
if ($env:OS -ne 'Windows_NT') { throw 'This script requires Windows.' }
$groups = whoami.exe /groups
if ($LASTEXITCODE -or ($groups -join "`n") -notmatch 'S-1-16-(12288|16384)\b') {
    throw 'Open PowerShell as Administrator, then run this script again.'
}
$ruleName = 'OpenSSH-Server-In-TCP'
if ($Action -eq 'stop') {
    if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) {
        Disable-NetFirewallRule -Name $ruleName | Out-Null
    }
    if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
        Stop-Service -Name sshd
    }
    Write-Host 'SSH stopped; its standard inbound firewall rule is disabled.'
    return
}
$capabilityName = 'OpenSSH.Server~~~~0.0.1.0'
$capability = Get-WindowsCapability -Online -Name $capabilityName
if ($capability.State -ne 'Installed') {
    Write-Host 'Installing Windows OpenSSH Server (may require internet access)...'
    $result = Add-WindowsCapability -Online -Name $capabilityName
    if ($result.RestartNeeded) { throw 'Restart Windows, then run this script again.' }
    if ((Get-WindowsCapability -Online -Name $capabilityName).State -ne 'Installed') {
        throw 'OpenSSH Server installation did not complete.'
    }
}
# Restrict the standard rule before starting the service. Never enable Public access.
if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) {
    Set-NetFirewallRule -Name $ruleName -Enabled True -Direction Inbound `
        -Action Allow -Profile Private -RemoteAddress LocalSubnet | Out-Null
    Get-NetFirewallRule -Name $ruleName | Get-NetFirewallPortFilter | `
        Set-NetFirewallPortFilter -Protocol TCP -LocalPort 22 | Out-Null
} else {
    New-NetFirewallRule -Name $ruleName -DisplayName 'OpenSSH SSH Server' `
        -Enabled True -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 `
        -Profile Private -RemoteAddress LocalSubnet | Out-Null
}
Start-Service -Name sshd
if ((Get-Service -Name sshd).Status -ne 'Running') { throw 'SSH service is not running.' }
Write-Host 'SSH is running. Use USB tethering or the same trusted LAN.'
Write-Host 'Set ONLY that trusted connection to Private in Windows network settings.'
Write-Host 'No password or key was set. Phone authentication is still required.'
Write-Host 'Username:'
whoami.exe
Write-Host 'IPv4 addresses (choose the USB tethering / trusted LAN adapter):'
Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred | Where-Object {
    $_.IPAddress -ne '127.0.0.1'
} | Format-Table InterfaceAlias, IPAddress -AutoSize
Write-Host 'To stop access, run this script with: -Action stop'
