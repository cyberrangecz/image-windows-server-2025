# Get information about the system drive
$partition = Get-Partition -DriveLetter 'C'

# Defrag disk
defrag C: /L /D /K /G /H
defrag C: /X /H

# Resize the system partition with the updated size
@"
sel disk $($partition.DiskNumber)
sel part $($partition.PartitionNumber)
shrink
"@ | diskpart

Write-VolumeCache C
