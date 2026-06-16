##############################################################################################
## Description: Script to create a CSV file with the disk informations of a Windows system
##
## Author: Matteo Z.
##############################################################################################

Param (
	[Parameter(Mandatory=$false)] [Alias('H')] [string] $remote_host,
	[Parameter(Mandatory=$false)] [Alias('P')] [string] $remote_path,
	[Parameter(Mandatory=$false)] [string] $system_list = "C:\temp\system.txt",
	[Parameter(Mandatory=$false)] [string] $path_export = "C:\temp\diskExport",
	[Parameter(Mandatory=$false)] [System.Management.Automation.PSCredential] $Credential,
	[Parameter(Mandatory=$false)] [switch] $AskAlwaysCred
)

function print_usage {
	Write-Host -ForegroundColor "red" "`nDescription:"
	Write-Host "   Script to create a CSV file with some disk informations, like the free and the total space, of a Windows system and saves it,"
	Write-Host "   only under request, on a remote system and in a specified path, passed as an argument"
	Write-Host "`n   File with the list of the Windows system: $system_list"
	Write-Host "`n   Directory of all CSV file created with the disk information: $path_csv"
	Write-Host "`n   Directory with all log file: $path_log"
	Write-Host "`n   The format of the file $system_list must be: <hostname1>,<ip address1>"
	Write-Host "                                                      ....."
	Write-Host "                                                      <hostnameN>,<ip addressN>"
	Write-Host -ForegroundColor "red" "`nUsage:"
	Write-Host "  1) $script"
	Write-Host "  2) $script -H <remote host> -P <remote_path>"
	Write-Host "  3) $script -AskAlwaysCred"
	Write-Host "  4) $script -Credential <credential>"
	Write-Host -ForegroundColor "red" "`nOption:"
	Write-Host "  -H"
	Write-Host "     Remote host to save the CSV file produced - not mandatory`n"
	Write-Host "  -P"
	Write-Host "     Path of the remote host where to save the CSV (e.g. 'C:\temp') - not mandatory (if the remote host is specified, then it becomes mandatory!)`n"
	Write-Host "  -system_list"
	Write-Host "     File with the list of Windows systems to analyze - default: C:\temp\system.txt`n"
	Write-Host "  -path_export"
	Write-Host "     Base directory where CSV and log files are created - default: C:\temp\diskExport`n"
	Write-Host "  -Credential"
	Write-Host "     Credential to use for all remote systems. If specified, it is used instead of asking interactively`n"
	Write-Host "  -AskAlwaysCred"
	Write-Host "     Ask credentials for every remote system. If not specified, the first credential entered is reused for all remote systems`n"
}

function verify_path {
	param (
		[string[]] $path_to_verify
	)

	foreach ($item in $path_to_verify) {
		if (! (Test-Path $item -PathType Container)) {	# test if it's a directory
			Write-Host "The path $item does not exist. Creating it..."
			Start-Sleep -Seconds 1

			try {
				New-Item -Path $item -ItemType Directory -ErrorAction Stop | Out-Null	# create a directory but show nothing in the output
			} catch {
				Write-Host "Failed to create directory $item"
				return $false	# equivalent to saying that the operation or condition is negative or false
			}
		}
	}
	
	return $true	# equivalent to saying that the operation or condition is successful or true
}

function test_system_connection {
	param (
		[string] $computer
	)

	if ($computer -eq "localhost" -or $computer -eq "127.0.0.1") {
		return $true
	}

	try {
		return (Test-Connection -ComputerName $computer -Quiet -Count 2 -ErrorAction Stop)
	} catch {
		"Connection test failed for '$computer': $($_.Exception.Message)" >> $log
		return $false
	}
}

function retrieve_disk_info {
	param (
		[string] $system,
		[string] $ip_address
	)

	"Retrieving the fixed disk (DriveType = 3) informations of the $system ..." >> $log

	# initialize the command variable to $null (equivalent to nonexistent value)
	$command = $null
	$is_local_system = ($system -eq "localhost" -or $ip_address -eq "127.0.0.1")

	if (! $is_local_system) {
		try {
			# retrieve the IP addresses of the local system (excluding the loopback address)
			$local_ips = @(Get-NetIPAddress -AddressState Preferred -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -ExpandProperty IPAddress)
			$is_local_system = ($local_ips -contains $ip_address)
		} catch {
			"Unable to retrieve local IP addresses: $($_.Exception.Message)" >> $log
		}
	}

	# command to retrieve the disk informations (total, used and free space)
	$get_wmi = {
		try {
			$logical_disks = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop
		} catch {
			$logical_disks = Get-WmiObject Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop
		}

		$logical_disks | Select-Object DeviceID, Description, FileSystem,  `
		@{Name="TotalSpace(GB)";Expression={[math]::Round($_.Size/1GB, 2)}}, `
		@{Name="UsedSpace(GB)";Expression={[math]::Round(($_.Size - $_.FreeSpace)/1GB, 2)}}, `
		@{Name="FreeSpace(GB)";Expression={[math]::Round($_.FreeSpace/1GB, 2)}}
	}

	try {
		if ($is_local_system) {
			# if the system is the localhost, there is not need to execute a remote command with 'Invoke-Command' (& -> to execute a command in a variable)
			$command = & $get_wmi
		} else {
			if ($null -ne $Credential) {
				$command = Invoke-Command -ComputerName $ip_address -Credential $Credential -ScriptBlock $get_wmi -ErrorAction Stop
			} elseif ($AskAlwaysCred) {
				$remoteCredential = Get-Credential -Message "Insert the credential to retrieve disk information from $system ($ip_address)"
				$command = Invoke-Command -ComputerName $ip_address -Credential $remoteCredential -ScriptBlock $get_wmi -ErrorAction Stop
			} else {
				if ($null -eq $script:remoteCredential) {
					$script:remoteCredential = Get-Credential -Message "Insert the credential to retrieve disk information from remote systems"
				}

				$command = Invoke-Command -ComputerName $ip_address -Credential $script:remoteCredential -ScriptBlock $get_wmi -ErrorAction Stop
			}
		}
	} catch {
		Write-Host -ForegroundColor "red" "An error occurred: $_"
		"An error occurred while retrieving disk information from $system ($ip_address): $($_.Exception.Message)" >> $log
	}

	$disk_info = @()

	if ($command) {
		foreach ($item in $command) {
			$disk = if ($null -ne $item.'DeviceID') { $item.'DeviceID' } else { "NotFound" }
			$descr = $item.Description
			$filesystem = $item.FileSystem
			$total_space = if ($null -ne $item.'TotalSpace(GB)') { $item.'TotalSpace(GB)' } else { "NotFound" }
			$used_space = if ($null -ne $item.'UsedSpace(GB)') { $item.'UsedSpace(GB)' } else { "NotFound" }
			$free_space = if ($null -ne $item.'FreeSpace(GB)') { $item.'FreeSpace(GB)' } else { "NotFound" }

			# simulating a missing disk info (e.g. free space) 
			# $free_space = if ($false) { $item.'FreeSpace(GB)' } else { "NotFound" }

			"I compose the string to be reported in the CSV ..." >> $log
			$disk_info += [PSCustomObject]@{
				System = $system
				'IP address' = $ip_address
				Disk = $disk
				Description = $descr
				Filesystem = $filesystem
				'TotalSpace(GB)' = $total_space
				'UsedSpace(GB)' = $used_space
				'FreeSpace(GB)' = $free_space
			}
		}
	} else {
		"Attention!! I can't be compose the string with the disk informations!" >> $log
	}

	return $disk_info
}

function create_csv {
	$flag = 0
	$disk_info = @()
	
	foreach ($row in $file_content) {
		Start-Sleep -Seconds 1
		# cut the string where there is a comma
		$match = $row.split(",")
		"`n------------------------------------------------" >> $log
		Write-Host -NoNewline -ForegroundColor "green" "`n- Analyzing the row = "
		Write-Host $row
		Start-Sleep -Seconds 1

		# if there are 2 words go ahead (i.e. system_name,ip)
		if ($match.Count -eq 2) {
			$system = $match[0].Trim()
			$ip_address = $match[1].Trim()
			Write-Host "System = $system - IP = $ip_address"
			Start-Sleep -Seconds 1

			if ([string]::IsNullOrWhiteSpace($system) -or [string]::IsNullOrWhiteSpace($ip_address)) {
				"`nWarning!! The line '" + $row + "' has been skipped!" >> $log
				Write-Host -ForegroundColor "red" "Problem with this row!"
			} else {
				"`nTesting the connection with the system '" + $system + " - $ip_address' ..." >> $log

				# test the connection with the system but do not print anything on the output (only returns true or false)
				if (test_system_connection -computer $ip_address) {
					"Connection ok, the system is reachable!" >> $log
					Write-Host -ForegroundColor "green" "Ping ok!"
					Start-Sleep -Seconds 1
					$disk_info += retrieve_disk_info -system $system -ip_address $ip_address
				} else {
					"Connection failed, the system can't be reachable!" >> $log
					Write-Host -ForegroundColor "red" "Ping failed!"
				}
			}
		} else {
			"`nWarning!! The line '" + $row + "' has been skipped!" >> $log
			Write-Host -ForegroundColor "red" "Problem with this row!"
		}
	}

	if ($disk_info.Count -gt 0) {
		# Write-Host "`nAll disk informations:`n$disk_info"
		$disk_info | Export-Csv -Path $csv -Delimiter "`t" -NoTypeInformation
		$flag = 1
	}

	return @($flag, $csv)	# return more than one variable in the function
}

function copy_csv_to_remote_host {
	param (
		[string] $csv
	)

	if (! [string]::IsNullOrWhiteSpace($remote_host)) {
		if (! [string]::IsNullOrWhiteSpace($remote_path)) {
			Start-Sleep -Seconds 1

			if (test_system_connection -computer $remote_host) {
				"Connection ok, the system is reachable!" >> $log
				Write-Host -ForegroundColor "green" "$remote_host - Ping ok!"
				Start-Sleep -Seconds 1
				# e.g. -P C:\temp -> $disk = C
				#                    $path = temp
				$disk, $path = $remote_path.Replace(":", "").Split("\", 2)
				
				if (! [string]::IsNullOrWhiteSpace($disk) -and ! [string]::IsNullOrWhiteSpace($path)) {
					$share = "\\$remote_host\$disk$\$path"
					"Remote disk and path where to copy the CSV: $disk - $path" >> $log
					"Remote share: $share" >> $log

					if (! (Test-Path $share -PathType Container)) {
						$remote_host + " - The directory '" + $share + "' doesn't exist!" >> $log
					} else {
						try {
							Copy-Item -Path $csv -Destination $share -ErrorAction Stop
							Write-Host -ForegroundColor "green" "`nThe file has been copied on $share!"
						} catch {
							Write-Host -ForegroundColor "red" "`n$remote_host - Failed to copy the CSV on $share!"
							Write-Host $_.Exception.Message
						}
					}
				} else {
					"Attention!! What is the path where I have to copy the file?" >> $log
					Write-Host -ForegroundColor "yellow" "`nAttention!! I don't understand the path on the remote host!"
				}
			} else {
				$remote_host + " - Connection failed, the server can't be reachable!" >> $log
				Write-Host -ForegroundColor "red" "$remote_host - Ping failed!"
			}
		} else {
			Write-Host -ForegroundColor "yellow" "Attention! I don't understand where I should copy the csv file, you should put also the remote path!"
		}
	}
}


########## MAIN ##########

$script = $MyInvocation.MyCommand.Name
$date = Get-Date -f yyyy-MM-dd_HH-mm-ss
$path_log = "$path_export\Log"
$path_csv = "$path_export\CSV"

if (Test-Path $system_list -PathType Leaf) {	# check if it's a file
	$file_content = Get-Content $system_list

	if ($file_content.Count -ne 0) {	# check if the file is not empty
		$path_to_verify = @($path_export, $path_log, $path_csv)		# to create an array
		
		if (verify_path -path_to_verify $path_to_verify) {
			$log = "$path_log\log-$date.log"
			$csv = "$path_csv\diskExport-$date.csv"
			
			$flag, $csv = create_csv
			# Write-Host "CSV exists? $flag - CSV to create = $csv"

			if ($flag) {
				if ((Get-Content $csv).Count -ne 0) {
					"`n`nHere you can found the CSV file '$csv'!" >> $log
					Write-Host "`nThe file CSV $csv has been created, you should check it!!"
					copy_csv_to_remote_host -csv $csv
				} else {
					"`nCSV file '$csv' is empty!" >> $log
					Write-Host -ForegroundColor "red" "`nCSV '$csv' is empty!"
				}	
			} else {
				"`nCSV file '$csv' has not been found!" >> $log
				Write-Host -ForegroundColor "red" "`nCSV '$csv' has not been found!"
			}

			if (Test-Path $log -PathType Leaf) {
				Write-Host "`nThe file log $log has been created, you should check it!!"
			}

			Write-Host ""
		}
	} else {
		Write-Host -ForegroundColor "yellow" "`nAttention!! The file $system_list is empty!"
		print_usage
	}
} else {
	Write-Host -ForegroundColor "yellow" "`nAttention!! The file $system_list has not been found!"
	print_usage
}
