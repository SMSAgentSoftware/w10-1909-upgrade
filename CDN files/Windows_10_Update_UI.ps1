##########################################################################
##                                                                      ##
##     POWERSHELL WPF TOOL TEMPLATE USING THE MAHAPPS.METRO LIBRARY     ##
##                                                                      ##
## Author:      Trevor Jones                                            ##
## Blog:        smsagent.blog                                           ##
##                                                                      ##
##########################################################################

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

# Exit if already running or completed
If ((Get-ItemProperty -Path $FullRegPath -Name CurrentStatus -ErrorAction SilentlyContinue | Select -ExpandProperty CurrentStatus -ErrorAction SilentlyContinue) -in ("Completed","Successfully updated","Preparing update","Running PreDownload before upgrade","Ready for install","Running Install","Ready for finalize","Running Finalize","Installed pending reboot"))
{
    Return
}
If (Get-CimInstance -Query "Select * from Win32_Process WHERE Name='PowerShell.exe' AND NOT ProcessID='$PID'" | Where {$_.CommandLine -match "Windows_10_Update_UI.ps1"})
{
    Return
}

# Set the location we are running from
$Source = $PSScriptRoot

# Load the function library
. "$Source\bin\FunctionLibrary.ps1"

# Load the required assemblies
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path "$Source\bin\Microsoft.Xaml.Behaviors.dll"
Add-Type -Path "$Source\bin\ControlzEx.dll"
Add-Type -Path "$Source\bin\MahApps.Metro.dll"
Add-Type -Path "$Source\bin\MahApps.Metro.SimpleChildWindow.dll"
Add-Type -Path "$Source\bin\MahApps.Metro.IconPacks.Core.dll"
Add-Type -Path "$Source\bin\MahApps.Metro.IconPacks.FontAwesome.dll"

# Load the main window XAML code
[XML]$Xaml = [System.IO.File]::ReadAllLines("$Source\Xaml\App.xaml") 

# Create a synchronized hash table and add the WPF window and its named elements to it
$Global:UI = [System.Collections.Hashtable]::Synchronized(@{})
$UI.Window = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml))
$xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | 
    ForEach-Object -Process {
        $UI.$($_.Name) = $UI.Window.FindName($_.Name)
    }


$Base64 = "iVBORw0KGgoAAAANSUhEUgAAAyAAAAHCCAIAAACYATqfAAAABGdBTUEAALGPC/xhBQAAAAlwSFlzAAAOwgAADsIBFShKgAAABC5JREFUeF7twQENAAAAwqD3T20PBwQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANyoAX1yAAFUaqhQAAAAAElFTkSuQmCC"
$BackgroundImage = New-Object System.Windows.Media.Imaging.BitmapImage
$BackgroundImage.BeginInit()
$BackgroundImage.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String($Base64)
$BackgroundImage.EndInit()
$UI.BackgroundImage.Source = $BackgroundImage

$Base64 = "MyBase64String"
$Logo = New-Object System.Windows.Media.Imaging.BitmapImage
$Logo.BeginInit()
$Logo.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String($Base64)
$Logo.EndInit()
$UI.Logo.Source = $Logo

# Used to set the install phase for the progress indicators
$UI.InstallPhase = "Prepare"


# Hold the background jobs here. Useful for querying the streams for any errors.
$UI.Jobs = @()
# View the error stream for the first background job, for example
#$UI.Jobs[0].PSInstance.Streams.Error

# Load in the other code libraries.
. "$Source\bin\ClassLibrary.ps1"
. "$Source\bin\EventLibrary.ps1"

$LastLoggedOnDisplayName = Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI -Name LastLoggedOnDisplayName -ErrorAction SilentlyContinue | Select -ExpandProperty LastLoggedOnDisplayName -ErrorAction SilentlyContinue
$LastLoggedOnUser = Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI -Name LastLoggedOnUser -ErrorAction SilentlyContinue | Select -ExpandProperty LastLoggedOnUser -ErrorAction SilentlyContinue
Write-upgradeLog -Message "Windows 10 Update Assistant was invoked by $LastLoggedOnDisplayName ($LastLoggedOnUser)"

# OC for data binding source
$UI.DataSource = New-Object System.Collections.ObjectModel.ObservableCollection[Object]
$UI.DataSource.Add("00:00:00") # [0] TimerText
$UI.DataSource.Add("0%")        # [1] Setup Progress (Prepare)
$UI.DataSource.Add("0%")        # [2] Setup Progress (Install)
$UI.DataSource.Add("0%")        # [3] Setup Progress (Finalize)
$UI.DataSource.Add("0")        # [4] Setup Progress Bar (Prepare)
$UI.DataSource.Add("0")        # [5] Setup Progress Bar (Install)
$UI.DataSource.Add("0")        # [6] Setup Progress Bar (Finalize)
$UI.DataSource.Add("0")        # [7] SetupPhase
$UI.DataSource.Add("0")        # [8] SetupSubPhase
$UI.DataSource.Add("#03DAC5")        # [9] Prepare colour
$UI.DataSource.Add("#A9A9A9")        # [10] Install Colour
$UI.DataSource.Add("#A9A9A9")        # [11] Finalize colour
$UI.DataSource.Add("Collapsed")      # [12] Page 2 visibility
$UI.DataSource.Add("Collapsed")      # [13] Page 3 visibility
$UI.DataSource.Add("SmileRegular")   # [14] Icon Type
$UI.DataSource.Add("#03DAC5")        # [15] Icon Foreground
$UI.DataSource.Add("The update has finished installing. Please restart your computer as soon as possible to complete the process.")        # [16] Finishing text
$UI.DataSource.Add("#03DAC5")        # [17] Finishing text colour
$UI.DataSource.Add("Collapsed")      # [18] SetupPhase & SetupSubPhase visibility
$UI.DataSource.Add("Cancel")      # [19] Button1 text
$UI.DataSource.Add("Begin")       # [20] Button2 text
$UI.DataSource.Add("Visible")      # [21] Button1 visibility
$UI.DataSource.Add("Visible")       # [22] Button2 visibility
$UI.DataSource.Add("PlugSolid")       # [23] Notification icon
$UI.DataSource.Add("Hide me")       # [24] Button3 text
$UI.DataSource.Add("Hidden")       # [25] Button3 visibility
$UI.DataSource.Add("")             # [26] Window activator


# Set the datacontext of the window to the OC for databinding
$UI.Window.DataContext = $UI.DataSource


# Display the main window

# Hide the PowerShell console window
$windowcode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
$asyncwindow = Add-Type -MemberDefinition $windowcode -Name Win32ShowWindowAsync -Namespace Win32Functions -PassThru
$null = $asyncwindow::ShowWindowAsync((Get-Process -PID $pid).MainWindowHandle, 0)

# Run the main window in an application
$app = New-Object -TypeName Windows.Application
$app.Properties
$app.Run($UI.Window)