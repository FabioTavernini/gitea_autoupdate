param (
    [string]$SettingsFilePath,
    [string]$ProxyServer,
    [string]$ProxyUser,
    [string]$proxyPW,
    [string]$WindowsServer,
    [string]$WindowsUser,
    [string]$WindowsPW,
    [string]$GiteaServerURL,
    [string]$GiteaInstallPath,
    [string]$GiteaWindowsServiceName,
    [int]$UseProxy
)

# Load settings from the provided settings file
$settings = Get-Content $SettingsFilePath | ConvertFrom-Json

# Override settings with provided parameters if they are not null or empty
if ($ProxyServer) { $settings.ProxyServer = $ProxyServer }
if ($ProxyUser) { $settings.ProxyUser = $ProxyUser }
if ($proxyPW) { $settings.ProxyPW = $proxyPW }
if ($WindowsServer) { $settings.WindowsServer = $WindowsServer }
if ($WindowsUser) { $settings.WindowsUser = $WindowsUser }
if ($WindowsPW) { $settings.WindowsPW = $WindowsPW }
if ($GiteaServerURL) { $settings.GiteaServerURL = $GiteaServerURL }
if ($GiteaInstallPath) { $settings.GiteaInstallPath = $GiteaInstallPath }
if ($GiteaWindowsServiceName) { $settings.GiteaWindowsServiceName = $GiteaWindowsServiceName }
if ($UseProxy -ne $null) { $settings.UseProxy = $UseProxy }

# Convert proxy password to secure string
$secStringPasswordProxy = ConvertTo-SecureString $settings.ProxyPW -AsPlainText -Force
$proxycreds = New-Object System.Management.Automation.PSCredential ($settings.proxyUser, $secStringPasswordProxy)

# Convert Windows password to secure string
$secStringPasswordWindows = ConvertTo-SecureString $settings.WindowsPW -AsPlainText -Force
$WindowsCreds = New-Object System.Management.Automation.PSCredential ($settings.WindowsUser, $secStringPasswordWindows)

$headers = @{
    "Accept" = "application/vnd.github+json"
}

try {

    if ($settings.UseProxy -eq 1) {
        $currentrelease = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/go-gitea/gitea/releases/latest" -Headers $headers -Proxy $settings.ProxyServer -ProxyCredential $proxycreds
    }
    else {
        $currentrelease = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/go-gitea/gitea/releases/latest" -Headers $headers
    }

    $currentreleaseversion = $currentrelease.tag_name.Substring(1)

    $currentversion = (Invoke-RestMethod -Method Get -Uri ($settings.GiteaServerURL + "/api/v1/version")).version

}
catch {
    Write-Host "Failed to retrieve current version(s)"
}

if ($currentreleaseversion -gt $currentversion) {

    Write-Host -ForegroundColor red "Currently installed version ("$currentversion") older than available version ("$currentreleaseversion")"
    Write-Host -foregroundcolor green "Downloading newer version now"

    $downloadurl = ($currentrelease.assets | Where-Object { $_.name -eq "gitea-" + $currentreleaseversion + "-windows-4.0-amd64.exe" }).browser_download_url

    try {
        New-PSDrive -Root $settings.GiteaInstallPath -Name "Gitfiles" -PSProvider FileSystem -Credential $WindowsCreds
        New-Item Gitfiles:\Versionarchive\$currentreleaseversion -ItemType Directory

        $ArchiveFile = "GitFiles:\versionarchive\" + $currentreleaseversion + "\gitea-" + $currentreleaseversion + "-gogit-windows-4.0-amd64.exe"

        if ($settings.UseProxy -eq 1) {
            Invoke-WebRequest -Uri $downloadurl -OutFile $ArchiveFile -Proxy $settings.ProxyServer -ProxyCredential $proxycreds 
        }
        else {
            Invoke-WebRequest -Uri $downloadurl -OutFile $ArchiveFile
        }
    }
    catch {
        Write-Host -foregroundcolor red "Error downloading new version and storing in versionarchive"
    }

    $global:CheckServiceStatus = {
        param($Service)
        Get-Service -Name "$Service"
    }

    $global:ScriptBlock = {
        param($Service)

        $servicestatus = Get-Service -Name "$Service"

        if ($servicestatus.Status -eq "Running") {
            Stop-Service -Name "$Service" 
        }
        if ($servicestatus.Status -ne "Running") {
            Start-Service -Name "$Service" 
        }
    }

    try {
        Invoke-Command -ComputerName $settings.WindowsServer -Credential $WindowsCreds -ScriptBlock $ScriptBlock -ArgumentList $settings.GiteaWindowsServiceName
    }
    catch {
        Write-Host -foregroundcolor red "Error stopping gitea service (1)"
    }

    try {
        $GiteaStatus = (Invoke-Command -ComputerName $settings.WindowsServer -Credential $WindowsCreds -ScriptBlock $CheckServiceStatus -ArgumentList $settings.GiteaWindowsServiceName).Status

        do {
            $GiteaStatus = (Invoke-Command -ComputerName $settings.WindowsServer -Credential $WindowsCreds -ScriptBlock $CheckServiceStatus -ArgumentList $settings.GiteaWindowsServiceName).Status
            Write-Host -ForegroundColor Yellow $GiteaStatus
            Start-Sleep -Milliseconds 250
        } until ($GiteaStatus -eq "stopped")

    }
    catch {
        Write-Host -foregroundcolor red "Unable to retrieve status of GITEA Service"
    }

    try {
        copy-item $ArchiveFile -destination Gitfiles:\"gitea.exe" -Force
    }
    catch {
        Write-Host -foregroundcolor red "Error deleting and replacing gitea.exe file"
    }

    try {
        Invoke-Command -ComputerName $settings.WindowsServer -Credential $WindowsCreds -ScriptBlock $ScriptBlock -ArgumentList $settings.GiteaWindowsServiceName
    }
    catch {
        Write-Host -foregroundcolor red "Error starting gitea service (2)"
    }

    Write-Host -ForegroundColor green "Update completed"
}
elseif ($currentreleaseversion -eq $currentversion) {
    Write-Host -ForegroundColor green "Currently installed version is the same as available version"
}
else {
    Write-Host -ForegroundColor green "Currently installed version newer than available version"
}
