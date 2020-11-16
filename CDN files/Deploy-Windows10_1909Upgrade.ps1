########################
## WINDOWS 10 UPGRADE ##
########################

# This script creates the working directory, downloads the initial scripts needed and creates the scheduled tasks that drive the updgrade process

################################
## Create Directory Structure ##
################################
$RootFolder = $env:ProgramData
$ParentFolderName = "IT"
$ChildFolderName = "1909_Upgrade"
$WorkingDirectory = "$RootFolder\$ParentFolderName\$ChildFolderName"
If (!(Test-path $RootFolder\$ParentFolderName))
{
    $null = New-Item -Path $RootFolder -Name $ParentFolderName -ItemType Directory -Force
}
If (!(Test-path $RootFolder\$ParentFolderName\$ChildFolderName))
{
    $null = New-Item -Path $RootFolder\$ParentFolderName -Name $ChildFolderName -ItemType Directory -Force
}
If (!(Test-path $RootFolder\$ParentFolderName\$ChildFolderName\bin))
{
    $null = New-Item -Path $RootFolder\$ParentFolderName\$ChildFolderName -Name "bin" -ItemType Directory -Force
}
If (!(Test-path $RootFolder\$ParentFolderName\$ChildFolderName\Xaml))
{
    $null = New-Item -Path $RootFolder\$ParentFolderName\$ChildFolderName -Name "Xaml" -ItemType Directory -Force
}

##################################################################
## Check that the script isn't running again or doesn't need to ##
##################################################################
$FilesExist = Test-Path "$WorkingDirectory\Run-WaaSUpdatePreparation.ps1"
$OSVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ReleaseID -ErrorAction Stop).ReleaseID
If ($FilesExist -or $OSVersion -ge "1909")
{
    Exit 0
}

#################################
## Disable IE First Run Wizard ##
#################################
# This prevents an error running Invoke-WebRequest when IE has not yet been run
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft" -Name "Internet Explorer" -Force
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer" -Name "Main" -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\Main" -Name "DisableFirstRunCustomize" -PropertyType DWORD -Value 1 -Force

#############################################################################
## Store some network access credentials to the registry as secure strings ##
#############################################################################
# COMPANYNET\HTS001MEMCMSQLREAD
$RootRegBase = "HKCU:\Software"
$RootRegBranchName = "HTS"
$FullRegPath = "$RootRegBase\$RootRegBranchName"
If (!(Test-Path $FullRegPath))
{
    $null = New-Item -Path $RootRegBase -Name $RootRegBranchName 
}
$String1 = "base64domain\username"
$String2 = "base64password"
$ConvertedString1 = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($String1))
$ConvertedString2 = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($String2))
$SS1 = $ConvertedString1 | ConvertTo-SecureString -AsPlainText -Force
$SS2 = $ConvertedString2 | ConvertTo-SecureString -AsPlainText -Force
Set-ItemProperty -Path $FullRegPath -Name String1 -Value ($SS1 | ConvertFrom-SecureString) -Force
Set-ItemProperty -Path $FullRegPath -Name String2 -Value ($SS2 | ConvertFrom-SecureString) -Force

#############################
## Download Required Files ##
#############################
$CDNContainer = "https://myCDNendpoint/w10-1909-upgrade"
$ProgressPreference = 'SilentlyContinue'

# Download Manifest
try 
{
    Invoke-WebRequest -Uri "$CDNContainer\FileManifest.xml" -OutFile $WorkingDirectory\FileManifest.xml -UseBasicParsing -ErrorAction Stop
}
catch 
{
    Exit 1
}

# Download each file in the manifest to the appropriate location
try
{
    [xml]$FileManifest = Get-Content -Path "$WorkingDirectory\FileManifest.xml" -ErrorAction Stop
    $RootFiles = $FileManifest.Upgrade.Files.File | Where {$_.Path -eq "Root"}
    $binFiles = $FileManifest.Upgrade.Files.File | Where {$_.Path -eq "bin"}
    $XamlFiles = $FileManifest.Upgrade.Files.File | Where {$_.Path -eq "Xaml"}
    foreach ($FileName in $RootFiles.Name)
    {
        Invoke-WebRequest -Uri "$CDNContainer\$FileName" -OutFile $WorkingDirectory\$FileName -UseBasicParsing -ErrorAction Stop
    }
    foreach ($FileName in $binFiles.Name)
    {
        Invoke-WebRequest -Uri "$CDNContainer\bin\$FileName" -OutFile $WorkingDirectory\bin\$FileName -UseBasicParsing -ErrorAction Stop
    }
    foreach ($FileName in $XamlFiles.Name)
    {
        Invoke-WebRequest -Uri "$CDNContainer\Xaml\$FileName" -OutFile $WorkingDirectory\Xaml\$FileName -UseBasicParsing -ErrorAction Stop
    }
}
Catch
{
    Exit 1
}

################################
## Create the Scheduled Tasks ##
################################
try 
{
    Register-ScheduledTask -Xml (Get-Content "$WorkingDirectory\Windows 10 Upgrade Preparer.xml" -ErrorAction Stop | out-string) -TaskName "Windows 10 Upgrade Preparer" -Force -ErrorAction Stop
    Register-ScheduledTask -Xml (Get-Content "$WorkingDirectory\Windows 10 Upgrade Cleanup.xml" -ErrorAction Stop | out-string) -TaskName "Windows 10 Upgrade Cleanup" -Force -ErrorAction Stop
    Register-ScheduledTask -Xml (Get-Content "$WorkingDirectory\Windows 10 Upgrade File Updater.xml" -ErrorAction Stop | out-string) -TaskName "Windows 10 Upgrade File Updater" -Force -ErrorAction Stop
}
catch 
{
    Exit 1
}

###############################################
## Create a New Record in Azure SQL Database ##
###############################################
Function Add-NewSQLRecord {
    $ComputerName = $env:COMPUTERNAME
    $SerialNumber = Get-CimInstance win32_BIOS | Select -ExpandProperty SerialNumber
    $eventgridtopicendpoint = "https://myeventgridendpoint.eventgrid.azure.net/api/events"
    $eventgridtopickey = "myeventgridtopickey"

    # Prepare hash table for the event body
    $eventID = Get-Random 99999      
    $eventDate = Get-Date -Format s # Date format should be SortableDateTimePattern (ISO 8601)
    $htbody = @{
        id= $eventID
        eventType="recordInserted"
        subject="Upgrade 1909 New Record"
        eventTime= $eventDate   
        data= @{
            ComputerName = "$ComputerName"
            SerialNumber = "$SerialNumber"
            CurrentStatus = "Ready for prep"
        }
        dataVersion="1.0"
    }

    # Send the request
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

Add-NewSQLRecord