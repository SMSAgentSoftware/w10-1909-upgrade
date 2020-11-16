#############################
##                         ##
## Defines event handlers  ##
##                         ##
#############################

# Bring the main window to the front once loaded
$UI.Window.Add_Loaded({
    #$This.Activate()
    $UI.EaseIn.Begin($UI.Window)
    try 
    {
        Disable-ScheduledTask -TaskName "Windows 10 Upgrade Notification" -ErrorAction Stop
        Write-UpgradeLog -Message "Scheduled task 'Windows 10 Upgrade Notification' was disabled"
    }
    catch 
    {
        Write-UpgradeLog -Message "Failed to disable scheduled task 'Windows 10 Upgrade Notification'" -LogLevel 2
    }
})

$UI.Window.Add_MouseLeftButtonDown({ 
    $UI.Window.DragMove()
})

$UI.Button3.Add_MouseEnter({
    $This.Foreground="#03DAC5"
})

$UI.Button3.Add_MouseLeave({
    $This.Foreground="#BB86FC"
})

$UI.Button3.Add_PreviewMouseLeftButtonUp({
    
    [XML]$Xaml = [System.IO.File]::ReadAllLines("$Source\Xaml\SmallWindow.xaml") 
    $UI.SmallWindow = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml))
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | 
        ForEach-Object -Process {
            $UI.$($_.Name) = $UI.SmallWindow.FindName($_.Name)
        }
    $UI.SmallWindowText.Add_MouseEnter({
        $This.Foreground="#03DAC5"
    })
    $UI.SmallWindowText.Add_MouseLeave({
        $This.Foreground="#BB86FC"
    })

    $UI.SmallWindowText.Add_PreviewMouseLeftButtonUp({
        $UI.SmallWindow.Close()
        $UI.Window.ShowDialog()
    })

    $UI.SmallWindow.Add_MouseLeftButtonDown({ 
        $This.DragMove()
    })

    $UI.Window.Hide()
    $UI.SmallWindow.ShowDialog()
    
})

$UI.Button1.Add_MouseEnter({
    $This.Foreground="#03DAC5"
})

$UI.Button1.Add_MouseLeave({
    $This.Foreground="#BB86FC"
})

$UI.Button1.Add_PreviewMouseLeftButtonUp({
    $UI.Window.Close()
    If ($This.Text -eq "Cancel")
    {
        Write-UpgradeLog -Message "User cancelled update" -LogLevel 2
        Try
        {
            Enable-ScheduledTask -TaskName "Windows 10 Upgrade Notification" -ErrorAction Stop
            Write-UpgradeLog -Message "Scheduled task 'Windows 10 Upgrade Notification' was re-enabled"
        }
        Catch
        {
            Write-UpgradeLog -Message "Failed to reenable scheduled task 'Windows 10 Upgrade Notification'" -LogLevel 2
        }
    }
    If ($UI.DispatcherTimer)
    {
        $UI.DispatcherTimer.Stop()
    }
    If ($UI.Stopwatch)
    {
        $UI.Stopwatch.Stop()
    }
    
    #$UI.Stopwatch.Stop()
    #$UI.DispatcherTimer.Dispose()
})

$UI.Button2.Add_MouseEnter({
    $This.Foreground="#03DAC5"
})

$UI.Button2.Add_MouseLeave({
    $This.Foreground="#BB86FC"
})

$UI.Button2.Add_PreviewMouseLeftButtonUp({

    If ($This.text -eq "Begin")
    {
        # USB Device check
        [array]$USBDisks = Get-CimInstance -Query  "Select Name from Win32_USBDevice WHERE (Description='Disk drive' OR Description='DisplayLink USB Device') AND Name != 'Generic STORAGE DEVICE USB Device'" | Select -ExpandProperty name 
        $PowerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus
        If ($USBDisks.Count -ge 1)
        {
            $Text = "Please disconnect the following USB devices before continuing:" + [System.Environment]::NewLine
            foreach ($USBDisk in $USBDisks)
            {
                $Text = $Text + [System.Environment]::NewLine + "‣ $USBDisk"
            }
            Write-UpgradeLog -Message "$Text" -LogLevel 2
            $UI.ChildText1.Text = $Text
            $UI.DataSource[23] = "UsbBrands"
            $UI.Notifier.IsOpen = "True"
        }
        # Power adapter check
        ElseIf ($PowerStatus -ne "Online")
        {
            $Text = "You are running on battery - please connect your power adapter before continuing."
            Write-UpgradeLog -Message "$Text" -LogLevel 2
            $UI.ChildText1.Text = $Text
            $UI.DataSource[23] = "PlugSolid"
            $UI.Notifier.IsOpen = "True"
        }
        else 
        {
            #$This.Visibility = "Collapsed"
            $UI.Page1.Visibility="Collapsed"
            $UI.DataSource[12] = "Visible"
            $UI.DataSource[18] = "Visible"
            #$UI.SetupPhase.Visibility="Visible"
            #$UI.SetupSubPhase.Visibility="Visible"
            $UI.DataSource[21] = "Collapsed"
            $UI.DataSource[22] = "Hidden"
            $UI.DataSource[25] = "Visible"

            Write-UpgradeLog -Message "Update installation started"
            Write-UpgradeLog -Message "Current phase: Prepare"
            Set-ItemProperty -Path $FullRegPath -Name CurrentStatus -Value "Preparing update" -Force
            $UI.Stopwatch = New-Object System.Diagnostics.Stopwatch
            $UI.Stopwatch.Start()
            $TimerCode = {
                $ProgressValue = Get-ItemProperty -Path HKLM:\SYSTEM\Setup\MoSetup\Volatile -Name SetupProgress -ErrorAction SilentlyContinue | Select -ExpandProperty SetupProgress -ErrorAction SilentlyContinue
                $SetupPhase = Get-ItemProperty -Path HKLM:\SYSTEM\Setup\MoSetup\Volatile -Name SetupPhase -ErrorAction SilentlyContinue | Select -ExpandProperty SetupPhase -ErrorAction SilentlyContinue
                $SetupSubPhase = Get-ItemProperty -Path HKLM:\SYSTEM\Setup\MoSetup\Volatile -Name SetupSubPhase -ErrorAction SilentlyContinue | Select -ExpandProperty SetupSubPhase -ErrorAction SilentlyContinue
                $UI.DataSource[0] = "$($UI.Stopwatch.Elapsed.Hours.ToString('00')):$($UI.Stopwatch.Elapsed.Minutes.ToString('00')):$($UI.Stopwatch.Elapsed.Seconds.ToString('00'))"
                If ($SetupPhase)
                {
                    $UI.DataSource[7] = $SetupPhase
                }
                If ($SetupSubPhase)
                {
                    $UI.DataSource[8] = $SetupSubPhase
                }
                If ($ProgressValue)
                {
                    If ($UI.InstallPhase -eq "Prepare" -and $ProgressValue.ToString() -ne "100")
                    {
                        $UI.DataSource[1] = $ProgressValue.ToString() + "%"
                        $UI.DataSource[4] = $ProgressValue.ToString()
                    }
                    ElseIf ($UI.InstallPhase -eq "Install" -and $ProgressValue.ToString() -ne "100")
                    {
                        $UI.DataSource[2] = $ProgressValue.ToString() + "%"
                        $UI.DataSource[5] = $ProgressValue.ToString()
                    }
                    ElseIf ($UI.InstallPhase -eq "Finalize" -and $ProgressValue.ToString() -ne "100")
                    {
                        $UI.DataSource[3] = $ProgressValue.ToString() + "%"
                        $UI.DataSource[6] = $ProgressValue.ToString()
                    }
                }
                
            }
            $UI.DispatcherTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
            $UI.DispatcherTimer.Interval = [TimeSpan]::FromSeconds(1)
            $UI.DispatcherTimer.Add_Tick($TimerCode)
            $UI.DispatcherTimer.Start()

            $Code = {
                Param($UI,$WorkingDirectory,$FullRegPath)
                Invoke-Update  
            }

            $Job = [BackgroundJob]::New($Code,@($UI,$WorkingDirectory,$FullRegPath),@("Function:\Invoke-Update","Function:\Write-UpgradeLog","Function:\Send-StatusUpdate"))
            $UI.Jobs += $Job
            $Job.Start()
        }
    }
    else 
    {
        Restart-Computer -Force    
    }
})

$UI.ChildText2.Add_PreviewMouseLeftButtonUp({
    $UI.Notifier.Close()
})

$UI.ChildText2.Add_MouseEnter({
    $This.Foreground="#03DAC5"
})

$UI.ChildText2.Add_MouseLeave({
    $This.Foreground="#BB86FC"
})

$UI.WindowActivator.Add_TextChanged({
    If ($UI.Window.IsActive -eq $false -and $UI.DataSource[26] -ne "")
    {
        Start-Sleep -Seconds 1
        $UI.SmallWindow.Close()
        $UI.Window.ShowDialog()
    }
})

