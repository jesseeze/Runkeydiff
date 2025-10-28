function Read-KeyValues {
    param ([string]$KeyPath)
    $h = @{}        # Create an empty hashtable
    $item = Get-ItemProperty -Path $KeyPath -ErrorAction SilentlyContinue
    foreach ($property in $item.PSObject.Properties) {
        if ($property.Name -match '^PS') { continue } # Skip System properties
        $h[$property.Name] = $property.Value
    }
    return $h
}

function Write-KeyValue1 {
    $paths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    )

    $snapshot = @{}

    try {
        foreach ($path in $paths) {
            # Reading registry values
            $values = Read-KeyValues -KeyPath $path
            Write-Host "`nValues in $($path):`n"
            $values
            $snapshot[$path] = $values
        }
    } 
    catch {
        Write-Host "Error reading registry: $_"
    }

    return $snapshot
}

function Run-ObservedProcess {
    param ([string]$ProcessPath)

    try {
        Start-Process -FilePath $ProcessPath -ErrorAction Stop
        Write-Host "Process started successfully."
    }
    catch {
        Write-Host "Error starting process: $_"
    }
}

function Compare-Snapshots {
    param (
        [hashtable]$ComSnapshot1,
        [hashtable]$ComSnapshot2
    )

    $differences = @()

    foreach ($key in $ComSnapshot1.Keys) {
        foreach ($subkey in $ComSnapshot1[$key].Keys) {
            $val1 = $ComSnapshot1[$key][$subkey]
            $val2 = $ComSnapshot2[$key][$subkey]
            if ($val1 -ne $val2) {
                $differences += [PSCustomObject]@{
                    Path   = $key
                    Name   = $subkey
                    Before = $val1
                    After  = $val2
                }
            }
        }
    }

    # Detect new values added after process run
    foreach ($key in $ComSnapshot2.Keys) {
        foreach ($subkey in $ComSnapshot2[$key].Keys) {
            if (-not $ComSnapshot1[$key].ContainsKey($subkey)) {
                $differences += [PSCustomObject]@{
                    Path   = $key
                    Name   = $subkey
                    Before = $null
                    After  = $ComSnapshot2[$key][$subkey]
                }
            }
        }
    }

    return $differences
}

# === Main Execution ===

$RegSnapshot1 = Write-KeyValue1
Write-Host "First snapshot taken."

$ProcessPath = Read-Host "Please enter the process name (with full path) to run and press Enter to continue..."
Run-ObservedProcess -ProcessPath $ProcessPath

# Wait a bit for changes to occur
Start-Sleep -Seconds 5

$RegSnapshot2 = Write-KeyValue1

$ComparedShot = Compare-Snapshots -ComSnapshot1 $RegSnapshot1 -ComSnapshot2 $RegSnapshot2

Write-Host "`nChanges observed in registry Run keys:`n"
$ComparedShot | Format-Table -AutoSize
