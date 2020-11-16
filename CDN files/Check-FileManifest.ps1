#####################################
## WINDOWS UPGRADE 10 FILE UPDATER ##
#####################################

# Variables
$RootFolder = $env:ProgramData
$ParentFolderName = "IT"
$ChildFolderName = "1909_Upgrade"
$WorkingDirectory = "$RootFolder\$ParentFolderName\$ChildFolderName"
$CDNContainer = "https://myCDNendpoint.azureedge.net/w10-1909-upgrade"
$ProgressPreference = 'SilentlyContinue'

# Download Manifest
Invoke-WebRequest -Uri "$CDNContainer\FileManifest.xml" -OutFile $WorkingDirectory\FileManifest_new.xml -UseBasicParsing
[xml]$CurrentFileManifest = Get-Content -Path "$WorkingDirectory\FileManifest.xml"
[xml]$NewFileManifest = Get-Content -Path "$WorkingDirectory\FileManifest_new.xml"

# Check for any new files
$NewFiles = New-Object System.Collections.ArrayList
foreach ($File in $NewFileManifest.Upgrade.Files.File)
{
    $FileExists = $CurrentFileManifest.Upgrade.Files.File | Where {$_.Name -eq $File.Name}
    If (!($FileExists))
    {
        [void]$NewFiles.Add($File)
    }
}

# Check for any updated files
$UpdatedFiles = New-Object System.Collections.ArrayList
foreach ($File in $NewFileManifest.Upgrade.Files.File)
{
    $CurrentFile = $CurrentFileManifest.Upgrade.Files.File | Where {$_.Name -eq $File.Name}
    If ($CurrentFile)
    {
        If ([double]$File.Version -gt [double]$CurrentFile.Version)
        {
            [void]$UpdatedFiles.Add($File)
        }
    }
}

# Download any new files
If ($NewFiles)
{
    Foreach ($file in $NewFiles)
    {
        Switch ($File.Path)
        {
            "Root" {$FinalLocation = $WorkingDirectory; $CDNURL = $CDNContainer}
            "bin" {$FinalLocation = "$WorkingDirectory\bin"; $CDNURL = $CDNContainer + "/bin"}
            "Xaml" {$FinalLocation = "$WorkingDirectory\Xaml"; $CDNURL = $CDNContainer + "/xaml"}
        }
        Invoke-WebRequest -Uri "$CDNURL/$($File.Name)" -OutFile "$FinalLocation\$($File.Name)" -UseBasicParsing
    }
}

# Download any updated files
If ($UpdatedFiles)
{
    Foreach ($file in $UpdatedFiles)
    {
        Switch ($File.Path)
        {
            "Root" {$FinalLocation = $WorkingDirectory; $CDNURL = $CDNContainer}
            "bin" {$FinalLocation = "$WorkingDirectory\bin"; $CDNURL = $CDNContainer + "/bin"}
            "Xaml" {$FinalLocation = "$WorkingDirectory\Xaml"; $CDNURL = $CDNContainer + "/xaml"}
        }
        Invoke-WebRequest -Uri "$CDNURL\$($File.Name)" -OutFile "$FinalLocation\$($File.Name)" -UseBasicParsing
    }
}

# Overwrite FileManifest with new version
Move-Item "$WorkingDirectory\FileManifest_new.xml" "$WorkingDirectory\FileManifest.xml" -Force

# Check if deadline is passed and change the schedule for the toast notification
$FullRegPath = "HKLM:\SOFTWARE\IT\1909Upgrade"
$Deadline = Get-ItemProperty -Path $FullRegPath -Name Deadline -ErrorAction SilentlyContinue | Select -ExpandProperty Deadline -ErrorAction SilentlyContinue
If ($Deadline)
{
    If (((Get-Date) - (Get-Date $Deadline)).TotalDays -gt 0 -and $ExcludedDevice -ne $true)
    {
        $NotificationTask = Get-ScheduledTask -TaskName "Windows 10 Upgrade Notification" -ErrorAction SilentlyContinue
        If ($NotificationTask)
        {
            If ($NotificationTask.State -ne "Disabled" -and $NotificationTask.Triggers[1].Enabled -eq $True)
            {
                $NotificationTask.Triggers[0].Repetition.Interval = "PT30M"
                $NotificationTask.Triggers[0].Repetition.Duration = "P1D"
                $NotificationTask.Triggers[1].Enabled = $false
                $NotificationTask | Set-ScheduledTask            
            }
        }
    }
}
