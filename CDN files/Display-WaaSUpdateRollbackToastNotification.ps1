####################################################
## WINDOWS 10 UPGRADE ROLLBACK TOAST NOTIFICATION ##
####################################################

<#
Function Convert-Base64toFile {
    Param($Base64Sting,$OutputFileName)
    $File = "C:\Users\tjones\OneDrive\Pictures\H_toast.png"
    $Image = [System.Drawing.Image]::FromFile($File)
    $MemoryStream = New-Object System.IO.MemoryStream
    $Image.Save($MemoryStream, $Image.RawFormat)
    [System.Byte[]]$Bytes = $MemoryStream.ToArray()
    $Base64 = [System.Convert]::ToBase64String($Bytes)
    $Image.Dispose()
    $MemoryStream.Dispose()
    $Base64 | out-file "C:\Users\tjones\OneDrive\Pictures\H_toast.txt"
}
#>

# Set working registry location
$RootRegBase = "HKLM:\Software"
$RootRegBranchName = "IT"
$UpgradeBranchName = "1909Upgrade"
$FullRegPath = "$RootRegBase\$RootRegBranchName\$UpgradeBranchName"

######################
## OS Version Check ##
######################
# Before going any further, check that the OS has not already been upgraded
$Version = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ReleaseID -ErrorAction Stop).ReleaseID
If ($Version -eq "1909")
{
    Return
}

# Figure out who's logged on if possible
$GivenName = Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI -Name LastLoggedOnDisplayName -ErrorAction SilentlyContinue | Select -ExpandProperty LastLoggedOnDisplayName -ErrorAction SilentlyContinue
If ($GivenName)
{
    $Name = $GivenName.Split(',')[1].Trim().Split()[0]
}
Else
{
    $Name = "there"
}

# Notification parameters
$Title = "Hey $Name, we're sorry but your Windows 10 update failed"
$AudioSource = "ms-winsoundevent:Notification.Default"
$SubtitleText = "Something went wrong during the offline phase of the update and the operating system has been rolled back to the previous version."
$SubtitleText2 = "Please contact IT support before attempting to update again."


# Create the image and logo files from base64
$Base64Logo = "mybase64logo"
$Base64Image = "mybase6image"
$LogoFile = "$env:TEMP\ToastLogo.png"
[byte[]]$Bytes = [convert]::FromBase64String($Base64Logo)
[System.IO.File]::WriteAllBytes($LogoFile,$Bytes)
$ImageFile = "$env:TEMP\ToastImage.png"
[byte[]]$Bytes = [convert]::FromBase64String($Base64Image)
[System.IO.File]::WriteAllBytes($ImageFile,$Bytes)

# Load some required namespaces
$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

# Register the AppID in the registry for use with the Action Center, if required
$AppID = "contoso.com"
$RegPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
if (!(Test-Path -Path "$RegPath\$AppId")) {
    $null = New-Item -Path "$RegPath\$AppId" -Force
    $null = New-ItemProperty -Path "$RegPath\$AppId" -Name 'ShowInActionCenter' -Value 1 -PropertyType 'DWORD'
}

# Define the toast notification in XML format
[xml]$ToastTemplate = @"
<toast duration="long">
    <visual>
    <binding template="ToastGeneric">
        <text>Windows 10 1909</text> 
        <image placement="hero" src="$ImageFile"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoFile"/>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true" >$Title</text>
            </subgroup>
        </group>
        <group>          
            <subgroup>     
                <text hint-style="subtitle" hint-wrap="true" >$SubtitleText</text>
            </subgroup>
        </group>
        <group>          
            <subgroup>     
                <text hint-style="subtitle" hint-wrap="true" >$SubtitleText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <audio src="$AudioSource"/>
</toast>
"@


# Load the notification into the required format
$ToastXml = New-Object -TypeName Windows.Data.Xml.Dom.XmlDocument
$ToastXml.LoadXml($ToastTemplate.OuterXml)

# Display
$App = "contoso.com"
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show($ToastXml)