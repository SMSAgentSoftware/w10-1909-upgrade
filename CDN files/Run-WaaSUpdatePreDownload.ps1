###############################################
## WINDOWS 10 UPGRADE PRE DOWNLOAD EXECUTION ##
###############################################

# Set working folder
$RootFolder = $env:ProgramData
$ParentFolderName = "IT"
$ChildFolderName = "1909_Upgrade"
$script:WorkingDirectory = "$RootFolder\$ParentFolderName\$ChildFolderName"

# Set working registry location
$RootRegBase = "HKLM:\Software"
$RootRegBranchName = "IT"
$UpgradeBranchName = "1909Upgrade"
$FullRegPath = "$RootRegBase\$RootRegBranchName\$UpgradeBranchName"

# Function to write to log file
Function Write-UpgradeLog {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
		
        [Parameter()]
        [ValidateSet(1, 2, 3)] # 1-Info, 2-Warning, 3-Error
        [int]$LogLevel = 1,

        [Parameter(Mandatory = $false)]
        [string]$Component = "1909_Upgrade",

        [Parameter(Mandatory = $false)]
        [object]$Exception
    )

    $LogFile = "$WorkingDirectory\1909_Upgrade.log"
    
    If ($Exception)
    {
        [String]$Message = "$Message" + "$Exception"
    }

    $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
    $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
    $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), $Component, $LogLevel
    $Line = $Line -f $LineFormat
    
    # Write to log
    Add-Content -Value $Line -Path $LogFile

}

# Function to create a update record for this device in the Azure SQL database
Function Send-StatusUpdate {
    $ComputerName = $env:COMPUTERNAME
    $SerialNumber = Get-CimInstance win32_BIOS | Select -ExpandProperty SerialNumber
    $eventgridtopicendpoint = "https://myeventgridendpoint.eventgrid.azure.net/api/events"
    $eventgridtopickey = "myeventgridtopickey"

    # Read current values from registry
    $RegistryItems = Get-Item -Path HKLM:\SOFTWARE\IT\1909Upgrade    
    $CurrentStatus = $RegistryItems.GetValue("CurrentStatus")
    $DistributionPoint = $RegistryItems.GetValue("DistributionPoint")
    $DistributionPointLatency = $RegistryItems.GetValue("DistributionPointLatency")
    $ClientType = $RegistryItems.GetValue("ClientType")
    $OSArchitecture = $RegistryItems.GetValue("OSArchitecture")
    $OSVersion = $RegistryItems.GetValue("OSVersion")
    $FreeDiskSpace = $RegistryItems.GetValue("FreeDiskSpace")
    $Manufacturer = $RegistryItems.GetValue("Manufacturer")
    $Model = $RegistryItems.GetValue("Model")
    $ReadinessCheckResult = $RegistryItems.GetValue("ReadinessCheckResult")
    $ReadinessCheckFailureDetail = $RegistryItems.GetValue("ReadinessCheckFailureDetail")
    $ReadinessCheckTimestampUTC = $RegistryItems.GetValue("ReadinessCheckTimestampUTC")
    $DownloadBandwidth = $RegistryItems.GetValue("DownloadBandwidth")
    $CurrentConnectionType = $RegistryItems.GetValue("CurrentConnectionType")
    $CorporateNetworkConnectivity = $RegistryItems.GetValue("CorporateNetworkConnectivity")
    $OSName = $RegistryItems.GetValue("OSName")
    $OSDescription = $RegistryItems.GetValue("OSDescription")
    $OSProductKeyChannel = $RegistryItems.GetValue("OSProductKeyChannel")
    $OSLanguageCode = $RegistryItems.GetValue("OSLanguageCode")
    $OSLanguage = $RegistryItems.GetValue("OSLanguage")
    $ESDFileName = $RegistryItems.GetValue("ESDFileName")
    $ESDMD5Hash = $RegistryItems.GetValue("ESDMD5Hash")
    $CurrentDownloadPercentComplete = $RegistryItems.GetValue("CurrentDownloadPercentComplete")
    $CurrentDownloadStartTime = $RegistryItems.GetValue("CurrentDownloadStartTime")
    $CurrentDownloadFinishTime = $RegistryItems.GetValue("CurrentDownloadFinishTime")
    $WindowsUpdateBoxDownloadDuration = $RegistryItems.GetValue("WindowsUpdateBoxDownloadDuration")
    $ESDDownloadDuration = $RegistryItems.GetValue("ESDDownloadDuration")
    $PreDownloadStartTime = $RegistryItems.GetValue("PreDownloadStartTime")
    $PreDownloadFinishTime = $RegistryItems.GetValue("PreDownloadFinishTime")
    $PreDownloadDuration = $RegistryItems.GetValue("PreDownloadDuration")
    $PreDownloadProcessExitCode = $RegistryItems.GetValue("PreDownloadProcessExitCode")
    $FailureCount = $RegistryItems.GetValue("FailureCount")
    $BoxResult = $RegistryItems.GetValue("BoxResult")
    $SetUpDiagFailureDetails = $RegistryItems.GetValue("SetUpDiagFailureDetails").Replace('"','').Replace("'",'')
    $SetupDiagFailureData = $RegistryItems.GetValue("SetupDiagFailureData").Replace('"','').Replace("'",'')
    $SetupDiagProfileName = $RegistryItems.GetValue("SetupDiagProfileName")
    $SetupDiagRemediation = $RegistryItems.GetValue("SetupDiagRemediation").Replace('"','').Replace("'",'')
    $SetupDiagDateTime = $RegistryItems.GetValue("SetupDiagDateTime")
    $HardBlockFound = $RegistryItems.GetValue("HardBlockFound") 
    $HardBlockTitle = $RegistryItems.GetValue("HardBlockTitle").Replace('"','').Replace("'",'')
    $HardBlockMessage = $RegistryItems.GetValue("HardBlockMessage").Replace('"','').Replace("'",'')
    $Deadline = $RegistryItems.GetValue("Deadline")
    $InstallStartTime = $RegistryItems.GetValue("InstallStartTime")
    $InstallFinishTime = $RegistryItems.GetValue("InstallFinishTime")
    $InstallDuration = $RegistryItems.GetValue("InstallDuration")
    $InstallProcessExitCode = $RegistryItems.GetValue("InstallProcessExitCode")
    $FinalizeStartTime = $RegistryItems.GetValue("FinalizeStartTime")
    $FinalizeFinishTime = $RegistryItems.GetValue("FinalizeFinishTime")
    $FinalizeDuration = $RegistryItems.GetValue("FinalizeDuration")
    $FinalizeProcessExitCode = $RegistryItems.GetValue("FinalizeProcessExitCode")
    $DownloadLocation = $RegistryItems.GetValue("DownloadLocation")
    $AzureCDNLatency = $RegistryItems.GetValue("AzureCDNLatency")
    $ESDEstimatedDownloadDuration = $RegistryItems.GetValue("ESDEstimatedDownloadDuration")

    # Prepare hash table for the event body
    $eventID = Get-Random 99999      
    $eventDate = Get-Date -Format s # Date format should be SortableDateTimePattern (ISO 8601)
    $htbody = @{
        id= $eventID
        eventType="recordUpdated"
        subject="Upgrade 1909 Update Record"
        eventTime= $eventDate   
        data= @{
            ComputerName = "$ComputerName"
            SerialNumber = "$SerialNumber"
            CurrentStatus = $(If ($CurrentStatus -eq ""){"NULL"}Else{"$CurrentStatus"})
            DistributionPoint = $(If ($DistributionPoint -eq ""){"NULL"}Else{"$DistributionPoint"})
            DistributionPointLatency = $(If ($DistributionPointLatency -eq ""){"NULL"}Else{"$DistributionPointLatency"})
            ClientType = $(If ($ClientType -eq ""){"NULL"}Else{"$ClientType"})
            OSArchitecture = $(If ($OSArchitecture -eq ""){"NULL"}Else{"$OSArchitecture"})
            OSVersion = $(If ($OSVersion -eq ""){"NULL"}Else{"$OSVersion"})
            FreeDiskSpace = $(If ($FreeDiskSpace -eq ""){"NULL"}Else{"$FreeDiskSpace"})
            Manufacturer = $(If ($Manufacturer -eq ""){"NULL"}Else{"$Manufacturer"})
            Model = $(If ($Model -eq ""){"NULL"}Else{"$Model"})
            ReadinessCheckResult = $(If ($ReadinessCheckResult -eq ""){"NULL"}Else{"$ReadinessCheckResult"})
            ReadinessCheckFailureDetail = $(If ($ReadinessCheckFailureDetail -eq ""){"NULL"}Else{"$ReadinessCheckFailureDetail"})
            ReadinessCheckTimestampUTC = $(If ($ReadinessCheckTimestampUTC -eq ""){"NULL"}Else{"$ReadinessCheckTimestampUTC"})
            DownloadBandwidth = $(If ($DownloadBandwidth -eq ""){"NULL"}Else{"$DownloadBandwidth"})
            CurrentConnectionType = $(If ($CurrentConnectionType -eq ""){"NULL"}Else{"$CurrentConnectionType"})
            CorporateNetworkConnectivity = $(If ($CorporateNetworkConnectivity -eq ""){"NULL"}Else{"$CorporateNetworkConnectivity"})
            OSName = $(If ($OSName -eq ""){"NULL"}Else{"$OSName"})
            OSDescription = $(If ($OSDescription -eq ""){"NULL"}Else{"$OSDescription"})
            OSProductKeyChannel = $(If ($OSProductKeyChannel -eq ""){"NULL"}Else{"$OSProductKeyChannel"})
            OSLanguageCode = $(If ($OSLanguageCode -eq ""){"NULL"}Else{"$OSLanguageCode"})
            OSLanguage = $(If ($OSLanguage -eq ""){"NULL"}Else{"$OSLanguage"})
            ESDFileName = $(If ($ESDFileName -eq ""){"NULL"}Else{"$ESDFileName"})
            ESDMD5Hash = $(If ($ESDMD5Hash -eq ""){"NULL"}Else{"$ESDMD5Hash"})
            CurrentDownloadPercentComplete = $(If ($CurrentDownloadPercentComplete -eq ""){"NULL"}Else{"$CurrentDownloadPercentComplete"})
            CurrentDownloadStartTime = $(If ($CurrentDownloadStartTime -eq ""){"NULL"}Else{"$CurrentDownloadStartTime"})
            CurrentDownloadFinishTime = $(If ($CurrentDownloadFinishTime -eq ""){"NULL"}Else{"$CurrentDownloadFinishTime"})
            WindowsUpdateBoxDownloadDuration = $(If ($WindowsUpdateBoxDownloadDuration -eq ""){"NULL"}Else{"$WindowsUpdateBoxDownloadDuration"})
            ESDDownloadDuration = $(If ($ESDDownloadDuration -eq ""){"NULL"}Else{"$ESDDownloadDuration"})
            PreDownloadStartTime = $(If ($PreDownloadStartTime -eq ""){"NULL"}Else{"$PreDownloadStartTime"})
            PreDownloadFinishTime = $(If ($PreDownloadFinishTime -eq ""){"NULL"}Else{"$PreDownloadFinishTime"})
            PreDownloadDuration = $(If ($PreDownloadDuration -eq ""){"NULL"}Else{"$PreDownloadDuration"})
            PreDownloadProcessExitCode = $(If ($PreDownloadProcessExitCode -eq ""){"NULL"}Else{"$PreDownloadProcessExitCode"})
            FailureCount = $(If ($FailureCount -eq ""){"NULL"}Else{"$FailureCount"})
            BoxResult = $(If ($BoxResult -eq ""){"NULL"}Else{"$BoxResult"})
            SetUpDiagFailureDetails = $(If ($SetUpDiagFailureDetails -eq ""){"NULL"}Else{"$SetUpDiagFailureDetails"})
            SetupDiagFailureData = $(If ($SetupDiagFailureData -eq ""){"NULL"}Else{"$SetupDiagFailureData"})
            SetupDiagProfileName = $(If ($SetupDiagProfileName -eq ""){"NULL"}Else{"$SetupDiagProfileName"})
            SetupDiagRemediation = $(If ($SetupDiagRemediation -eq ""){"NULL"}Else{"$SetupDiagRemediation"})
            SetupDiagDateTime = $(If ($SetupDiagDateTime -eq ""){"NULL"}Else{"$SetupDiagDateTime"})
            HardBlockFound = $(If ($HardBlockFound -eq ""){"NULL"}Else{"$HardBlockFound"})
            HardBlockTitle = $(If ($HardBlockTitle -eq ""){"NULL"}Else{"$HardBlockTitle"})
            HardBlockMessage = $(If ($HardBlockMessage -eq ""){"NULL"}Else{"$HardBlockMessage"})
            Deadline = $(If ($Deadline -eq ""){"NULL"}Else{"$Deadline" | Get-Date -Format "o"})
            InstallStartTime = $(If ($InstallStartTime -eq ""){"NULL"}Else{"$InstallStartTime"})
            InstallFinishTime = $(If ($InstallFinishTime -eq ""){"NULL"}Else{"$InstallFinishTime"})
            InstallDuration = $(If ($InstallDuration -eq ""){"NULL"}Else{"$InstallDuration"})
            InstallProcessExitCode = $(If ($InstallProcessExitCode -eq ""){"NULL"}Else{"$InstallProcessExitCode"})
            FinalizeStartTime = $(If ($FinalizeStartTime -eq ""){"NULL"}Else{"$FinalizeStartTime"})
            FinalizeFinishTime = $(If ($FinalizeFinishTime -eq ""){"NULL"}Else{"$FinalizeFinishTime"})
            FinalizeDuration = $(If ($FinalizeDuration -eq ""){"NULL"}Else{"$FinalizeDuration"})
            FinalizeProcessExitCode = $(If ($FinalizeProcessExitCode -eq ""){"NULL"}Else{"$FinalizeProcessExitCode"})
            DownloadLocation = $(If ($DownloadLocation -eq ""){"NULL"}Else{"$DownloadLocation"})
            AzureCDNLatency = $(If ($AzureCDNLatency -eq ""){"NULL"}Else{"$AzureCDNLatency"})
            ESDEstimatedDownloadDuration = $(If ($ESDEstimatedDownloadDuration -eq ""){"NULL"}Else{"$ESDEstimatedDownloadDuration"})
        }
        dataVersion="1.0"
    }

    # Send the request
    $ProgressPreference = 'SilentlyContinue'
    Try
    {
        $body = "["+(ConvertTo-Json $htbody)+"]"
        $Response = Invoke-WebRequest -Uri $eventgridtopicendpoint -Method POST -Body $body -Headers @{"aeg-sas-key" = $eventgridtopickey} -UseBasicParsing -ErrorAction Stop
    }
    Catch
    {
        $_
    }
}

# Function to find hard compatibility blockers
Function Find-HardBlocks {
    # Find all the compatibility xml files
    $SearchLocation = 'C:\$WINDOWS.~BT\Sources\Panther'
    $CompatibilityXMLs = Get-childitem "$SearchLocation\compat*.xml" | Sort LastWriteTime -Descending

    # Create an array to hold the results
    $Blockers = @()

    # Search each file for any hard blockers
    Foreach ($item in $CompatibilityXMLs)
    {
        $xml = [xml]::new()
        $xml.Load($item)
        $HardBlocks = $xml.CompatReport.Hardware.HardwareItem | Where {$_.InnerXml -match 'BlockingType="Hard"'}
        If($HardBlocks)
        {
            Foreach ($HardBlock in $HardBlocks)
            {
                $FileAge = (Get-Date).ToUniversalTime() - $item.LastWriteTimeUTC
                $Blockers += [pscustomobject]@{
                    ComputerName = $env:COMPUTERNAME
                    FileName = $item.Name
                    LastWriteTimeUTC = $item.LastWriteTimeUTC
                    FileAge = "$($Fileage.Days) days $($Fileage.hours) hours $($fileage.minutes) minutes"
                    BlockingType = $HardBlock.CompatibilityInfo.BlockingType
                    Title = $HardBlock.CompatibilityInfo.Title
                    Message = $HardBlock.CompatibilityInfo.Message
                }
            }
        }
    }

    Return $Blockers
}


# Function to register contoso.com as a user app for toast notifications
Function Register-NotificationApp {
    $HKCR = Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue
    If (!($HKCR))
    {
        New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -Scope Script
    }
    $AppRegPath = "HKCR:\AppUserModelId"
    $AppID = "contoso.com"
    $RegPath = "$AppRegPath\$AppID"
    $DisplayNameValue = "contoso.com"
    $ShowInSettingsValue = "0"
    If (!(Test-Path $RegPath))
    {
        $null = New-Item -Path $AppRegPath -Name $AppID -Force
    }
    $DisplayName = Get-ItemProperty -Path $RegPath -Name DisplayName -ErrorAction SilentlyContinue | Select -ExpandProperty DisplayName -ErrorAction SilentlyContinue
    If ($DisplayName -ne $DisplayNameValue)
    {
        $null = New-ItemProperty -Path $RegPath -Name DisplayName -Value $DisplayNameValue -PropertyType String -Force
    }
    $ShowInSettings = Get-ItemProperty -Path $RegPath -Name ShowInSettings -ErrorAction SilentlyContinue | Select -ExpandProperty ShowInSettings -ErrorAction SilentlyContinue
    If ($ShowInSettings -ne $ShowInSettingsValue)
    {
        $null = New-ItemProperty -Path $RegPath -Name ShowInSettings -Value $ShowInSettingsValue -PropertyType DWORD -Force
    }
    Remove-PSDrive -Name HKCR -Force
}

########################
## Check Current Time ##
########################
$Hour = [Datetime]::Now.TimeOfDay.TotalHours
If ($Hour -gt 16.5)
{
    Write-UpgradeLog -Message "The hour is late so will perform no activities now to help avoid execution failure for the longer running tasks"
    Return
}

######################
## OS Version Check ##
######################
# Before going any further, check that the OS has not already been upgraded
$Version = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ReleaseID -ErrorAction Stop).ReleaseID
Set-ItemProperty -Path $FullRegPath -Name OSVersion -Value $Version -Force
If ($Version -eq "1909")
{
    Return
}

##########################################################################
## Blank out some registry keys in case they were set by a previous run ##
##########################################################################
$RegistryKeys = @(
    'PreDownloadFinishTime'
    'PreDownloadDuration'
    'PreDownloadProcessExitCode'
    'FailureCount'
    'BoxResult'
    'SetUpDiagFailureDetails'
    'SetupDiagFailureData'
    'SetupDiagProfileName'
    'SetupDiagRemediation'
    'SetupDiagDateTime'
    'HardBlockFound'
    'HardBlockTitle'
    'HardBlockMessage'
)
Foreach ($RegistryKey in $RegistryKeys)
{
    Set-ItemProperty -Path $FullRegPath -Name $RegistryKey -Value "" -Force
}

#####################
## Run PreDownload ##
#####################
Write-UpgradeLog -Message "Running PreDownload"
Write-UpgradeLog -Message "Cmd line: $WorkingDirectory\WindowsUpdateBox.exe /Update /PreDownload /quiet /noreboot"
Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Running PreDownload" -Force
$Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
Set-ItemProperty -Path $FullRegPath -Name PreDownloadStartTime -Value $Timestamp -Force
Send-StatusUpdate
try 
{
    $Process = Start-Process -FilePath "$WorkingDirectory\WindowsUpdateBox.exe" -ArgumentList "/Update /PreDownload /quiet /noreboot" -Wait -NoNewWindow -Passthru -ErrorAction Stop
}
catch 
{
    Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Failed to run PreDownload" -Force
    Write-UpgradeLog -Message "Failed to run the PreDownload. The error message was: $_" -LogLevel 3
    Write-UpgradeLog -Message "The PreDownload phase will be periodically retried" -LogLevel 2
    $Time = New-ScheduledTaskTrigger -Weekly -DaysOfWeek "Tuesday","Friday" -At 12PM 
    $Task = Set-ScheduledTask -TaskName "Windows 10 Upgrade PreDownload" -Trigger $Time
    $task | Set-ScheduledTask
    Send-StatusUpdate
    Return
}
$ConvertedExitCode = "0x" + "$('{0:X4}' -f $Process.ExitCode)"
$Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
Set-ItemProperty -Path $FullRegPath -Name PreDownloadFinishTime -Value $Timestamp -Force
$StartTime = Get-Date (Get-ItemProperty -Path $FullRegPath -Name PreDownloadStartTime | Select -ExpandProperty PreDownloadStartTime)
$FinishTime = Get-Date (Get-ItemProperty -Path $FullRegPath -Name PreDownloadFinishTime | Select -ExpandProperty PreDownloadFinishTime)
$Duration = ($FinishTime - $StartTime)
Set-ItemProperty -Path  $FullRegPath -Name PreDownloadDuration -Value "$($Duration.Minutes) minutes $($Duration.Seconds) seconds" -Force
Write-UpgradeLog -Message "Completed PreDownload in $($Duration.Minutes) minutes $($Duration.Seconds) seconds"
If ($Process.ExitCode -ne 0)
{
    Write-UpgradeLog -Message "PreDownload process completed with exit code $ConvertedExitCode" -LogLevel 2
}
else {
    Write-UpgradeLog -Message "PreDownload process completed with exit code $ConvertedExitCode"
}
Set-ItemProperty -Path $FullRegPath -Name PreDownloadProcessExitCode -Value $ConvertedExitCode -Force
If ($Process.ExitCode -ne 0)
{
    $FailureCount = Get-ItemProperty -Path HKLM:\SYSTEM\Setup\MoSetup\Tracking -Name FailureCount | Select -ExpandProperty FailureCount
    $BoxResult = "0x" + "$('{0:X4}' -f (Get-ItemProperty -Path HKLM:\SYSTEM\Setup\MoSetup\Volatile -Name BoxResult | Select -ExpandProperty BoxResult))"
    $SetupDiagFailureDetails = Get-ItemProperty -Path HKLM:\SYSTEM\Setup\setupdiag\results -Name FailureDetails | Select -ExpandProperty FailureDetails
    $SetupDiagFailureData = Get-ItemProperty -Path HKLM:\SYSTEM\Setup\setupdiag\results -Name FailureData | Select -ExpandProperty FailureData
    $SetupDiagProfileName = Get-ItemProperty -Path HKLM:\SYSTEM\Setup\setupdiag\results -Name ProfileName | Select -ExpandProperty ProfileName
    $SetupDiagRemediation = Get-ItemProperty -Path HKLM:\SYSTEM\Setup\setupdiag\results -Name Remediation | Select -ExpandProperty Remediation
    $SetupDiagDateTime = Get-ItemProperty -Path HKLM:\SYSTEM\Setup\setupdiag\results -Name DateTime | Select -ExpandProperty DateTime
    Set-ItemProperty -Path $FullRegPath -Name FailureCount -Value $FailureCount -Force
    Set-ItemProperty -Path $FullRegPath -Name BoxResult -Value $BoxResult -Force
    Set-ItemProperty -Path $FullRegPath -Name SetUpDiagFailureDetails -Value $SetUpDiagFailureDetails -Force
    Set-ItemProperty -Path $FullRegPath -Name SetupDiagFailureData -Value $SetupDiagFailureData -Force
    Set-ItemProperty -Path $FullRegPath -Name SetupDiagProfileName -Value $SetupDiagProfileName -Force
    Set-ItemProperty -Path $FullRegPath -Name SetupDiagRemediation -Value $SetupDiagRemediation -Force
    Set-ItemProperty -Path $FullRegPath -Name SetupDiagDateTime -Value $SetupDiagDateTime -Force
    Write-UpgradeLog -Message "BoxResult is $BoxResult"
    Write-UpgradeLog -Message "SetupDiag ProfileName is $SetupDiagProfileName"
    Write-UpgradeLog -Message "SetupDiag Failure Details: $SetupDiagFailureDetails"
    Write-UpgradeLog -Message "SetupDiag Failure Data: $SetupDiagFailureData"
    Write-UpgradeLog -Message "SetupDiag Remediation: $SetupDiagRemediation"
    $HardBlocks = Find-Hardblocks
    If ($HardBlocks)
    {
        Set-ItemProperty -Path $FullRegPath -Name HardBlockFound -Value "Yes" -Force
        Set-ItemProperty -Path $FullRegPath -Name HardBlockTitle -Value $HardBlocks[0].Title -Force
        Set-ItemProperty -Path $FullRegPath -Name HardBlockMessage -Value $HardBlocks[0].Message -Force
        Write-UpgradeLog -Message "A hard block was found:" -LogLevel 2
        Write-UpgradeLog -Message "  Title: $($HardBlocks[0].Title)" -LogLevel 2
        Write-UpgradeLog -Message "  Message: $($HardBlocks[0].Message)" -LogLevel 2
        If ($HardBlocks[0].Message -match "Your PC isn't supported yet on this version of Windows 10")
        {
            Write-UpgradeLog -Message "This PC is currently on compatibility hold. It cannot be upgraded until Microsoft have resolved the issue that prevents installation." -LogLevel 2
            Write-UpgradeLog -Message "The PreDownload phase will be retried periodically until the compatibility hold is released." -LogLevel 2
            Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Retry PreDownload due to compatibility hold" -Force
        }
        else 
        {
            set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Retry PreDownload due to hard block" -Force
        }
    }
    else 
    {
        Set-ItemProperty -Path $FullRegPath -Name HardBlockFound -Value "No" -Force
        Set-ItemProperty -Path $FullRegPath -Name HardBlockTitle -Value "" -Force
        Set-ItemProperty -Path $FullRegPath -Name HardBlockMessage -Value "" -Force
        Write-UpgradeLog -Message "No hard block was found"
        Write-UpgradeLog -Message "This PC did not pass the compatibility assessment or failed to run the PreDownload phase." -LogLevel 2
        Write-UpgradeLog -Message "The PreDownload phase will be retried periodically." -LogLevel 2
        Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Retry PreDownload due to failure" -Force
    }
    $Time = New-ScheduledTaskTrigger -Weekly -DaysOfWeek "Tuesday","Friday" -At 12PM #-At "$((Get-Date).AddHours(1).Hour):00"
    $Task = Set-ScheduledTask -TaskName "Windows 10 Upgrade PreDownload" -Trigger $Time
    $task | Set-ScheduledTask
}
else 
{
    Write-UpgradeLog -Message "The PreDownload phase passed successfully"
    Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Ready for upgrade" -Force
    Write-UpgradeLog -Message "Disabling the PreDownload scheduled task"
    Disable-ScheduledTask -TaskName "Windows 10 Upgrade PreDownload" 

    # Set the deadline to 30 days if a deadline doesn't already exist
    $Deadline = Get-ItemProperty -Path $FullRegPath -Name Deadline -ErrorAction SilentlyContinue | Select -ExpandProperty Deadline -ErrorAction SilentlyContinue
    If (!($Deadline))
    {
        $Timestamp = [Datetime]::UtcNow.AddDays(30).Date.AddHours(15) | Get-Date -Format "MMMM dd yyyy, HH:mm"
        Write-UpgradeLog -Message "Setting the upgrade deadline to '$Timestamp'"
        Set-ItemProperty -Path $FullRegPath -Name Deadline -Value $Timestamp -Force
    }
    # Register contoso.com as a user app for toast notifications
    Write-UpgradeLog -Message "Registering contoso.com as a user app for toast notifications"
    Register-NotificationApp 

    # Register scheduled tasks for upgrade notifications, and the upgrade itself
    Register-ScheduledTask -Xml (Get-Content "$WorkingDirectory\Windows 10 Upgrade Notification.xml" | out-string) -TaskName "Windows 10 Upgrade Notification" -Force
    Register-ScheduledTask -Xml (Get-Content "$WorkingDirectory\Windows 10 Upgrade.xml" | out-string) -TaskName "Windows 10 Upgrade" -Force

    # Register event source for Windows 10 upgrade event trigger
    If (!([System.Diagnostics.EventLog]::SourceExists("Windows 10 Update")))
    {
        [System.Diagnostics.EventLog]::CreateEventSource("Windows 10 Update","Application")
    }

    # Create Desktop shortcut for the update
    $TargetFile = "WScript.exe"
    $ShortcutFile = "$env:Public\Desktop\Windows 10 Update.lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
    $Shortcut.TargetPath = $TargetFile
    $Shortcut.IconLocation = "$WorkingDirectory\myiconfile.ico"
    $Shortcut.Arguments = """$WorkingDirectory\Invoke-PSScript.vbs"" ""New-WaaSUpdateTriggerEvent.ps1"""
    $Shortcut.Save()
}

Send-StatusUpdate
Start-ScheduledTask -TaskName "Windows 10 Upgrade Notification"
