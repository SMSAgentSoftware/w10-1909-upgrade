#########################
## WINDOWS 10 UPGRADER ##
#########################

# Check to see if the script is already running in another execution, if so exit and let it finish
$ExistingExecution = Get-CimInstance Win32_process -ErrorAction Stop | where {$_.Name -eq "powershell.exe" -and $_.CommandLine -match "Run-WaaSUpdatePreparation.ps1" -and $_.ProcessId -ne $PID}
If ($ExistingExecution)
{
    Return
}

$ProgressPreference = 'SilentlyContinue'

# Set working folder
$RootFolder = $env:ProgramData
$ParentFolderName = "IT"
$ChildFolderName = "1909_Upgrade"
$script:WorkingDirectory = "$RootFolder\$ParentFolderName\$ChildFolderName"

# Set Azure CDN URI
$CDNEndPoint = "https://myCDNendpoint.azureedge.net"
$Container = "w10-1909-upgrade"
$CDNEndPointURI = "$CDNEndPoint/$Container"

# Get list of ConfigMgr Distribution Points
[array]$ConfigMgrDistributionPoints = Get-Content -Path $WorkingDirectory\ConfigMgr_DistributionPoints.txt


#region Functions
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

# Function to detect a VPN connection
Function Get-CurrentConnectionType {
    $WirelessConnected = $null
    $WiredConnected = $null
    $VPNConnected = $null

    $WirelessAdapters =  Get-CimInstance -Namespace "root\WMI" -Class MSNdis_PhysicalMediumType -Filter `
        'NdisPhysicalMediumType = 9'
    $WiredAdapters = Get-CimInstance -Namespace "root\WMI" -Class MSNdis_PhysicalMediumType -Filter `
        "NdisPhysicalMediumType = 0 and `
        (NOT InstanceName like '%pangp%') and `
        (NOT InstanceName like '%cisco%') and `
        (NOT InstanceName like '%juniper%') and `
        (NOT InstanceName like '%vpn%') and `
        (NOT InstanceName like 'Hyper-V%') and `
        (NOT InstanceName like 'VMware%') and `
        (NOT InstanceName like 'VirtualBox Host-Only%') and `
        (NOT InstanceName like '%Multiplexor Driver%')"
    $ConnectedAdapters =  Get-CimInstance -Class win32_NetworkAdapter -Filter `
        'NetConnectionStatus = 2'
    $VPNAdapters =  Get-CimInstance -Class Win32_NetworkAdapterConfiguration -Filter `
        "Description like '%pangp%' `
        or Description like '%cisco%'  `
        or Description like '%juniper%' `
        or Description like '%vpn%'"

    Foreach($Adapter in $ConnectedAdapters) {
        If($WirelessAdapters.InstanceName -contains $Adapter.Name)
        {
            $WirelessConnected = $true
        }
    }

    Foreach($Adapter in $ConnectedAdapters) {
        If($WiredAdapters.InstanceName -contains $Adapter.Name)
        {
            $WiredConnected = $true
        }
    }

    Foreach($Adapter in $ConnectedAdapters) {
        If($VPNAdapters.Index -contains $Adapter.DeviceID)
        {
            $VPNConnected = $true
        }
    }

    <#
    This doesn't work in SYSTEM context if they are not "All User" connections
    Try
    {
        $null = Get-Command Get-VPNConnection -ErrorAction Stop
        If((Get-VpnConnection | Where {$_.ConnectionStatus -eq "Connected"}))
        {
            $VPNConnected = $true
        }
    }
    Catch {}
    #>

    # Check known routes for corporate VPN connections
    $UKVPN = Get-NetRoute -DestinationPrefix 10.199.*
    $USVPN = Get-NetRoute -DestinationPrefix 10.98.*
    If ($UKVPN -or $USVPN)
    {
        $VPNConnected = $true
    }

    If(($WirelessConnected -ne $true) -and ($WiredConnected -eq $true)){ $ConnectionType="WIRED"}
    If(($WirelessConnected -eq $true) -and ($WiredConnected -eq $true)){$ConnectionType="WIRED AND WIRELESS"}
    If(($WirelessConnected -eq $true) -and ($WiredConnected -ne $true)){$ConnectionType="WIRELESS"}
    If($VPNConnected -eq $true){$ConnectionType="VPN"}

    Write-Output "$ConnectionType"
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
#endregion Functions

#####################
## Create Log File ##
#####################
$LogFile = "$WorkingDirectory\1909_Upgrade.log"
	
# Create the log file
If (!(Test-Path $LogFile))
{
    $null = New-Item $LogFile -Type File
}

#################################################
## Create Registry Keys if not already present ##
#################################################
$RootRegBase = "HKLM:\Software"
$RootRegBranchName = "IT"
$UpgradeBranchName = "1909Upgrade"
$FullRegPath = "$RootRegBase\$RootRegBranchName\$UpgradeBranchName"
$RegKeys = @(
    'CurrentStatus'
    'DistributionPoint'
    'DistributionPointLatency'
    'ClientType'
    'OSArchitecture'
    'OSVersion'
    'FreeDiskSpace'
    'Manufacturer'
    'Model'
    'ReadinessCheckResult'
    'ReadinessCheckFailureDetail'
    'ReadinessCheckTimestampUTC'
    'DownloadBandwidth'
    'CurrentConnectionType'
    'CorporateNetworkConnectivity'
    'OSName'
    'OSDescription'
    'OSProductKeyChannel'
    'OSLanguageCode'
    'OSLanguage'
    'ESDFileName'
    'ESDMD5Hash'
    'CurrentDownloadPercentComplete'
    'CurrentDownloadStartTime'
    'CurrentDownloadFinishTime'
    'WindowsUpdateBoxDownloadDuration'
    'ESDEstimatedDownloadDuration'
    'ESDDownloadDuration'
    'PreDownloadStartTime'
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
    'Deadline'
    'InstallStartTime'
    'InstallFinishTime'
    'InstallDuration'
    'InstallProcessExitCode'
    'FinalizeStartTime'
    'FinalizeFinishTime'
    'FinalizeDuration'
    'FinalizeProcessExitCode'
    'AzureCDNLatency'
    'DownloadLocation'
)
If (!(Test-Path $RootRegBase\$RootRegBranchName))
{
    $null = New-Item -Path $RootRegBase -Name $RootRegBranchName 
}
If (!(Test-Path $FullRegPath))
{
    $null = New-Item -Path $RootRegBase\$RootRegBranchName -Name $UpgradeBranchName 
    Write-UpgradeLog -Message "Creating registry keys at $FullRegPath"
}
Foreach ($RegKey in $RegKeys)
{
    If (!(Get-ItemProperty -Path $FullRegPath -Name $RegKey -ErrorAction SilentlyContinue))
    {
        $null = New-ItemProperty -Path $FullRegPath -Name $RegKey -PropertyType String
    }
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

########################
## Get Current Status ##
########################
$CurrentStatus = Get-ItemProperty -Path $FullRegPath -Name CurrentStatus | Select-Object -ExpandProperty CurrentStatus
If (!($CurrentStatus))
{
    Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Pending start" -Force
    $CurrentStatus = Get-ItemProperty -Path $FullRegPath -Name CurrentStatus | Select-Object -ExpandProperty CurrentStatus
}
Write-UpgradeLog -Message "Current status is $CurrentStatus"

##########################
## Run Readiness Checks ##
##########################
If ($CurrentStatus -eq "Pending start" -or $CurrentStatus -eq "Failed readiness checks")
{
    Write-UpgradeLog -Message "Running readiness checks"
    Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Running readiness checks" -Force
    $ProductType = Get-CimInstance -ClassName Win32_OperatingSystem -Property ProductType | Select -ExpandProperty ProductType
    Set-ItemProperty -Path $FullRegPath -Name ClientType -Value $ProductType -Force
    Write-UpgradeLog -Message "Client type is $ProductType"
    $OSArchitecture = Get-CimInstance -ClassName Win32_OperatingSystem -Property OSArchitecture | Select -ExpandProperty OSArchitecture
    Set-ItemProperty -Path $FullRegPath -Name OSArchitecture -Value $OSArchitecture -Force
    Write-UpgradeLog -Message "OS architecture is $OSArchitecture"
    $Version = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ReleaseID -ErrorAction Stop).ReleaseID
    Set-ItemProperty -Path $FullRegPath -Name OSVersion -Value $Version -Force
    Write-UpgradeLog -Message "OS version is $Version"
    $FreeSpace = [Math]::Round(((Get-CimInstance -ClassName Win32_Volume -Property FreeSpace,DriveLetter | Where {$_.DriveLetter -eq $env:SystemDrive} | Select -ExpandProperty FreeSpace) / 1MB),0)
    Set-ItemProperty -Path $FullRegPath -Name FreeDiskSpace -Value $FreeSpace -Force
    Write-UpgradeLog -Message "Free disk space on system drive is $FreeSpace`MB"
    $Make = Get-CimInstance -ClassName Win32_ComputerSystem -Property Manufacturer | Select -ExpandProperty Manufacturer
    Set-ItemProperty -Path $FullRegPath -Name Manufacturer -Value $Make -Force
    Write-UpgradeLog -Message "Manufacturer is $Make"
    $Model = Get-CimInstance -ClassName Win32_ComputerSystem -Property Model | Select -ExpandProperty Model
    Set-ItemProperty -Path $FullRegPath -Name Model -Value $Model -Force
    Write-UpgradeLog -Message "Model is $Model"
    $OSLanguageCode = Get-CimInstance -ClassName Win32_OperatingSystem -Property OSLanguage | Select -ExpandProperty OSLanguage
    Set-ItemProperty -Path $FullRegPath -Name OSLanguageCode -Value $OSLanguageCode -Force
    Write-UpgradeLog -Message "OS Language Code is $OSLanguageCode"
    Switch ($OSLanguageCode)
    {
        1033 {$OSLanguage = "en-US"}
        1034 {$OSLanguage = "de-DE"}
        2057 {$OSLanguage = "en-GB"}
        default {$OSLanguage = "Unknown"}
    }
    Set-ItemProperty -Path $FullRegPath -Name OSLanguage -Value $OSLanguage -Force
    Write-UpgradeLog -Message "OS Language is $OSLanguage"

    $Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
    Set-ItemProperty -Path $FullRegPath -Name ReadinessCheckTimestampUTC -Value $Timestamp -Force
    Write-UpgradeLog -Message "Readiness checks completed at $Timestamp"

    If ($ProductType -ne 1)
    {
        Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Failed readiness checks" -Force
        Set-ItemProperty -Path $FullRegPath -Name ReadinessCheckResult -Value "Failed" -Force
        Set-ItemProperty -Path $FullRegPath -Name ReadinessCheckFailureDetail -Value "Failed ProductType check - OS is not a client OS" -Force
        Write-UpgradeLog -Message "The ProductType readiness check failed. OS is not a client OS" -LogLevel 3
        Send-StatusUpdate
        Return
    }
    If ($OSArchitecture -ne "64-bit")
    {
        Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Failed readiness checks" -Force
        Set-ItemProperty -Path $FullRegPath -Name ReadinessCheckResult -Value "Failed" -Force
        Set-ItemProperty -Path $FullRegPath -Name ReadinessCheckFailureDetail -Value "Failed OSArchitecture check - OS is not 64-bit" -Force
        Write-UpgradeLog -Message "The OSArchitecture check failed. OS must be 64-bit" -LogLevel 3
        Send-StatusUpdate
        Return
    }
    If ($Version -eq "1909")
    {
        Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Failed readiness checks" -Force
        Set-ItemProperty -Path $FullRegPath -Name ReadinessCheckResult -Value "Failed" -Force
        Set-ItemProperty -Path $FullRegPath -Name ReadinessCheckFailureDetail -Value "Failed OSVersion check - OS is already 1909" -Force
        Write-UpgradeLog -Message "The OSVersion check failed. OS is already 1909" -LogLevel 3
        Send-StatusUpdate
        Return
    }
    If ($FreeSpace -lt 15000)
    {
        Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Failed readiness checks" -Force
        Set-ItemProperty -Path $FullRegPath -Name ReadinessCheckResult -Value "Failed" -Force
        Set-ItemProperty -Path $FullRegPath -Name ReadinessCheckFailureDetail -Value "Failed FreeDiskSpace check - System drive has $FreeSpace`MB free space but 15000MB is required" -Force
        Write-UpgradeLog -Message "The FreeDiskSpace check failed. System drive has $FreeSpace`MB free space but 15000MB is required" -LogLevel 3
        Send-StatusUpdate
        Return
    }
    Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Completed readiness checks" -Force
    Set-ItemProperty -Path $FullRegPath -Name ReadinessCheckResult -Value "Success" -Force
    Set-ItemProperty -Path $FullRegPath -Name ReadinessCheckFailureDetail -Value "" -Force
    Write-UpgradeLog -Message "Readiness checks have passed successfully"
    Send-StatusUpdate

    Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Checking internet connectivity" -Force
    $CurrentStatus = Get-ItemProperty -Path $FullRegPath -Name CurrentStatus | Select-Object -ExpandProperty CurrentStatus
}

######################
## OS Version Check ##
######################
# Before going any further, check that the OS has not already been upgraded
$Version = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ReleaseID -ErrorAction Stop).ReleaseID
Set-ItemProperty -Path $FullRegPath -Name OSVersion -Value $Version -Force
If ($Version -eq "1909")
{
    Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Already upgraded" -Force
    Write-UpgradeLog -Message "OS version is now $Version. Nothing more for us to do. Let's disable the scheduled tasks and wait for the cleanup script to run."
    Send-StatusUpdate
    $ScheduledTasks = @(
        'Windows 10 Upgrade Notification'
        'Windows 10 Upgrade PreDownload'
        'Windows 10 Upgrade Preparer'
    )
    Foreach ($ScheduledTask in $ScheduledTasks)
    { 
        try 
        {
            Unregister-ScheduledTask -TaskName $ScheduledTask -ErrorAction Stop
            Write-UpgradeLog -Message "Unregistered scheduled task '$ScheduledTask'"
        }
        catch 
        {
            Write-UpgradeLog -Message "Failed to unregister scheduled task '$ScheduledTask'" -LogLevel 2
        }
        
    }
    Return
}

#################################
## Check Internet Connectivity ##
#################################
$InternetConnectivity = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
If ($InternetConnectivity)
{
    Write-UpgradeLog -Message "Connected to internet"
}
else
{
    Write-UpgradeLog -Message "No connectivity to internet. Exiting script" -LogLevel 2
    Return
}

##################################
## Determine Internet Bandwidth ##
##################################
$DownloadBandwidth = Get-ItemProperty -Path $FullRegPath -Name DownloadBandwidth | Select-Object -ExpandProperty DownloadBandwidth
If (!($DownloadBandwidth))
{
    Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Checking internet bandwidth" -Force
    #$CurrentStatus = Get-ItemProperty -Path $FullRegPath -Name CurrentStatus | Select-Object -ExpandProperty CurrentStatus
    Write-UpgradeLog -Message "Downloading a 100MB file from the Azure CDN to measure realistic bandwidth"
    $Stopwatch = New-Object System.Diagnostics.Stopwatch
    $Stopwatch.Start()
        Invoke-WebRequest -Uri "https://myCDNendpoint.windows.net/w10-1909-upgrade/100MB.bin" -UseBasicParsing  -OutFile $env:TEMP\100MB.bin
    $Stopwatch.Stop()
    Remove-Item -Path $env:TEMP\100MB.bin -Force
    $Bandwidth = [math]::Round((100 / $Stopwatch.Elapsed.TotalSeconds) * 8,2)
    $ApproximateESDDownloadDuration = [Timespan]::FromSeconds(3371.415 / (100 / $Stopwatch.Elapsed.TotalSeconds))
    Write-UpgradeLog -Message "CDN download bandwidth is $Bandwidth`Mbps"
    Set-ItemProperty -Path $FullRegPath -Name DownloadBandwidth -Value "$Bandwidth`Mbps" -Force
    Write-UpgradeLog -Message "Approximate time to download the ESD file will be $($ApproximateESDDownloadDuration.Hours) hours $($ApproximateESDDownloadDuration.Minutes) minutes"
    Set-ItemProperty -Path $FullRegPath -Name ESDEstimatedDownloadDuration -Value "$($ApproximateESDDownloadDuration.Hours) hours $($ApproximateESDDownloadDuration.Minutes) minutes" -Force
    Send-StatusUpdate
}

#################################
## Determine Azure CDN Latency ##
#################################
$AzureLatency = Get-ItemProperty -Path $FullRegPath -Name AzureCDNLatency | Select-Object -ExpandProperty AzureCDNLatency
If (!($AzureLatency))
{
    Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Testing Azure CDN latency" -Force
    Write-UpgradeLog -Message "Testing latency to the Azure CDN"
    $result = & $WorkingDirectory\psping.exe myCDNendpoint.windows.net:443 -accepteula
    $AzureCDNLatency = ($result | Select-String "Average").ToString().split()[-1]
    Set-ItemProperty -Path  $FullRegPath -Name AzureCDNLatency -Value "$AzureCDNLatency" -Force
    Write-UpgradeLog -Message "Latency to Azure CDN is $AzureCDNLatency"
}

#######################################
## Determine Network Connection Type ##
#######################################
Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Determining network connection type" -Force
$CurrentStatus = Get-ItemProperty -Path $FullRegPath -Name CurrentStatus | Select-Object -ExpandProperty CurrentStatus
$CurrentConnectionType = Get-CurrentConnectionType
Write-UpgradeLog -Message "Current network connection type is: $CurrentConnectionType"
Set-ItemProperty -Path $FullRegPath -Name CurrentConnectionType -Value "$CurrentConnectionType" -Force

##########################################
## Check Corporate Network Connectivity ##
##########################################
Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Checking corporate network connectivity" -Force
$CurrentStatus = Get-ItemProperty -Path $FullRegPath -Name CurrentStatus | Select-Object -ExpandProperty CurrentStatus
$CorporateConnectivity = Test-NetConnection -ComputerName MyOn-PremServer.MyCompany.org -InformationLevel Quiet
If ($CorporateConnectivity -eq $True)
{
    Write-UpgradeLog -Message "Connected to corporate network"
}
else 
{
    Write-UpgradeLog -Message "Not connected to corporate network"
}
Set-ItemProperty -Path $FullRegPath -Name CorporateNetworkConnectivity -Value "$CorporateConnectivity" -Force

############################################
## FIND LOWEST LATENCY DISTRIBUTION POINT ##
############################################
# If connected to corporate network and not by VPN, pings all the ConfigMgr DPs to find the one with the lowest latency for the client
$DistributionPoint = Get-ItemProperty -Path $FullRegPath -Name DistributionPoint | Select-Object -ExpandProperty DistributionPoint
If ((!($DistributionPoint) -and $CorporateConnectivity -eq $true -and $CurrentConnectionType -ne "VPN"))
{
    Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Finding lowest latency distribution point" -Force
    $CurrentStatus = Get-ItemProperty -Path $FullRegPath -Name CurrentStatus | Select-Object -ExpandProperty CurrentStatus
    Send-StatusUpdate
    Write-UpgradeLog -Message "Testing latency to ConfigMgr distribution points"
    $PingResults = New-Object System.Collections.ArrayList
    $Stopwatch = New-Object System.Diagnostics.Stopwatch
    $Stopwatch.Start()
    foreach ($DP in $ConfigMgrDistributionPoints)
    {
        $Test = Test-Connection $DP -Count 4 -ErrorAction SilentlyContinue
        If ($Test)
        {
            $Average = ($Test.ResponseTime | Measure-Object -Average).Average
            [void]$PingResults.Add([PSCustomObject]@{
                Name = $DP
                Latency = $Average
            })
        }
    }
    $Stopwatch.Stop()
    Write-UpgradeLog -Message "Completed testing latency to ConfigMgr distribution points in $($Stopwatch.Elapsed.Minutes) minutes and $($Stopwatch.Elapsed.Seconds) seconds"
    $FastestDP = $PingResults | Sort Latency | Select -First 1
    Write-UpgradeLog -Message "Distribution point with the lowest latency is $($FastestDP.Name) at $($FastestDP.Latency)ms"
    Set-ItemProperty -Path  $FullRegPath -Name DistributionPoint -Value $FastestDP.Name -Force
    Set-ItemProperty -Path  $FullRegPath -Name DistributionPointLatency -Value "$($FastestDP.Latency)ms" -Force
}

#######################################
## Determine Consumer or Business OS ##
#######################################
$OSProductKey = Get-ItemProperty -Path $FullRegPath -Name OSProductKeyChannel | Select-Object -ExpandProperty OSProductKeyChannel
If (!($OSProductKey))
{
    Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Determining if consumer or business OS" -Force
    $CurrentStatus = Get-ItemProperty -Path $FullRegPath -Name CurrentStatus | Select-Object -ExpandProperty CurrentStatus
    $LicenceInfo = & "$env:SystemRoot\System32\cscript.exe" "$env:Systemroot\System32\slmgr.vbs" /dlv
    $OSName = ($LicenceInfo | Select-String "Name")[0].ToString().Split(':')[1].Trim()
    $OSDescription = ($LicenceInfo | Select-String "Description").ToString().Split(':')[1].Trim()
    $OSProductKeyChannel = ($LicenceInfo | Select-String "Product Key Channel").ToString().Split()[3].Trim()
    Set-ItemProperty -Path  $FullRegPath -Name OSName -Value $OSName -Force
    Write-UpgradeLog -Message "OS Name is '$OSName'"
    Set-ItemProperty -Path  $FullRegPath -Name OSDescription -Value $OSDescription -Force
    Write-UpgradeLog -Message "OS Description is '$OSDescription'"
    Set-ItemProperty -Path  $FullRegPath -Name OSProductKeyChannel -Value $OSProductKeyChannel -Force
    Write-UpgradeLog -Message "OS Product Key Channel is '$OSProductKeyChannel'"
}

##########################################
## Determine which ESD file to download ##
##########################################
$ESDFile = Get-ItemProperty -Path $FullRegPath -Name ESDFileName | Select-Object -ExpandProperty ESDFileName
$ESDMD5Hash = Get-ItemProperty -Path $FullRegPath -Name ESDMD5Hash | Select-Object -ExpandProperty ESDMD5Hash
If (!($ESDFile) -or !($ESDMD5Hash))
{
    Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Determining which ESD file to download" -Force
    $CurrentStatus = Get-ItemProperty -Path $FullRegPath -Name CurrentStatus | Select-Object -ExpandProperty CurrentStatus
    $OSLanguageCode = Get-ItemProperty -Path $FullRegPath -Name OSLanguageCode | Select-Object -ExpandProperty OSLanguageCode
    $OSProductKeyChannel = Get-ItemProperty -Path $FullRegPath -Name OSProductKeyChannel | Select-Object -ExpandProperty OSProductKeyChannel
    If ($OSLanguageCode -eq 1033 -and ($OSProductKeyChannel -match "OEM" -or $OSProductKeyChannel -match "Retail"))
    {
        $ESDFile = "18363.1139.201008-0514.19h2_release_svc_refresh_clientconsumer_RET_x64fre_en-us.esd"
        $ESDMD5Hash = "0BD6275F338628D8083C6140477D87C5"
    }
    If ($OSLanguageCode -eq 1033 -and $OSProductKeyChannel -match "Volume")
    {
        $ESDFile = "18363.1139.201008-0514.19h2_release_svc_refresh_clientbusiness_VOL_x64fre_en-us.esd"
        $ESDMD5Hash = "993CCD835B303A5A4D6FEC54BDFEDA71"
    }
    If ($OSLanguageCode -eq 2057 -and ($OSProductKeyChannel -match "OEM" -or $OSProductKeyChannel -match "Retail"))
    {
        $ESDFile = "18363.1139.201008-0514.19h2_release_svc_refresh_clientconsumer_RET_x64fre_en-gb.esd"
        $ESDMD5Hash = "08585405C48A8F0A5DCF2E8691970E67"
    }
    If ($OSLanguageCode -eq 2057 -and $OSProductKeyChannel -match "Volume")
    {
        $ESDFile = "18363.1139.201008-0514.19h2_release_svc_refresh_clientbusiness_VOL_x64fre_en-gb.esd"
        $ESDMD5Hash = "D95B05EC34F04AE1989D124CC308023C"
    }
    If ($OSLanguageCode -eq 1031 -and ($OSProductKeyChannel -match "OEM" -or $OSProductKeyChannel -match "Retail"))
    {
        $ESDFile = "18363.1139.201008-0514.19h2_release_svc_refresh_clientconsumer_RET_x64fre_de-de.esd"
        $ESDMD5Hash = "339830EA066A563CFC0FF429D8694826"
    }
    Set-ItemProperty -Path  $FullRegPath -Name ESDFileName -Value $ESDFile -Force
    Write-UpgradeLog -Message "ESD file to be used is '$ESDFile'"
    Set-ItemProperty -Path  $FullRegPath -Name ESDMD5Hash -Value $ESDMD5Hash -Force
    Write-UpgradeLog -Message "ESD file MD5 hash is '$ESDMD5Hash'"
}

###################################
## Download WindowsUpdateBox.exe ##
###################################
$File = "WindowsUpdateBox.exe"
$WindowsUpdateBoxMD5Hash = "4C819FCE37A518E1A67092A1697681A7"
If (!(Test-Path "$WorkingDirectory\$file") -or ((Get-FileHash -Path "$WorkingDirectory\$file" -Algorithm MD5 -ErrorAction SilentlyContinue).Hash -ne $WindowsUpdateBoxMD5Hash))
{
    Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Downloading WindowsUpdateBox.exe" -Force
    Write-UpgradeLog -Message "Downloading WindowsUpdateBox.exe"
    Set-ItemProperty -Path  $FullRegPath -Name CurrentDownloadPercentComplete -Value 0 -Force
    $CurrentStatus = Get-ItemProperty -Path $FullRegPath -Name CurrentStatus | Select-Object -ExpandProperty CurrentStatus
    $Stopwatch = New-Object System.Diagnostics.Stopwatch
    $Stopwatch.Start()
    $BitsJob = Start-BitsTransfer -Source "$CDNEndPointURI/$File" -Destination "$WorkingDirectory\$File" -Priority Foreground -Asynchronous -RetryInterval 60 -DisplayName "WindowsUpdateBox"
    do {
        $Progress = [Math]::Round((100 * ($BitsJob.BytesTransferred / $BitsJob.BytesTotal)),2)
        Start-Sleep -Seconds 1
        Set-ItemProperty -Path  $FullRegPath -Name CurrentDownloadPercentComplete -Value $Progress -Force
        Write-UpgradeLog -Message "Downloading WindowsUpdateBox.exe: $Progress`%"
    } until ($BitsJob.JobState -eq "Transferred")
    Complete-BitsTransfer -BitsJob $BitsJob
    $Stopwatch.Stop()
    Set-ItemProperty -Path  $FullRegPath -Name CurrentDownloadPercentComplete -Value 100 -Force
    Write-UpgradeLog -Message "Downloading WindowsUpdateBox.exe: 100%"
    Set-ItemProperty -Path  $FullRegPath -Name WindowsUpdateBoxDownloadDuration -Value "$($Stopwatch.Elapsed.Minutes) minutes $($Stopwatch.Elapsed.Seconds) seconds" -Force
    Write-UpgradeLog -Message "Downloaded WindowsUpdateBox.exe in $($Stopwatch.Elapsed.Minutes) minutes $($Stopwatch.Elapsed.Seconds) seconds"
    $Hash = (Get-FileHash -Path "$WorkingDirectory\$File" -Algorithm MD5).Hash
    If ($Hash -eq $WindowsUpdateBoxMD5Hash)
    {
        Write-UpgradeLog -Message "MD5 hash on WindowsUpdateBox.exe is correct"
        Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Downloading ESD file" -Force
        $CurrentStatus = Get-ItemProperty -Path $FullRegPath -Name CurrentStatus | Select-Object -ExpandProperty CurrentStatus
    }
    else 
    {
        Write-UpgradeLog -Message "MD5 hash on WindowsUpdateBox.exe is incorrect. Will try download again later. Exiting script." -LogLevel 3
        Return
    }
}

#########################################
## Determine Download Location for ESD ##
#########################################
[double]$DPLatency = (Get-ItemProperty -Path $FullRegPath -Name DistributionPointLatency | Select-Object -ExpandProperty DistributionPointLatency).TrimEnd('ms')
[double]$CDNLatency = (Get-ItemProperty -Path $FullRegPath -Name AzureCDNLatency | Select-Object -ExpandProperty AzureCDNLatency).TrimEnd('ms')
$DistributionPoint = Get-ItemProperty -Path $FullRegPath -Name DistributionPoint | Select-Object -ExpandProperty DistributionPoint
$CurrentConnectionType = Get-ItemProperty -Path $FullRegPath -Name CurrentConnectionType | Select-Object -ExpandProperty CurrentConnectionType

If ($DistributionPoint)
{
    $DPResult = Test-Connection -ComputerName $DistributionPoint -Quiet
}
If (!($DPLatency))
{
    $DownloadLocation = "AzureCDN"
}
ElseIf ($DPLatency -lt $CDNLatency)
{
    If ($DPResult -eq $True -and $CurrentConnectionType -ne "VPN")
    {
        $DownloadLocation = "DistributionPoint"
    }
    else 
    {
        $DownloadLocation = "AzureCDN"
    }
}
else 
{
    $DownloadLocation = "AzureCDN"
}
Write-UpgradeLog -Message "Download location will be $DownloadLocation as it has the lowest latency of available sources"
Set-ItemProperty -Path  $FullRegPath -Name DownloadLocation -Value "$DownloadLocation" -Force

#################################
## Download Feature Update ESD ##
#################################
$ESDFileName = Get-ItemProperty -Path $FullRegPath -Name ESDFileName | Select-Object -ExpandProperty ESDFileName
$ESDMD5Hash = Get-ItemProperty -Path $FullRegPath -Name ESDMD5Hash | Select-Object -ExpandProperty ESDMD5Hash
If (!(Test-Path "$WorkingDirectory\$ESDFileName") -or ((Get-FileHash -Path "$WorkingDirectory\$ESDFileName" -Algorithm MD5 -ErrorAction SilentlyContinue).Hash -ne $ESDMD5Hash))
{
    Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Downloading ESD file" -Force
    Send-StatusUpdate
    Write-UpgradeLog -Message "Downloading ESD file"
    Set-ItemProperty -Path  $FullRegPath -Name CurrentDownloadPercentComplete -Value 0 -Force
    # Check for existing bits job
    $BitsJob = Get-BitsTransfer -Name "ESD File" -ErrorAction SilentlyContinue
    If ($BitsJob)
    {
        # If in action state, exit script
        If ($BitsJob.JobState -in ("Suspended", "Queued", "Connecting", "Transient Error"))
        {
            Write-UpgradeLog -Message "An existing BITS job was found in the state '$($BitsJob.JobState)'. The computer may have been restarted or lost connectivity during the download. We'll wait 5 minutes to see if it resumes, if not exit and retry later."
            Start-Sleep -Seconds 300
            $BitsJob = Get-BitsTransfer -Name "ESD File" -ErrorAction SilentlyContinue
            If ($BitsJob.JobState -eq "Transferring")
            {
                Write-UpgradeLog -Message "Previous BITS job is now running again...continuing logging"
                $Progress = [Math]::Round((100 * ($BitsJob.BytesTransferred / $BitsJob.BytesTotal)),2)
                Set-ItemProperty -Path  $FullRegPath -Name CurrentDownloadPercentComplete -Value $Progress -Force
                Write-UpgradeLog -Message "Downloading $ESDFilename`: $Progress`%"
            }
            ElseIf ($BitsJob.JobState -eq "Transferred")
            { }
            Else
            {
                Return
            }
        }
        ElseIf ($BitsJob.JobState -eq "Transferring" -or $BitsJob.JobState -eq "Transferred")
        {
            Write-UpgradeLog -Message "A previous BITS job is still active...continuing logging"
            $Progress = [Math]::Round((100 * ($BitsJob.BytesTransferred / $BitsJob.BytesTotal)),2)
            Set-ItemProperty -Path  $FullRegPath -Name CurrentDownloadPercentComplete -Value $Progress -Force
            Write-UpgradeLog -Message "Downloading $ESDFilename`: $Progress`%"
        }
        else 
        {
            Remove-BitsTransfer -BitsJob $BitsJob
            Remove-Variable BitsJob    
        }
    }
    # 
    If ($DownloadLocation -eq "DistributionPoint")
    {
        If (!($BitsJob))
        {
            # Download from Distribution Point
            $DistributionPoint = (Get-ItemProperty -Path $FullRegPath -Name DistributionPoint | Select-Object -ExpandProperty DistributionPoint).ToLower()
            Write-UpgradeLog -Message "Using ConfigMgr distribution point: $DistributionPoint"
            # Prepare credentials
            $DecryptedString1 = Get-ItemProperty -Path HKCU:\Software\-Name String1 -ErrorAction SilentlyContinue | Select -ExpandProperty String1 | ConvertTo-SecureString
            $DecryptedString2 = Get-ItemProperty -Path HKCU:\Software\-Name String2 -ErrorAction SilentlyContinue | Select -ExpandProperty String2 | ConvertTo-SecureString
            $Credentials = New-Object System.Management.Automation.PSCredential -ArgumentList (([PSCredential]::new("Data",$DecryptedString1).GetNetworkCredential().Password), $DecryptedString2)
            # Determine ContentID for ESD file
            Switch ($ESDFileName)
            {
                "18363.1139.201008-0514.19h2_release_svc_refresh_clientconsumer_RET_x64fre_en-us.esd" {$ContentID = "f8c164f8-4007-4dbb-ad5c-5bae39cd0c2f"}
                "18363.1139.201008-0514.19h2_release_svc_refresh_clientbusiness_VOL_x64fre_en-us.esd" {$ContentID = "e69f3a03-cb4f-47ab-9b35-7fb261a84cc5"}
                "18363.1139.201008-0514.19h2_release_svc_refresh_clientconsumer_RET_x64fre_en-gb.esd" {$ContentID = "a278c2af-9054-46e6-94ac-e9660911a417"}
                "18363.1139.201008-0514.19h2_release_svc_refresh_clientbusiness_VOL_x64fre_en-gb.esd" {$ContentID = "f67852f5-c9d1-4314-88d4-76349dbded30"}
                "18363.1139.201008-0514.19h2_release_svc_refresh_clientconsumer_RET_x64fre_de-de.esd" {$ContentID = "61d41a05-ac28-4dce-8ede-279685160769"}
                
            }
            $URI = "http://$DistributionPoint/SMS_DP_SMSPKG$/$ContentID/$ESDFileName"
            Write-UpgradeLog -Message "URL is $URI"
            $Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
            Set-ItemProperty -Path $FullRegPath -Name CurrentDownloadStartTime -Value $Timestamp -Force
            $BitsJob = Start-BitsTransfer -Source $URI -Destination "$WorkingDirectory\$ESDFileName" -Priority Foreground -Asynchronous -RetryInterval 60 -DisplayName "ESD File" -Credential $Credentials -Authentication Negotiate
        }
        do {
            $Progress = [Math]::Round((100 * ($BitsJob.BytesTransferred / $BitsJob.BytesTotal)),2)
            Start-Sleep -Seconds 60
            Set-ItemProperty -Path  $FullRegPath -Name CurrentDownloadPercentComplete -Value $Progress -Force
            Write-UpgradeLog -Message "Downloading $ESDFilename`: $Progress`%"
        } until ($BitsJob.JobState -eq "Transferred" -or $BitsJob.JobState -eq "Error")
        If ($BitsJob.JobState -eq "Error")
        {
            Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "BITS job error" -Force
            Write-UpgradeLog -Message "BITS job was found in an error state." -LogLevel 3
            Write-UpgradeLog -Message "BITS job error description: $($BitsJob.ErrorDescription)" -LogLevel 3
            Write-UpgradeLog -Message "We'll exit the script for this run. Perhaps the error will be corrected on the next run." -LogLevel 2
            Send-StatusUpdate
            Return
        }
        Complete-BitsTransfer -BitsJob $BitsJob
        Set-ItemProperty -Path  $FullRegPath -Name CurrentDownloadPercentComplete -Value 100 -Force
        Write-UpgradeLog -Message "Downloading $ESDFilename`: 100%"
        $Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
        Set-ItemProperty -Path $FullRegPath -Name CurrentDownloadFinishTime -Value $Timestamp -Force
        $StartTime = Get-Date (Get-ItemProperty -Path $FullRegPath -Name CurrentDownloadStartTime | Select -ExpandProperty CurrentDownloadStartTime)
        $FinishTime = Get-Date (Get-ItemProperty -Path $FullRegPath -Name CurrentDownloadFinishTime | Select -ExpandProperty CurrentDownloadFinishTime)
        $Duration = ($FinishTime - $StartTime)
        Set-ItemProperty -Path  $FullRegPath -Name ESDDownloadDuration -Value "$($Duration.Hours) hours $($Duration.Minutes) minutes $($Duration.Seconds) seconds" -Force
        Write-UpgradeLog -Message "Downloaded $ESDFilename in $($Duration.Hours) hours $($Duration.Minutes) minutes $($Duration.Seconds) seconds"
        Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Calculating ESD Hash" -Force
        Write-UpgradeLog -Message "Calculating ESD hash value"
        Send-StatusUpdate
        $Hash = (Get-FileHash -Path "$WorkingDirectory\$ESDFilename" -Algorithm MD5).Hash
        If ($Hash -eq $ESDMD5Hash)
        {
            Write-UpgradeLog -Message "MD5 hash on $ESDFilename is correct"
            Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Ready for compat scan" -Force
            Disable-ScheduledTask -TaskName "Windows 10 Upgrade Preparer"
            Register-ScheduledTask -Xml (Get-Content "$WorkingDirectory\Windows 10 Upgrade PreDownload.xml" | out-string) -TaskName "Windows 10 Upgrade PreDownload" -Force
            Start-ScheduledTask -TaskName "Windows 10 Upgrade PreDownload"
            #$CurrentStatus = Get-ItemProperty -Path $FullRegPath -Name CurrentStatus | Select-Object -ExpandProperty CurrentStatus
        }
        else 
        {
            Write-UpgradeLog -Message "MD5 hash on $ESDFilename is incorrect. Will try download again later. Exiting script." -LogLevel 3
            Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Retry download due to incorrect ESD Hash" -Force
            Send-StatusUpdate
            Return
        }
    }
    else 
    {
        If (!($BitsJob))
        {
            # Download from Azure CDN
            Write-UpgradeLog -Message "Using Azure CDN"
            $Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
            Set-ItemProperty -Path $FullRegPath -Name CurrentDownloadStartTime -Value $Timestamp -Force
            $BitsJob = Start-BitsTransfer -Source "$CDNEndPointURI/$ESDFileName" -Destination "$WorkingDirectory\$ESDFileName" -Priority Foreground -Asynchronous -RetryInterval 60 -DisplayName "ESD File"
        }
        do {
            $Progress = [Math]::Round((100 * ($BitsJob.BytesTransferred / $BitsJob.BytesTotal)),2)
            Start-Sleep -Seconds 60
            Set-ItemProperty -Path  $FullRegPath -Name CurrentDownloadPercentComplete -Value $Progress -Force
            Write-UpgradeLog -Message "Downloading $ESDFilename`: $Progress`%"
        } until ($BitsJob.JobState -eq "Transferred" -or $BitsJob.JobState -eq "Error")
        If ($BitsJob.JobState -eq "Error")
        {
            Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "BITS job error" -Force
            Write-UpgradeLog -Message "BITS job was found in an error state." -LogLevel 3
            Write-UpgradeLog -Message "BITS job error description: $($BitsJob.ErrorDescription)" -LogLevel 3
            Write-UpgradeLog -Message "We'll exit the script for this run. Perhaps the error will be corrected on the next run." -LogLevel 2
            Send-StatusUpdate
            Return
        }
        Complete-BitsTransfer -BitsJob $BitsJob
        Set-ItemProperty -Path  $FullRegPath -Name CurrentDownloadPercentComplete -Value 100 -Force
        Write-UpgradeLog -Message "Downloading $ESDFilename`: 100%"
        $Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
        Set-ItemProperty -Path $FullRegPath -Name CurrentDownloadFinishTime -Value $Timestamp -Force
        $StartTime = Get-Date (Get-ItemProperty -Path $FullRegPath -Name CurrentDownloadStartTime | Select -ExpandProperty CurrentDownloadStartTime)
        $FinishTime = Get-Date (Get-ItemProperty -Path $FullRegPath -Name CurrentDownloadFinishTime | Select -ExpandProperty CurrentDownloadFinishTime)
        $Duration = ($FinishTime - $StartTime)
        Set-ItemProperty -Path  $FullRegPath -Name ESDDownloadDuration -Value "$($Duration.Hours) hours $($Duration.Minutes) minutes $($Duration.Seconds) seconds" -Force
        Write-UpgradeLog -Message "Downloaded $ESDFilename in $($Duration.Hours) hours $($Duration.Minutes) minutes $($Duration.Seconds) seconds"
        Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Calculating ESD Hash" -Force
        Write-UpgradeLog -Message "Calculating ESD hash value"
        Send-StatusUpdate
        $Hash = (Get-FileHash -Path "$WorkingDirectory\$ESDFilename" -Algorithm MD5).Hash
        If ($Hash -eq $ESDMD5Hash)
        {
            Write-UpgradeLog -Message "MD5 hash on $ESDFilename is correct"
            Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Ready for compat scan" -Force
            try 
            {
                Disable-ScheduledTask -TaskName "Windows 10 Upgrade Preparer" -ErrorAction Stop
                Write-UpgradeLog -Message "Disabled scheduled task 'Windows 10 Upgrade Preparer'"
            }
            catch 
            {
                Write-UpgradeLog -Message "Failed to disabled scheduled task 'Windows 10 Upgrade Preparer'" -loglevel 2
            }
            try 
            {
                Register-ScheduledTask -Xml (Get-Content "$WorkingDirectory\Windows 10 Upgrade PreDownload.xml" | out-string) -TaskName "Windows 10 Upgrade PreDownload" -Force -ErrorAction Stop
                Write-UpgradeLog -Message "Registered scheduled task 'Windows 10 Upgrade PreDownload'"
            }
            catch 
            {
                Write-UpgradeLog -Message "Failed to register scheduled task 'Windows 10 Upgrade PreDownload'" -loglevel 2
            }
            try 
            {
                Start-ScheduledTask -TaskName "Windows 10 Upgrade PreDownload" -ErrorAction Stop
                Write-UpgradeLog -Message "Started scheduled task 'Windows 10 Upgrade PreDownload'"
            }
            catch 
            {
                Write-UpgradeLog -Message "Failed to start scheduled task 'Windows 10 Upgrade PreDownload'" -loglevel 2
            }           
        }
        else 
        {
            Write-UpgradeLog -Message "MD5 hash on $ESDFilename is incorrect. Will try download again later. Exiting script." -LogLevel 3
            Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Retry download due to incorrect ESD Hash" -Force
            Send-StatusUpdate
            Return
        }
    }
}

Write-UpgradeLog -Message "Sending status message and exiting preparation script"
Send-StatusUpdate