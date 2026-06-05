 # WinExportDisk

PowerShell script that exports Windows disk information, such as free space and total space, to a CSV file.

Optionally, the CSV file can be saved to a remote host and a specific remote path.

## Usage

```powershell
powershell.exe .\exportDiskInfo.ps1
powershell.exe .\exportDiskInfo.ps1 -H [remote_host] -P [remote_path]
