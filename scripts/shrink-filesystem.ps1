# Get information about the system drive
$partition = Get-Partition -DriveLetter 'C'

# Defrag disk
defrag C: /L /D /K /G /H
defrag C: /X /H

# Resize the filesystem, keep trying until it succeeds or timeout
$timeout = 300
$retryInterval = 15
$startTime = Get-Date
while ((Get-Date) -lt $startTime.AddSeconds($timeout)) {
    $output = @"
sel disk $($partition.DiskNumber)
sel part $($partition.PartitionNumber)
shrink
"@ | diskpart
    Write-Host $output
    if ($output -match "DiskPart successfully shrunk the volume") {
        break
    }
    Write-Host "Retrying in $retryInterval seconds..."
    Start-Sleep -Seconds $retryInterval
}

if ((Get-Date) -ge $startTime.AddSeconds($timeout)) {
    Write-Host "Timeout: Shrink is still not successfull after $timeout seconds."
}

Write-VolumeCache C
