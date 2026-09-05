# 检查是否以管理员身份运行
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "正在调起管理员权限弹窗..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$oldFlutter = "E:\sdk\flutter\bin"
$newFlutter = "E:\sdk\flutter-3.47.0-active\bin"

$currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
$parts = $currentPath -split ';' | Where-Object { $_ -and ($_ -ne $oldFlutter) }

if ($parts -notcontains $newFlutter) {
    $parts += $newFlutter
}

$updatedPath = $parts -join ';'
[Environment]::SetEnvironmentVariable("PATH", $updatedPath, "Machine")

Write-Host "==================================================" -ForegroundColor Green
Write-Host " 成功！系统 PATH 已更新！" -ForegroundColor Green
Write-Host " 已移除: $oldFlutter" -ForegroundColor Cyan
Write-Host " 已添加: $newFlutter" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host "请关闭当前所有终端窗口，重新打开终端后即可生效！" -ForegroundColor Yellow
