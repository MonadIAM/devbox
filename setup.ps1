$ErrorActionPreference = "Stop"

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-EnvFile {
    param([string]$Path)
    $result = @{}
    Get-Content $Path | Where-Object { $_ -match '=' } | ForEach-Object {
        $parts = $_ -split '=', 2
        $result[$parts[0].Trim()] = $parts[1].Trim()
    }
    return $result
}

function Require-ConfigValue {
    param(
        [hashtable]$Values,
        [string[]]$Names
    )
    foreach ($name in $Names) {
        if (-not $Values.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($Values[$name])) {
            throw "missing required config value: $name"
        }
    }
}

function Assert-WslSupportsModernConfig {
    $versionOutput = (& wsl --version) 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $versionOutput) {
        throw "wsl --version is not available; update WSL from Microsoft Store before running this script"
    }
}

function Test-DistroInstalled {
    param([string]$Distro)
    $installed = @((wsl -l -q) 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    return $installed -contains $Distro
}

function Wait-WslUser {
    param(
        [string]$Distro,
        [string]$LinuxUsername,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        (& wsl -d $Distro -u root id $LinuxUsername) >$null 2>$null
        if ($LASTEXITCODE -eq 0) {
            return
        }
        Start-Sleep -Seconds 5
    }

    throw "timed out waiting for Linux user '$LinuxUsername' in WSL distro '$Distro'"
}

function ConvertTo-PortList {
    param([string]$Csv)
    if ([string]::IsNullOrWhiteSpace($Csv)) {
        return @()
    }
    return $Csv -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

function New-RenderedFile {
    param(
        [string]$TemplatePath,
        [string]$OutputPath,
        [hashtable]$Values
    )
    $content = Get-Content $TemplatePath -Raw
    foreach ($key in $Values.Keys) {
        $content = $content -replace "__${key}__", $Values[$key]
    }
    Set-Content -Path $OutputPath -Value $content -NoNewline
}

function Register-FirewallRule {
    param(
        [string]$Name,
        [string]$Port,
        [string]$Profile
    )
    if (-not (Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $Name -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -Profile $Profile | Out-Null
    }
}

if (-not (Test-Admin)) {
    throw "run this script as Administrator"
}

$DevboxDir = $PSScriptRoot

$EnvFile = Join-Path $DevboxDir ".env"
if (-not (Test-Path $EnvFile)) {
    throw "missing $EnvFile (copy .env.example to .env and fill it in)"
}

$cfg = Read-EnvFile -Path $EnvFile
Require-ConfigValue -Values $cfg -Names @(
    "LINUX_USERNAME",
    "DISTRO",
    "WSL_DISK_SIZE",
    "WSL_PROCESSORS",
    "WSL_MEMORY",
    "WSL_SWAP",
    "WSL_USER_WAIT_TIMEOUT_SECONDS",
    "SSH_PORT",
    "EXPOSED_TCP_PORTS",
    "FIREWALL_PROFILE",
    "K3D_VERSION",
    "HELM_VERSION",
    "KUBECTL_VERSION"
)
$Distro = $cfg["DISTRO"]
$LinuxUsername = $cfg["LINUX_USERNAME"]
$SshPort = $cfg["SSH_PORT"]
$DiskSize = $cfg["WSL_DISK_SIZE"]
$ExposedPorts = ConvertTo-PortList -Csv $cfg["EXPOSED_TCP_PORTS"]
$FirewallProfile = $cfg["FIREWALL_PROFILE"]
$UserWaitTimeoutSeconds = [int]$cfg["WSL_USER_WAIT_TIMEOUT_SECONDS"]

Write-Host "[1/8] wsl --update"
wsl --update
Assert-WslSupportsModernConfig

Write-Host "[2/8] distro"
if (-not (Test-DistroInstalled -Distro $Distro)) {
    Write-Host "installing $Distro"
    wsl --install -d $Distro
    Write-Host "finish Linux user setup in the opened $Distro window"
    Wait-WslUser -Distro $Distro -LinuxUsername $LinuxUsername -TimeoutSeconds $UserWaitTimeoutSeconds
} else {
    Write-Host "$Distro already installed"
}

Write-Host "[3/8] disk size ($DiskSize)"
wsl --terminate $Distro
try {
    wsl --manage $Distro --resize $DiskSize
} catch {
    Write-Host "resize not supported by this wsl.exe version, skipping" -ForegroundColor Yellow
}

Write-Host "[4/8] .wslconfig"
$wslConfigTarget = Join-Path $env:USERPROFILE ".wslconfig"
if (Test-Path $wslConfigTarget) {
    Copy-Item $wslConfigTarget "$wslConfigTarget.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
}
New-RenderedFile -TemplatePath (Join-Path $DevboxDir ".wslconfig.template") -OutputPath $wslConfigTarget -Values $cfg
wsl --shutdown
Start-Sleep -Seconds 3

Write-Host "[5/8] wsl.conf"
$tmpWslConf = Join-Path $env:TEMP "monadiam-wsl.conf"
New-RenderedFile -TemplatePath (Join-Path $DevboxDir "wsl.conf.template") -OutputPath $tmpWslConf -Values $cfg
$wslTmpPath = (wsl -d $Distro wslpath -a ($tmpWslConf -replace '\\', '/')).Trim()
wsl -d $Distro -u root bash -c "cp '$wslTmpPath' /etc/wsl.conf"
wsl --terminate $Distro
Start-Sleep -Seconds 2
wsl -d $Distro -- true | Out-Null

Write-Host "[6/8] provisioning"
$wslDevboxPath = (wsl -d $Distro wslpath -a ($DevboxDir -replace '\\', '/')).Trim()
wsl -d $Distro -u root bash -c "bash '$wslDevboxPath/provision.sh'"

Write-Host "[7/8] firewall rules"
Register-FirewallRule -Name "WSL2 SSH ($Distro)" -Port $SshPort -Profile $FirewallProfile
foreach ($port in $ExposedPorts) {
    Register-FirewallRule -Name "WSL2 devbox ($Distro, $port)" -Port $port -Profile $FirewallProfile
}

Write-Host "[8/8] done"
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } |
    Select-Object InterfaceAlias, IPAddress | Format-Table -AutoSize

Write-Host "SSH from Mac:"
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } |
    ForEach-Object { Write-Host "ssh -p $SshPort $LinuxUsername@$($_.IPAddress)" }
