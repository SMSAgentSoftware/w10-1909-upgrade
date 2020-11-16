sing namespace System.Net
using namespace System.Data
using namespace System.Data.SqlClient

param($eventGridEvent, $TriggerMetadata)

# Output basic info about this execution
Write-Host "Receiving new entry for $($eventGridEvent.data.ComputerName) (Serial Number: $($eventGridEvent.data.SerialNumber))"

# Retrieve some variables
$MSI_ENDPOINT = [System.Environment]::GetEnvironmentVariable("MSI_ENDPOINT")
$MSI_SECRET = [System.Environment]::GetEnvironmentVariable("MSI_SECRET")
$ConnectionString = [System.Environment]::GetEnvironmentVariable("sqldb_Connection")

# Obtain access token for function app managed identity for database audience
$tokenAuthURI = "$MSI_ENDPOINT`?resource=https://database.windows.net/&api-version=2017-09-01"
$tokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret"="$MSI_SECRET"} -Uri $tokenAuthURI
$accessToken = $tokenResponse.access_token

$CurrentDate = [datetime]::Now

# SQL Query
$Query = "
INSERT INTO [dbo].[Upgrade1909] (
	ComputerName,
    SerialNumber,
    CurrentStatus,
    DateUpdated
)
VALUES (
	'$($eventGridEvent.data.ComputerName)',
    '$($eventGridEvent.data.SerialNumber)',
    '$($eventGridEvent.data.CurrentStatus)',
    '$CurrentDate'
)
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
    "Record successfully added to database" | Write-Host
    $Result = "Record successfully added to database"
}
Catch
{
    $Result = $_.Exception.Message
    Write-Error $Result
}
   
# Close the connection
$connection.Close()