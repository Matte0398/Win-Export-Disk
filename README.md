# Win-Export-Disk

PowerShell utility that collects Windows disk information and exports the results to a CSV file.

The script reads a list of Windows systems, checks their reachability, retrieves fixed disk information, and generates a CSV report with disk usage details.

It can also optionally copy the generated CSV file to a remote host and path.

## Features

- Collects fixed disk information (DriveType = 3) from Windows systems
- Supports local and remote systems
- Reads target systems from an input file
- Checks system reachability before collecting data
- Retrieves disk data using CIM/WMI
- Exports results to CSV
- Creates log files for troubleshooting
- Supports custom export paths
- Supports credentials for remote systems
- Can copy the generated CSV report to a remote host

## Collected Information

The generated CSV file includes:

- System name
- IP address
- Disk letter
- Description
- File system
- Total space in GB
- Used space in GB
- Free space in GB

## Requirements

- Windows PowerShell
- Network access to the target systems
- Permissions to query remote Windows systems
- PowerShell remoting enabled on remote systems, if remote collection is required

## Input

By default, the script reads the list of systems from:

``` text
C:\temp\system.txt

server01,192.168.1.10
server02,192.168.1.11
```

## Output

By default, the script creates output files under:

``` text
C:\temp\diskExport

The following folders are created automatically:

  C:\temp\diskExport\CSV
  C:\temp\diskExport\Log

Generated files:

  C:\temp\diskExport\CSV\diskExport-<timestamp>.csv
  C:\temp\diskExport\Log\log-<timestamp>.log
```

## Usage

``` powershell
.\exportDiskInfo.ps1

Specify a custom systems list:

  .\exportDiskInfo.ps1 -system_list "C:\temp\systems.txt"

Specify a custom export path:

  .\exportDiskInfo.ps1 -path_export "C:\Reports\DiskExport"

Copy the generated CSV file to a remote host:

  .\exportDiskInfo.ps1 -H "remote-server" -P "C:\temp"

Use a predefined credential:

  .\exportDiskInfo.ps1 -Credential $credential

Ask for credentials for every remote system:

  .\exportDiskInfo.ps1 -AskAlwaysCred
```

## CSV Example

| System | IP address | Disk | Description | Filesystem | TotalSpace(GB) | UsedSpace(GB) | FreeSpace(GB) |
|--------|------------|------|-------------|------------|----------------|---------------|---------------|
| server01 | 192.168.1.11 | C: | Local Fixed Disk | NTFS | 100 | 70 | 30 |
| server02 | 192.168.1.12 | D: | Local Fixed Disk | NTFS | 200 | 120 | 80 |

## Repository Structure

``` text
Win-Export-Disk/
│   exportDiskInfo.ps1
├── examples/
│   ├── system.txt
└── README.md
