#########################################
## WINDOWS 10 UPGRADE ROLLBACK CHECKER ##
#########################################

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

# Check if OS was updated or not
$Version = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ReleaseID -ErrorAction Stop).ReleaseID
If ($Version  -ne "1909")
{
    # If not, log it, run the scheduled task to notify the user etc
    Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Rolled back" -Force
    Write-UpgradeLog -Message "Update was rolled back after reboot!" -LogLevel 3

    # Stamp SetupDiag data to registry
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

    Try 
    {
        Register-ScheduledTask -Xml (Get-Content "$WorkingDirectory\Windows 10 Upgrade Rollback Notification.xml" | out-string) -TaskName "Windows 10 Upgrade Rollback Notification" -Force -ErrorAction Stop
        Write-UpgradeLog -Message "Registered scheduled task 'Windows 10 Upgrade Rollback Notification'"
    }
    Catch 
    {
        Write-UpgradeLog -Message "Failed to register scheduled task 'Windows 10 Upgrade Rollback Notification': $_" -LogLevel 2
    }
    Try 
    {
        Start-Sleep -Seconds 5
        Start-ScheduledTask -TaskName "Windows 10 Upgrade Rollback Notification" -ErrorAction Stop
        Write-UpgradeLog -Message "Notified user of rollback via toast notification"
    }
    Catch 
    {
        Write-UpgradeLog -Message "Failed to notify user of rollback via toast notification: $_" -LogLevel 2
    }
    Try 
    {
        Start-Sleep -Seconds 5
        Disable-ScheduledTask -TaskName "Windows 10 Upgrade Rollback Notification"  -ErrorAction Stop
        Write-UpgradeLog -Message "Disabled scheduled task 'Windows 10 Upgrade Rollback Notification'"
    }
    Catch 
    {
        Write-UpgradeLog -Message "Failed to disable scheduled task 'Windows 10 Upgrade Rollback Notification': $_" -LogLevel 2
    }    
}
Else 
{
    # If successful updgrade, log it and delete the desktop shortcut for the update
    Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Successfully updated" -Force
    Write-UpgradeLog -Message "Update was successfully applied after reboot."
    try 
    {
        Remove-Item "$env:PUBLIC\Desktop\Windows 10 Update.lnk" -Force -ErrorAction Stop
        Write-UpgradeLog -Message "'Windows 10 Update' shortcut was removed from '$env:PUBLIC\Desktop'"
    }
    catch 
    {
        Write-UpgradeLog -Message "Failed to remove 'Windows 10 Update' shortcut from '$env:PUBLIC\Desktop'" -LogLevel 2
    }
    
}

# Disable the rollback checker scheduled task in any case
Try 
{
    Disable-ScheduledTask -TaskName "Windows 10 Upgrade Rollback Checker"   -ErrorAction Stop
    Write-UpgradeLog -Message "Disabled scheduled task 'Windows 10 Upgrade Rollback Checker'"
}
Catch 
{
    Write-UpgradeLog -Message "Failed to disable scheduled task 'Windows 10 Upgrade Rollback Checker': $_" -LogLevel 2
}   

# Send the current status
Send-StatusUpdate