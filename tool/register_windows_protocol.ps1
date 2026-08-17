param(
    [switch]$Unregister,
    [string]$Executable
)

$ErrorActionPreference = "Stop"
$protocolKey = "HKCU:\Software\Classes\minigame"

if ($Unregister) {
    if (Test-Path $protocolKey) {
        Remove-Item $protocolKey -Recurse -Force
    }
    Write-Host "Unregistered minigame:// protocol"
    exit 0
}

if (-not $Executable) {
    $Executable = Join-Path $PSScriptRoot "..\build\windows\x64\runner\Debug\minigameapp.exe"
}
$Executable = [System.IO.Path]::GetFullPath($Executable)
if (-not (Test-Path $Executable -PathType Leaf)) {
    throw "Flutter Windows executable not found: $Executable. Build it first or pass -Executable."
}

if (-not (Test-Path $protocolKey)) {
    New-Item $protocolKey -Force | Out-Null
}
Set-Item $protocolKey -Value "URL:MiniGame Protocol"
New-ItemProperty $protocolKey -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null
New-Item "$protocolKey\DefaultIcon" -Force | Out-Null
Set-Item "$protocolKey\DefaultIcon" -Value "`"$Executable`",0"
New-Item "$protocolKey\shell\open\command" -Force | Out-Null
Set-Item "$protocolKey\shell\open\command" -Value "`"$Executable`" `"%1`""

Write-Host "Registered minigame:// protocol"
Write-Host "Executable: $Executable"
Write-Host "Test: Start-Process 'minigame://auth/callback?token=test'"
