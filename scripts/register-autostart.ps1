param(
    [string]$TaskName = 'Flip5DisplayProfile',
    [string]$WatchPath = (Join-Path $PSScriptRoot 'flip5-display-profile.ps1')
)

# 重建"插拔外接屏自动切档"的开机任务。watcher 脚本丢失时从本目录副本补回。
$Self = Join-Path $PSScriptRoot 'flip5-display-profile.ps1'

if (-not (Test-Path $WatchPath)) {
    if (Test-Path $Self) {
        Copy-Item $Self $WatchPath -Force
        Write-Host "watcher 缺失，已从副本恢复到 $WatchPath"
    } else {
        Write-Host "找不到 watcher：$WatchPath 和 $Self 都不存在"; exit 1
    }
}

$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $WatchPath + '"'
)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description 'Flip5 内屏/外接屏插拔自动切档 watcher' -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Start-Sleep 5
$t = Get-ScheduledTask -TaskName $TaskName
Write-Host ("任务 {0} 状态 = {1}" -f $t.TaskName, $t.State)
Write-Host '撤销：Unregister-ScheduledTask -TaskName ' $TaskName ' -Confirm:$false'
