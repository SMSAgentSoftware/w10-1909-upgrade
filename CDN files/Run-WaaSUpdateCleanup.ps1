#######################################
## WINDOWS 10 UPGRADE CLEANUP SCRIPT ##
#######################################

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

# If on 1909, cleanup files and scheduled tasks
$Version = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ReleaseID -ErrorAction Stop).ReleaseID
If ($Version -eq "1909")
{
    Set-ItemProperty -Path $FullRegPath -Name OSVersion -Value $Version -Force
    Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Upgraded" -Force
    Write-UpgradeLog -Message "OS version is now $Version. Nothing more for us to do. Let's cleanup the upgrade directory and the scheduled tasks."
    $UpgradeFiles = Get-ChildItem $WorkingDirectory
    Foreach ($Item in $UpgradeFiles)
    {
        If ($Item.Name -ne "1909_Upgrade.log")
        {  
            If ($Item.Attributes -match "Directory")
            {
                try 
                {
                    Remove-Item -Path $Item.FullName -Recurse -Force -ErrorAction Stop
                    Write-UpgradeLog -Message "Deleted directory '$($Item.Name)' and its contents"
                }
                catch 
                {
                    Write-UpgradeLog -Message "Failed to delete directory '$($Item.Name)': $_" -LogLevel 2
                }  
            }  
            else 
            {
                try 
                {
                    Remove-Item -Path $Item.FullName -Force -ErrorAction Stop
                    Write-UpgradeLog -Message "Deleted file '$($Item.Name)'"
                }
                catch 
                {
                    Write-UpgradeLog -Message "Failed to delete file '$($Item.Name)': $_" -LogLevel 2
                }  
            }       
        }
    }
    $ScheduledTasks = @(
        'Windows 10 Upgrade Notification'
        'Windows 10 Upgrade PreDownload'
        'Windows 10 Upgrade Preparer'
        'Windows 10 Upgrade Cleanup'
        'Windows 10 Upgrade File Updater'
        'Windows 10 Upgrade'
        'Windows 10 Upgrade Rollback Notification'
        'Windows 10 Upgrade Rollback Checker'
    )
    Foreach ($ScheduledTask in $ScheduledTasks)
    { 
        try 
        {
            Unregister-ScheduledTask -TaskName $ScheduledTask -Confirm:$false -ErrorAction Stop
            Write-UpgradeLog -Message "Unregistered scheduled task '$ScheduledTask'"
        }
        catch 
        {
            Write-UpgradeLog -Message "Failed to unregister scheduled task '$ScheduledTask': $_" -LogLevel 2
        }
    }

    try 
    {
        Remove-Item -Path "$env:Public\Desktop\Windows 10 Update.lnk" -Force -ErrorAction Stop
        Write-UpgradeLog -Message "Removed Windows 10 Update desktop shortcut"
    }
    catch 
    {
        Write-UpgradeLog -Message "Failed to remove desktop shortcut '$env:Public\Desktop\Windows 10 Update.lnk'" -LogLevel 2
    }

    try 
    {
        $HKU = Get-PSDrive -Name HKU -ErrorAction SilentlyContinue
        If (!($HKU))
        {
            New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -Scope Script -ErrorAction Stop
        }
        Remove-Item -Path HKU:\S-1-5-18\Software\IT -Recurse -Force -ErrorAction Stop
        Write-UpgradeLog -Message "Removed credentials registry keys from SYSTEM user hive"
    }
    catch 
    {
        Write-UpgradeLog -Message "Failed to remove credentials registry keys from SYSTEM user hive" -LogLevel 2
    }

}
