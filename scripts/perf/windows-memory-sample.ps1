param(
  [int]$RootPid = 0,
  [string]$ProcessName = 'gotoim_flutter',
  [int]$IntervalSeconds = 5,
  [int]$Count = 1,
  [string]$OutputPrefix = 'windows-memory',
  [string]$Scenario = 'unspecified',
  [int]$Iteration = 1,
  [string]$WindowCount = '',
  [string]$Notes = ''
)
$ErrorActionPreference = 'Stop'
if ($Count -lt 1 -or $IntervalSeconds -lt 1) { throw 'Count and interval must be positive.' }
if ($RootPid -eq 0) {
  $processCandidates = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
  if ($processCandidates.Count -ne 1) { throw "Expected exactly one $ProcessName process; specify -RootPid." }
  $RootPid = $processCandidates[0].Id
}
$root = Get-Process -Id $RootPid -ErrorAction Stop
$rootStart = $root.StartTime.ToUniversalTime()
$summary = "$OutputPrefix-summary.csv"
$detail = "$OutputPrefix-processes.csv"
$mapping = "$OutputPrefix-initial-processes.csv"
$envFile = "$OutputPrefix-environment.txt"
$initial = @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, CreationDate)
$initial | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $mapping
@("timestamp=$((Get-Date).ToUniversalTime().ToString('o'))", "root_pid=$RootPid", "root_start_utc=$($rootStart.ToString('o'))", "root_path=$($root.Path)", "os=$([Environment]::OSVersion.VersionString)", "architecture=$env:PROCESSOR_ARCHITECTURE", 'Attribution uses live parent PID relationships; reparented or detached processes are not included. Initial system process mapping permits separate investigation. No command lines or window titles are recorded.') | Set-Content -Encoding UTF8 $envFile
for ($i = 0; $i -lt $Count; $i++) {
  $timestamp = (Get-Date).ToUniversalTime().ToString('o')
  $snapshot = @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, CreationDate)
  $currentRoot = @( $snapshot | Where-Object { $_.ProcessId -eq $RootPid } )
  if ($currentRoot.Count -ne 1 -or [math]::Abs(($currentRoot[0].CreationDate.ToUniversalTime() - $rootStart).TotalMilliseconds) -gt 2) { throw 'Root process exited or PID was reused.' }
  $ids = @{}; $ids[$RootPid] = $true
  do {
    $added = $false
    foreach ($p in $snapshot) {
      if ($ids.ContainsKey([int]$p.ParentProcessId) -and -not $ids.ContainsKey([int]$p.ProcessId)) {
        $ids[[int]$p.ProcessId] = $true; $added = $true
      }
    }
  } while ($added)
  $rows = @(); $missing = 0
  foreach ($p in $snapshot | Where-Object { $ids.ContainsKey([int]$_.ProcessId) }) {
    try {
      $proc = Get-Process -Id $p.ProcessId -ErrorAction Stop
      if ([math]::Abs(($proc.StartTime.ToUniversalTime() - $p.CreationDate.ToUniversalTime()).TotalMilliseconds) -gt 2) { throw 'PID reused' }
      $rows += [pscustomobject]@{ timestamp=$timestamp; root_pid=$RootPid; pid=$p.ProcessId; parent_pid=$p.ParentProcessId; name=$p.Name; private_mb=[math]::Round($proc.PrivateMemorySize64 / 1MB, 2); working_set_mb=[math]::Round($proc.WorkingSet64 / 1MB, 2) }
    } catch { $missing++ }
  }
  if ($rows.Count) { $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Append -Path $detail }
  $private = ($rows | Measure-Object private_mb -Sum).Sum
  $working = ($rows | Measure-Object working_set_mb -Sum).Sum
  $web = @($rows | Where-Object { $_.name -eq 'msedgewebview2.exe' })
  $webPrivate = if ($web.Count) { ($web | Measure-Object private_mb -Sum).Sum } else { $null }
  [pscustomobject]@{scenario=$Scenario; iteration=$Iteration; timestamp=$timestamp; root_pid=$RootPid; window_count=$WindowCount; process_count=$rows.Count; private_mb=[math]::Round($private,2); working_set_mb=[math]::Round($working,2); webview_private_mb=$webPrivate; dart_heap_mb=''; notes="$Notes; missing_processes=$missing; WebView blank means no attributed process, not proof of zero"} | Export-Csv -NoTypeInformation -Encoding UTF8 -Append -Path $summary
  if ($i -lt $Count - 1) { Start-Sleep -Seconds $IntervalSeconds }
}
