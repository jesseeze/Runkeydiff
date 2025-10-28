function Read-KeyValues {
    param ([string]$KeyPath)
    $h = @{}
    try {
        $item = Get-ItemProperty -Path $KeyPath -ErrorAction Stop
        foreach ($prop in $item.PSObject.Properties) {
            if ($prop.Name -match '^PS') { continue }
            $h[$prop.Name] = $prop.Value
        }
    } catch {
        Write-Host "Warning: Cannot read key $KeyPath" -ForegroundColor Yellow
    }
    return $h
}

function Get-RunKeySnapshot {
    $paths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    )
    $snapshot = @{}
    foreach ($path in $paths) {
        $values = Read-KeyValues -KeyPath $path
        Write-Host "`n[+] Registry values in $($path):`n" -ForegroundColor Cyan
        if ($values.Count -gt 0) {
            $values.GetEnumerator() | Format-Table Name, Value -AutoSize
        } else {
            Write-Host "(no values)" -ForegroundColor DarkGray
        }
        $snapshot[$path] = $values
    }
    return $snapshot
}

function Run-ObservedProcess {
    param ([string]$ProcessPath)
    try {
        $proc = Start-Process -FilePath $ProcessPath -PassThru -ErrorAction Stop
        Write-Host "`n[+] Process started: $ProcessPath (PID: $($proc.Id))" -ForegroundColor Green
        return $proc
    } catch {
        Write-Host "`n[!] Error starting process: $_" -ForegroundColor Red
        return $null
    }
}

function Stop-ObservedProcess {
    param ([System.Diagnostics.Process]$Proc)
    if ($null -eq $Proc) {
        Write-Host "[!] No process to stop." -ForegroundColor Yellow
        return
    }
    try {
        if (!$Proc.HasExited) {
            Stop-Process -Id $Proc.Id -Force -ErrorAction Stop
            Write-Host "[✓] Process stopped successfully (PID: $($Proc.Id))" -ForegroundColor Green
        } else {
            Write-Host "[i] Process has already exited." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[!] Error stopping process: $_" -ForegroundColor Red
    }
}

function Compare-Snapshots {
    param ([hashtable]$ComSnapshot1, [hashtable]$ComSnapshot2)
    $diffList = @()
    foreach ($path in $ComSnapshot1.Keys) {
        $keys1 = $ComSnapshot1[$path].Keys
        $keys2 = $ComSnapshot2[$path].Keys
        foreach ($key in $keys1) {
            $val1 = $ComSnapshot1[$path][$key]
            $val2 = $ComSnapshot2[$path][$key]
            if ($val1 -ne $val2) {
                $diffList += [PSCustomObject]@{
                    Path = $path
                    Name = $key
                    Before = $val1
                    After = $val2
                    Change = if ($null -eq $val2) { "Removed" } else { "Modified" }
                }
            }
        }
        foreach ($key in $keys2) {
            if (-not $keys1 -or ($key -notin $keys1)) {
                $diffList += [PSCustomObject]@{
                    Path = $path
                    Name = $key
                    Before = $null
                    After = $ComSnapshot2[$path][$key]
                    Change = "Added"
                }
            }
        }
    }
    return $diffList
}

Write-Host "==============================" -ForegroundColor Yellow
Write-Host "   RunKeyDiff.ps1 started"
Write-Host "==============================`n" -ForegroundColor Yellow

$RegSnapshot1 = Get-RunKeySnapshot
Write-Host "`n[+] First snapshot taken.`n" -ForegroundColor Green

$ProcessPath = Read-Host "Enter the full path of the process to run"
$Proc = Run-ObservedProcess -ProcessPath $ProcessPath

Start-Sleep -Seconds 5

$RegSnapshot2 = Get-RunKeySnapshot
Write-Host "`n[+] Second snapshot taken.`n" -ForegroundColor Green

Stop-ObservedProcess -Proc $Proc

$ComparedShot = Compare-Snapshots -ComSnapshot1 $RegSnapshot1 -ComSnapshot2 $RegSnapshot2

Write-Host "`n=============================="
Write-Host " Changes observed in Run keys"
Write-Host "==============================`n"

if ($ComparedShot.Count -eq 0) {
    Write-Host "No changes detected in registry Run keys." -ForegroundColor Cyan
} else {
    $ComparedShot | Format-Table Path, Name, Change, Before, After -AutoSize
}

Write-Host "`n[✓] Comparison complete.`n" -ForegroundColor Green







