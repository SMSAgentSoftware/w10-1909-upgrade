using namespace System.Net
using namespace System.Data
using namespace System.Data.SqlClient

param($eventGridEvent, $TriggerMetadata)

# Output basic info about this execution
Write-Host "Updating entry for $($eventGridEvent.data.ComputerName) (Serial Number: $($eventGridEvent.data.SerialNumber))"

# Retrieve some variables
$MSI_ENDPOINT = [System.Environment]::GetEnvironmentVariable("MSI_ENDPOINT")
$MSI_SECRET = [System.Environment]::GetEnvironmentVariable("MSI_SECRET")
$ConnectionString = [System.Environment]::GetEnvironmentVariable("sqldb_Connection")

# Obtain access token for function app managed identity for database audience
$tokenAuthURI = "$MSI_ENDPOINT`?resource=https://database.windows.net/&api-version=2017-09-01"
$tokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret"="$MSI_SECRET"} -Uri $tokenAuthURI
$accessToken = $tokenResponse.access_token

# Add quotes around the data for SQL (except for dates)
$CurrentDate = Get-Date -Format "o"
$CurrentStatus = "'" + $eventGridEvent.data.CurrentStatus + "'"
$DistributionPoint = "'" + $eventGridEvent.data.DistributionPoint + "'"
$DistributionPointLatency = "'" + $eventGridEvent.data.DistributionPointLatency + "'"
$ClientType = "'" + $eventGridEvent.data.ClientType + "'"
$OSArchitecture = "'" + $eventGridEvent.data.OSArchitecture + "'"
$OSVersion = "'" + $eventGridEvent.data.OSVersion + "'"
$FreeDiskSpace = "'" + $eventGridEvent.data.FreeDiskSpace + "'"
$Manufacturer = "'" + $eventGridEvent.data.Manufacturer + "'"
$Model = "'" + $eventGridEvent.data.Model + "'"
$ReadinessCheckResult = "'" + $eventGridEvent.data.ReadinessCheckResult + "'"
$ReadinessCheckFailureDetail = "'" + $eventGridEvent.data.ReadinessCheckFailureDetail + "'"
$ReadinessCheckTimestampUTC = $eventGridEvent.data.ReadinessCheckTimestampUTC
$DownloadBandwidth = "'" + $eventGridEvent.data.DownloadBandwidth + "'"
$CurrentConnectionType = "'" + $eventGridEvent.data.CurrentConnectionType + "'"
$CorporateNetworkConnectivity = "'" + $eventGridEvent.data.CorporateNetworkConnectivity + "'"
$OSName = "'" + $eventGridEvent.data.OSName + "'"
$OSDescription = "'" + $eventGridEvent.data.OSDescription + "'"
$OSProductKeyChannel = "'" + $eventGridEvent.data.OSProductKeyChannel + "'"
$OSLanguageCode = "'" + $eventGridEvent.data.OSLanguageCode + "'"
$OSLanguage = "'" + $eventGridEvent.data.OSLanguage + "'"
$ESDFileName = "'" + $eventGridEvent.data.ESDFileName + "'"
$ESDMD5Hash = "'" + $eventGridEvent.data.ESDMD5Hash + "'"
$CurrentDownloadPercentComplete = "'" + $eventGridEvent.data.CurrentDownloadPercentComplete + "'"
$CurrentDownloadStartTime = $eventGridEvent.data.CurrentDownloadStartTime
$CurrentDownloadFinishTime = $eventGridEvent.data.CurrentDownloadFinishTime
$WindowsUpdateBoxDownloadDuration = "'" + $eventGridEvent.data.WindowsUpdateBoxDownloadDuration + "'"
$ESDDownloadDuration = "'" + $eventGridEvent.data.ESDDownloadDuration + "'"
$PreDownloadStartTime = $eventGridEvent.data.PreDownloadStartTime
$PreDownloadFinishTime = $eventGridEvent.data.PreDownloadFinishTime
$PreDownloadDuration = "'" + $eventGridEvent.data.PreDownloadDuration + "'"
$PreDownloadProcessExitCode = "'" + $eventGridEvent.data.PreDownloadProcessExitCode + "'"
$FailureCount = "'" + $eventGridEvent.data.FailureCount + "'"
$BoxResult = "'" + $eventGridEvent.data.BoxResult  + "'"
$SetUpDiagFailureDetails = "'" + $eventGridEvent.data.SetUpDiagFailureDetails  + "'"
$SetupDiagFailureData = "'" + $eventGridEvent.data.SetupDiagFailureData + "'"
$SetupDiagProfileName = "'" + $eventGridEvent.data.SetupDiagProfileName + "'"
$SetupDiagRemediation = "'" + $eventGridEvent.data.SetupDiagRemediation + "'"
$SetupDiagDateTime = $eventGridEvent.data.SetupDiagDateTime
$HardBlockFound = "'" + $eventGridEvent.data.HardBlockFound + "'"
$HardBlockTitle = "'" + $eventGridEvent.data.HardBlockTitle + "'"
$HardBlockMessage = "'" + $eventGridEvent.data.HardBlockMessage + "'"
$Deadline = $eventGridEvent.data.Deadline
$InstallStartTime = $eventGridEvent.data.InstallStartTime
$InstallFinishTime = $eventGridEvent.data.InstallFinishTime
$InstallDuration = "'" + $eventGridEvent.data.InstallDuration + "'"
$InstallProcessExitCode = "'" + $eventGridEvent.data.InstallProcessExitCode + "'"
$FinalizeStartTime = $eventGridEvent.data.FinalizeStartTime
$FinalizeFinishTime = $eventGridEvent.data.FinalizeFinishTime
$FinalizeDuration = "'" + $eventGridEvent.data.FinalizeDuration + "'"
$FinalizeProcessExitCode = "'" + $eventGridEvent.data.FinalizeProcessExitCode + "'"
$SerialNumber = "'" + $eventGridEvent.data.SerialNumber + "'"
$DownloadLocation = "'" + $eventGridEvent.data.DownloadLocation + "'"
$AzureCDNLatency = "'" + $eventGridEvent.data.AzureCDNLatency + "'"
$ESDEstimatedDownloadDuration = "'" + $eventGridEvent.data.ESDEstimatedDownloadDuration + "'"

# Convert the dates to SQL friendly format
If ($ReadinessCheckTimestampUTC -ne "NULL"){$ReadinessCheckTimestampUTC = "'" + ($ReadinessCheckTimestampUTC | Get-Date -Format "o") + "'"}
If ($CurrentDownloadStartTime -ne "NULL"){$CurrentDownloadStartTime = "'" + ($CurrentDownloadStartTime | Get-Date -Format "o") + "'"}
If ($CurrentDownloadFinishTime -ne "NULL"){$CurrentDownloadFinishTime = "'" + ($CurrentDownloadFinishTime | Get-Date -Format "o") + "'"}
If ($PreDownloadStartTime -ne "NULL"){$PreDownloadStartTime = "'" + ($PreDownloadStartTime | Get-Date -Format "o") + "'"}
If ($PreDownloadFinishTime -ne "NULL"){$PreDownloadFinishTime = "'" + ($PreDownloadFinishTime | Get-Date -Format "o") + "'"}
If ($SetupDiagDateTime -ne "NULL"){$SetupDiagDateTime = "'" + ($SetupDiagDateTime | Get-Date -Format "o") + "'"}
If ($Deadline -ne "NULL"){$Deadline = "'" + ($Deadline | Get-Date -Format "o") + "'"}
If ($InstallStartTime -ne "NULL"){$InstallStartTime = "'" + ($InstallStartTime | Get-Date -Format "o") + "'"}
If ($InstallFinishTime -ne "NULL"){$InstallFinishTime = "'" + ($InstallFinishTime | Get-Date -Format "o") + "'"}
If ($FinalizeStartTime -ne "NULL"){$FinalizeStartTime = "'" + ($FinalizeStartTime | Get-Date -Format "o") + "'"}
If ($FinalizeFinishTime -ne "NULL"){$FinalizeFinishTime = "'" + ($FinalizeFinishTime | Get-Date -Format "o") + "'"}

# SQL Query
$Query = "
UPDATE [dbo].[Upgrade1909] 
SET CurrentStatus = $CurrentStatus,
    DistributionPoint = $DistributionPoint,
    DistributionPointLatency = $DistributionPointLatency,
    ClientType = $ClientType,
    OSArchitecture = $OSArchitecture,
    OSVersion = $OSVersion,
    FreeDiskSpace = $FreeDiskSpace,
    Manufacturer = $Manufacturer,
    Model = $Model,
    ReadinessCheckResult = $ReadinessCheckResult,
    ReadinessCheckFailureDetail = $ReadinessCheckFailureDetail,
    ReadinessCheckTimestampUTC = $ReadinessCheckTimestampUTC,
    DownloadBandwidth = $DownloadBandwidth,
    CurrentConnectionType = $CurrentConnectionType,
    CorporateNetworkConnectivity = $CorporateNetworkConnectivity,
    OSName = $OSName,
    OSDescription = $OSDescription,
    OSProductKeyChannel = $OSProductKeyChannel,
    OSLanguageCode = $OSLanguageCode,
    OSLanguage = $OSLanguage,
    ESDFileName = $ESDFileName,
    ESDMD5Hash = $ESDMD5Hash,
    CurrentDownloadPercentComplete = $CurrentDownloadPercentComplete,
    CurrentDownloadStartTime = $CurrentDownloadStartTime,
    CurrentDownloadFinishTime = $CurrentDownloadFinishTime,
    WindowsUpdateBoxDownloadDuration = $WindowsUpdateBoxDownloadDuration,
    ESDDownloadDuration = $ESDDownloadDuration,
    PreDownloadStartTime = $PreDownloadStartTime,
    PreDownloadFinishTime = $PreDownloadFinishTime,
    PreDownloadDuration = $PreDownloadDuration,
    PreDownloadProcessExitCode = $PreDownloadProcessExitCode,
    FailureCount = $FailureCount,
    BoxResult = $BoxResult,
    SetUpDiagFailureDetails = $SetUpDiagFailureDetails,
    SetupDiagFailureData = $SetupDiagFailureData,
    SetupDiagProfileName = $SetupDiagProfileName,
    SetupDiagRemediation = $SetupDiagRemediation,
    SetupDiagDateTime = $SetupDiagDateTime,
    HardBlockFound = $HardBlockFound,
    HardBlockTitle = $HardBlockTitle,
    HardBlockMessage = $HardBlockMessage,
    Deadline = $Deadline,
    InstallStartTime = $InstallStartTime,
    InstallFinishTime = $InstallFinishTime,
    InstallDuration = $InstallDuration,
    InstallProcessExitCode = $InstallProcessExitCode,
    FinalizeStartTime = $FinalizeStartTime,
    FinalizeFinishTime = $FinalizeFinishTime,
    FinalizeDuration = $FinalizeDuration,
    FinalizeProcessExitCode = $FinalizeProcessExitCode,
    DownloadLocation = $DownloadLocation,
    AzureCDNLatency = $AzureCDNLatency,
    ESDEstimatedDownloadDuration = $ESDEstimatedDownloadDuration,
    DateUpdated = '$CurrentDate'
WHERE SerialNumber = $SerialNumber
"
# Run the query
Try
{
    $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    $connection.AccessToken = $accessToken
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = $Query
    $command.ExecuteReader()
    "Record successfully updated in database" | Write-Host
    $Result = "Record successfully updated in database"
}
Catch
{
    $Result = $_.Exception.Message
    Write-Error $Result
}
  
# Close the connection
$connection.Close()