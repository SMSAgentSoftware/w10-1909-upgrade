####################################
##                                ##
## Contains PowerShell functions  ##
##                                ##
####################################

# Function to write to the upgrade log
Function script:Write-UpgradeLog {

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

Function Invoke-Update {
    Param()

    ########################################################
    ## Blank out some registry keys set by a previous run ##
    ########################################################
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
    Write-UpgradeLog -Message "Running PreDownload before upgrade"
    Write-UpgradeLog -Message "Cmd line: $WorkingDirectory\WindowsUpdateBox.exe /Update /PreDownload /quiet /noreboot"
    Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Running PreDownload before upgrade" -Force
    $Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
    Set-ItemProperty -Path $FullRegPath -Name PreDownloadStartTime -Value $Timestamp -Force
    Send-StatusUpdate
    try 
    {
        $Process = Start-Process -FilePath "$WorkingDirectory\WindowsUpdateBox.exe" -ArgumentList "/Update /PreDownload /quiet /noreboot" -Wait -NoNewWindow -Passthru -ErrorAction Stop
    }
    catch 
    {
        Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Failed to run PreDownload before upgrade" -Force
        Write-UpgradeLog -Message "Failed to run the PreDownload before upgrade. The error message was: $_" -LogLevel 3
        Send-StatusUpdate
        $UI.DataSource[14] = "FrownRegular"
        $UI.DataSource[15] = "#CF6679"
        $UI.DataSource[16] = "An error occured during the prepare phase. The update was not applied. Please contact IT support for assistance."
        $UI.DataSource[18] = "Collapsed" # [18] SetupPhase & SetupSubPhase visibility
        $UI.DataSource[19] = "Close" # [19] Button1 text
        $UI.DataSource[21] = "Visible" # [21] Button1 visibility
        $UI.DataSource[22] = "Collapsed" # [22] Button2 visibility
        $UI.DataSource[25] = "Collapsed" # [25] Button3 visibility
        $UI.DataSource[12] = "Collapsed" # [12] Page 2 visibility
        $UI.DataSource[13] = "Visible" # [13] Page 3 visibility
    
        $SoundFile = "$env:SystemDrive\Windows\Media\Windows Foreground.wav"
        $SoundPlayer = New-Object System.Media.SoundPlayer -ArgumentList $SoundFile
        $SoundPlayer.Add_LoadCompleted({
            $This.Play()
            $This.Dispose()
        })
        $SoundPlayer.LoadAsync()
    
        $UI.DataSource[26] = "ShowMe!"
        Return
    }
    $ConvertedExitCode = "0x" + "$('{0:X4}' -f $Process.ExitCode)"
    $Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
    Set-ItemProperty -Path $FullRegPath -Name PreDownloadFinishTime -Value $Timestamp -Force
    $StartTime = Get-Date (Get-ItemProperty -Path $FullRegPath -Name PreDownloadStartTime | Select -ExpandProperty PreDownloadStartTime)
    $FinishTime = Get-Date (Get-ItemProperty -Path $FullRegPath -Name PreDownloadFinishTime | Select -ExpandProperty PreDownloadFinishTime)
    $Duration = ($FinishTime - $StartTime)
    Set-ItemProperty -Path  $FullRegPath -Name PreDownloadDuration -Value "$($Duration.Minutes) minutes $($Duration.Seconds) seconds" -Force
    Write-UpgradeLog -Message "Completed PreDownload before upgrade in $($Duration.Minutes) minutes $($Duration.Seconds) seconds"
    If ($Process.ExitCode -ne 0)
    {
        Write-UpgradeLog -Message "PreDownload process completed with exit code $ConvertedExitCode" -LogLevel 2
    }
    else 
    {
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
        Write-UpgradeLog -Message "This PC did not pass the compatibility assessment or failed to run the PreDownload phase." -LogLevel 2
        Write-UpgradeLog -Message "Notifying the user to seek assistance from IT." -LogLevel 2
        Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Failed PreDownload before upgrade" -Force
        Send-StatusUpdate

        $UI.DataSource[14] = "FrownRegular"
        $UI.DataSource[15] = "#CF6679"
        $UI.DataSource[16] = "An error occured during the prepare phase. The update was not applied. Please contact IT support for assistance."
        $UI.DataSource[18] = "Collapsed" # [18] SetupPhase & SetupSubPhase visibility
        $UI.DataSource[19] = "Close" # [19] Button1 text
        $UI.DataSource[21] = "Visible" # [21] Button1 visibility
        $UI.DataSource[22] = "Collapsed" # [22] Button2 visibility
        $UI.DataSource[25] = "Collapsed" # [25] Button3 visibility
        $UI.DataSource[12] = "Collapsed" # [12] Page 2 visibility
        $UI.DataSource[13] = "Visible" # [13] Page 3 visibility
    
        $SoundFile = "$env:SystemDrive\Windows\Media\Windows Foreground.wav"
        $SoundPlayer = New-Object System.Media.SoundPlayer -ArgumentList $SoundFile
        $SoundPlayer.Add_LoadCompleted({
            $This.Play()
            $This.Dispose()
        })
        $SoundPlayer.LoadAsync()
    
        $UI.DataSource[26] = "ShowMe!"
        Return
    }
    else 
    {
        Write-UpgradeLog -Message "The PreDownload before upgrade phase passed successfully"
        Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Ready for install" -Force
        $UI.InstallPhase = "Install"
        $UI.DataSource[10] = "#03DAC5"
        $UI.DataSource[1] = "100%" # Progress bar
        $UI.DataSource[4] = "100" # Progress value
    }

    #################
    ## Run Install ##
    #################
    Write-UpgradeLog -Message "Running Install"
    Write-UpgradeLog -Message "Cmd line: $WorkingDirectory\WindowsUpdateBox.exe /Update /Install /quiet /noreboot"
    Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Running Install" -Force
    $Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
    Set-ItemProperty -Path $FullRegPath -Name InstallStartTime -Value $Timestamp -Force
    Send-StatusUpdate
    try 
    {
        $Process = Start-Process -FilePath "$WorkingDirectory\WindowsUpdateBox.exe" -ArgumentList "/Update /Install /quiet /noreboot" -Wait -NoNewWindow -Passthru -ErrorAction Stop
    }
    catch 
    {
        Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Failed to run Install" -Force
        Write-UpgradeLog -Message "Failed to run the Install. The error message was: $_" -LogLevel 3
        Send-StatusUpdate
        $UI.DataSource[14] = "FrownRegular"
        $UI.DataSource[15] = "#CF6679"
        $UI.DataSource[16] = "An error occured during the install phase. The update was not applied. Please contact IT support for assistance."
        $UI.DataSource[18] = "Collapsed" # [18] SetupPhase & SetupSubPhase visibility
        $UI.DataSource[19] = "Close" # [19] Button1 text
        $UI.DataSource[21] = "Visible" # [21] Button1 visibility
        $UI.DataSource[22] = "Collapsed" # [22] Button2 visibility
        $UI.DataSource[25] = "Collapsed" # [25] Button3 visibility
        $UI.DataSource[12] = "Collapsed" # [12] Page 2 visibility
        $UI.DataSource[13] = "Visible" # [13] Page 3 visibility
    
        $SoundFile = "$env:SystemDrive\Windows\Media\Windows Foreground.wav"
        $SoundPlayer = New-Object System.Media.SoundPlayer -ArgumentList $SoundFile
        $SoundPlayer.Add_LoadCompleted({
            $This.Play()
            $This.Dispose()
        })
        $SoundPlayer.LoadAsync()
    
        $UI.DataSource[26] = "ShowMe!"
        Return
    }
    $ConvertedExitCode = "0x" + "$('{0:X4}' -f $Process.ExitCode)"
    $Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
    Set-ItemProperty -Path $FullRegPath -Name InstallFinishTime -Value $Timestamp -Force
    $StartTime = Get-Date (Get-ItemProperty -Path $FullRegPath -Name InstallStartTime | Select -ExpandProperty InstallStartTime)
    $FinishTime = Get-Date (Get-ItemProperty -Path $FullRegPath -Name InstallFinishTime | Select -ExpandProperty InstallFinishTime)
    $Duration = ($FinishTime - $StartTime)
    Set-ItemProperty -Path  $FullRegPath -Name InstallDuration -Value "$($Duration.Minutes) minutes $($Duration.Seconds) seconds" -Force
    Write-UpgradeLog -Message "Completed Install in $($Duration.Minutes) minutes $($Duration.Seconds) seconds"
    If ($Process.ExitCode -ne 0)
    {
        Write-UpgradeLog -Message "Install process completed with exit code $ConvertedExitCode" -LogLevel 2
    }
    else 
    {
        Write-UpgradeLog -Message "Install process completed with exit code $ConvertedExitCode"
    }
    Set-ItemProperty -Path $FullRegPath -Name InstallProcessExitCode -Value $ConvertedExitCode -Force
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
        Write-UpgradeLog -Message "This PC failed to complete the Install phase." -LogLevel 2
        Write-UpgradeLog -Message "Notifying the user to seek assistance from IT." -LogLevel 2
        Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Failed Install" -Force
        Send-StatusUpdate

        $UI.DataSource[14] = "FrownRegular"
        $UI.DataSource[15] = "#CF6679"
        $UI.DataSource[16] = "An error occured during the install phase. The update was not applied. Please contact IT support for assistance."
        $UI.DataSource[18] = "Collapsed" # [18] SetupPhase & SetupSubPhase visibility
        $UI.DataSource[19] = "Close" # [19] Button1 text
        $UI.DataSource[21] = "Visible" # [21] Button1 visibility
        $UI.DataSource[22] = "Collapsed" # [22] Button2 visibility
        $UI.DataSource[25] = "Collapsed" # [25] Button3 visibility
        $UI.DataSource[12] = "Collapsed" # [12] Page 2 visibility
        $UI.DataSource[13] = "Visible" # [13] Page 3 visibility
    
        $SoundFile = "$env:SystemDrive\Windows\Media\Windows Foreground.wav"
        $SoundPlayer = New-Object System.Media.SoundPlayer -ArgumentList $SoundFile
        $SoundPlayer.Add_LoadCompleted({
            $This.Play()
            $This.Dispose()
        })
        $SoundPlayer.LoadAsync()
    
        $UI.DataSource[26] = "ShowMe!"
        Return
    }
    else 
    {
        Write-UpgradeLog -Message "The Install phase passed successfully"
        Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Ready for finalize" -Force
        $UI.InstallPhase = "Finalize"
        $UI.DataSource[11] = "#03DAC5"
        $UI.DataSource[2] = "100%" # Progress bar
        $UI.DataSource[5] = "100" # Progress value
    }

    ##################
    ## Run Finalize ##
    ##################
    Write-UpgradeLog -Message "Running Finalize"
    Write-UpgradeLog -Message "Cmd line: $WorkingDirectory\WindowsUpdateBox.exe /Update /Finalize /quiet /noreboot"
    Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Running Finalize" -Force
    $Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
    Set-ItemProperty -Path $FullRegPath -Name FinalizeStartTime -Value $Timestamp -Force
    Send-StatusUpdate
    try 
    {
        $Process = Start-Process -FilePath "$WorkingDirectory\WindowsUpdateBox.exe" -ArgumentList "/Update /Finalize /quiet /noreboot" -Wait -NoNewWindow -Passthru -ErrorAction Stop
    }
    catch 
    {
        Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Failed to run Finalize" -Force
        Write-UpgradeLog -Message "Failed to run Finalize. The error message was: $_" -LogLevel 3
        Send-StatusUpdate
        $UI.DataSource[14] = "FrownRegular"
        $UI.DataSource[15] = "#CF6679"
        $UI.DataSource[16] = "An error occured during the finalize phase. The update was not fully applied. Please contact IT support for assistance."
        $UI.DataSource[18] = "Collapsed" # [18] SetupPhase & SetupSubPhase visibility
        $UI.DataSource[19] = "Close" # [19] Button1 text
        $UI.DataSource[21] = "Visible" # [21] Button1 visibility
        $UI.DataSource[22] = "Collapsed" # [22] Button2 visibility
        $UI.DataSource[25] = "Collapsed" # [25] Button3 visibility
        $UI.DataSource[12] = "Collapsed" # [12] Page 2 visibility
        $UI.DataSource[13] = "Visible" # [13] Page 3 visibility
    
        $SoundFile = "$env:SystemDrive\Windows\Media\Windows Foreground.wav"
        $SoundPlayer = New-Object System.Media.SoundPlayer -ArgumentList $SoundFile
        $SoundPlayer.Add_LoadCompleted({
            $This.Play()
            $This.Dispose()
        })
        $SoundPlayer.LoadAsync()
    
        $UI.DataSource[26] = "ShowMe!"
        Return
    }
    $ConvertedExitCode = "0x" + "$('{0:X4}' -f $Process.ExitCode)"
    $Timestamp = [Datetime]::UtcNow | Get-Date -Format "yyyy-MMM-dd HH:mm:ss"
    Set-ItemProperty -Path $FullRegPath -Name FinalizeFinishTime -Value $Timestamp -Force
    $StartTime = Get-Date (Get-ItemProperty -Path $FullRegPath -Name FinalizeStartTime | Select -ExpandProperty FinalizeStartTime)
    $FinishTime = Get-Date (Get-ItemProperty -Path $FullRegPath -Name FinalizeFinishTime | Select -ExpandProperty FinalizeFinishTime)
    $Duration = ($FinishTime - $StartTime)
    Set-ItemProperty -Path  $FullRegPath -Name FinalizeDuration -Value "$($Duration.Minutes) minutes $($Duration.Seconds) seconds" -Force
    Write-UpgradeLog -Message "Completed Finalize in $($Duration.Minutes) minutes $($Duration.Seconds) seconds"
    If ($Process.ExitCode -ne 0)
    {
        Write-UpgradeLog -Message "Finalize process completed with exit code $ConvertedExitCode" -LogLevel 2
    }
    else 
    {
        Write-UpgradeLog -Message "Finalize process completed with exit code $ConvertedExitCode"
    }
    Set-ItemProperty -Path $FullRegPath -Name FinalizeProcessExitCode -Value $ConvertedExitCode -Force
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
        Write-UpgradeLog -Message "This PC failed to complete the Finalize phase." -LogLevel 2
        Write-UpgradeLog -Message "Notifying the user to seek assistance from IT." -LogLevel 2
        Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Failed Finalize" -Force
        Send-StatusUpdate

        $UI.DataSource[14] = "FrownRegular"
        $UI.DataSource[15] = "#CF6679"
        $UI.DataSource[16] = "An error occured during the finalize phase. The update was not fully applied. Please contact IT support for assistance."
        $UI.DataSource[18] = "Collapsed" # [18] SetupPhase & SetupSubPhase visibility
        $UI.DataSource[19] = "Close" # [19] Button1 text
        $UI.DataSource[21] = "Visible" # [21] Button1 visibility
        $UI.DataSource[22] = "Collapsed" # [22] Button2 visibility
        $UI.DataSource[25] = "Collapsed" # [25] Button3 visibility
        $UI.DataSource[12] = "Collapsed" # [12] Page 2 visibility
        $UI.DataSource[13] = "Visible" # [13] Page 3 visibility
    
        $SoundFile = "$env:SystemDrive\Windows\Media\Windows Foreground.wav"
        $SoundPlayer = New-Object System.Media.SoundPlayer -ArgumentList $SoundFile
        $SoundPlayer.Add_LoadCompleted({
            $This.Play()
            $This.Dispose()
        })
        $SoundPlayer.LoadAsync()
    
        $UI.DataSource[26] = "ShowMe!"
        Return
    }
    else 
    {
        Write-UpgradeLog -Message "The Finalize phase passed successfully"
        Set-ItemProperty -Path  $FullRegPath -Name CurrentStatus -Value "Installed pending reboot" -Force
        Send-StatusUpdate

        # Regoster rollback scheduled tasks in case they are needed
        try {
            Register-ScheduledTask -Xml (Get-Content "$WorkingDirectory\Windows 10 Upgrade Rollback Notification.xml" | out-string) -TaskName "Windows 10 Upgrade Rollback Notification" -Force -ErrorAction Stop
            Write-UpgradeLog -Message "Registered scheduled task 'Windows 10 Upgrade Rollback Notification'"
        }
        catch {
            Write-UpgradeLog -Message "Failed to registered scheduled task 'Windows 10 Upgrade Rollback Notification': $_" -LogLevel 2
        }
        try {
            Register-ScheduledTask -Xml (Get-Content "$WorkingDirectory\Windows 10 Upgrade Rollback Checker.xml" | out-string) -TaskName "Windows 10 Upgrade Rollback Checker" -Force -ErrorAction Stop
            Write-UpgradeLog -Message "Registered scheduled task 'Windows 10 Upgrade Rollback Checker'"
        }
        catch {
            Write-UpgradeLog -Message "Failed to registered scheduled task 'Windows 10 Upgrade Rollback Checker': $_" -LogLevel 2
        }
        #$UI.InstallPhase = "Finalize"
        #$UI.DataSource[11] = "#03DAC5"
        $UI.DataSource[3] = "100%" # Progress bar
        $UI.DataSource[6] = "100" # Progress value

        $UI.DataSource[14] = "SmileRegular"
        $UI.DataSource[15] = "#03DAC5"
        $UI.DataSource[16] = "The update has finished installing. Please restart your computer as soon as possible to complete the process."
        $UI.DataSource[18] = "Collapsed" # [18] SetupPhase & SetupSubPhase visibility
        $UI.DataSource[19] = "Close" # [19] Button1 text
        $UI.DataSource[20] = "Restart" #[20] Button 2 text
        $UI.DataSource[21] = "Visible" # [21] Button1 visibility
        $UI.DataSource[22] = "Visible" # [22] Button2 visibility
        $UI.DataSource[25] = "Collapsed" # [25] Button3 visibility
        $UI.DataSource[12] = "Collapsed" # [12] Page 2 visibility
        $UI.DataSource[13] = "Visible" # [13] Page 3 visibility
    }

}

# Function to create a update record for this device in the Azure SQL database
Function script:Send-StatusUpdate {
    $ComputerName = $env:COMPUTERNAME
    $SerialNumber = Get-CimInstance win32_BIOS | Select -ExpandProperty SerialNumber
    $eventgridtopicendpoint = "https://myEventGridEndpoint.eventgrid.azure.net/api/events"
    $eventgridtopickey = "MyEventGridTopicKey"

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

