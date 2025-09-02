function Get-BackupVolumes {

    Get-Volume | Where-Object {
        ($_.FileSystemType -in @('NTFS', 'FAT32')) -and
        ($_.DriveType -in ('Fixed', 'Removable')) -and
        ($null -ne $_.DriveLetter -and $_.DriveLetter -ne '')
    }
}
