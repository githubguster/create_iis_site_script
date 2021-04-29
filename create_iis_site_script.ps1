#Requires -RunAsAdministrator
#
# create iis web
# 2021/04/29
# auth: guster
#
[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false, HelpMessage="source directory")]
    [string] $source,
    [Parameter(Mandatory=$false, HelpMessage="destination directory")]
    [string] $destination,
    [Parameter(Mandatory=$false)]
    [string] $webName,
    [Parameter(Mandatory=$false)]
    [int] $webPort,
    [Parameter(Mandatory=$false)]
    [bool] $webPreloadEnable,
    [Parameter(Mandatory=$false)]
    [bool] $webSocketEnable
)

$DEFAULT_WEB_SITE_NAME="Default Web Site"

function copy_file {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $source,
        [Parameter(Mandatory=$true, Position=1)]
        [string] $destination
    )
    Write-Output "Copy $source to $destination"
    Copy-Item -Path $source -Destination $destination -Recurse -Force
}

function remove_file {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $source
    )
    Write-Output "Remove $source"
    Remove-Item -Path $source -Recurse -Force
}

#iinstall iis package
function iis_init {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, Position=0)]
        [bool] $preloadEnable,
        [Parameter(Mandatory=$false, Position=1)]
        [bool] $webSocketEnable
    )
    Write-Output "Install IIS Package"
    #feature list: DISM /Online /Get-Features
    #enable: DISM /Online /Enable-Feature /FeatureName:feature_name /All
    #disable: DISM /Online /Disable-Feature /FeatureName:feature_name
    #DISM /Online /Enable-Feature /FeatureName:IIS-DefaultDocument /All
    #DISM /Online /Enable-Feature /FeatureName:IIS-ASPNET /All
    #DISM /Online /Enable-Feature /FeatureName:IIS-ASPNET45 /All
    #DISM /Online /Enable-Feature /FeatureName:IIS-ApplicationInit /All
    #DISM /Online /Enable-Feature /FeatureName:IIS-WebSockets /All
    
    #feature list: Get-WindowsOptionalFeature -Online
    #enable: Enable-WindowsOptionalFeature -Online -FeatureName feature_name
    #disable: Disable-WindowsOptionalFeature -Online -FeatureName feature_name
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-DefaultDocument
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-ASPNET
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-ASPNET45
    if ($preloadEnable -eq $true) {
        Enable-WindowsOptionalFeature -Online -FeatureName IIS-ApplicationInit
    }
    if ($webSocketEnable -eq $true) {
        Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebSockets
    }
}

function create_new_app_pool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $name
    )
    Write-Output "Create Web App Pool $name"
    #property list: Get-ItemProperty IIS:\AppPools\web_name|select *
    #property list: Get-ItemProperty IIS:\AppPools\web_name -name name|select *
    #property list: (Get-IISAppPool -name 'web_name').name
    New-WebAppPool -Name "$name" -Force
    Set-ItemProperty -Path "IIS:\AppPools\$name" -Name managedRuntimeVersion -Value 'v4.0' -Force
    Set-ItemProperty -Path "IIS:\AppPools\$name" -Name managedPipelineMode -Value 'Integrated' -Force
    Set-ItemProperty -Path "IIS:\AppPools\$name" -Name processModel.identityType -Value 'ApplicationPoolIdentity' -Force
    Set-ItemProperty -Path "IIS:\AppPools\$name" -Name recycling.periodicRestart.time -Value '0.00:00:00' -Force
    restart_app_pool($name)
}

function start_app_pool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $name
    )
    Write-Output "Start Web App Pool $name"
    Start-WebAppPool -Name "$name"
}

function stop_app_pool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $name
    )
    Write-Output "Stop Web App Pool $name"
    Stop-WebAppPool -Name "$name"
}

function restart_app_pool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $name
    )
    stop_app_pool($name)
    start_app_pool($name)
}

function create_new_web_site {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $name,
        [Parameter(Mandatory=$true, Position=1)]
        [string] $appPool,
        [Parameter(Mandatory=$true, Position=2)]
        [string] $ip,
        [Parameter(Mandatory=$true, Position=3)]
        [int] $port,
        [Parameter(Mandatory=$true, Position=4)]
        [string] $path,
        [Parameter(Mandatory=$false, Position=5)]
        [bool] $preloadEnable
    )
    Write-Output "Create Web Site $name"
    #property list: Get-ItemProperty IIS:\Sites\web_name|select *
    #property list: Get-ItemProperty IIS:\Sites\web_name -name name|select *
    #property list: (Get-Website -name 'web_name').name
    New-Website -Name "$name" -ApplicationPool "$appPool" -IPAddress $ip -Port $port -PhysicalPath "$path" -Force
    if ($preloadEnable -eq $true) {
        Set-ItemProperty -Path "IIS:\Sites\$name" -Name applicationDefaults.preloadEnabled -Value "True" -Force
    }
    restart_web_site($name)
}

function append_web_site_binding {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $name,
        [Parameter(Mandatory=$true, Position=1)]
        [string] $protocol,
        [Parameter(Mandatory=$true, Position=2)]
        [string] $ip,
        [Parameter(Mandatory=$true, Position=3)]
        [int] $port
    )
    Write-Output "Append Web Site Binding Protocol $protocol IP $ip Port $port"
    #New-ItemProperty -Path "IIS:\Sites\$name" -Name bindings -Value @{protocol="$protocol";bindingInformation="$information";}
    New-WebBinding -Name "$name" -Protocol "$protocol" -IPAddress "$ip" -Port $port 
}

function remove_web_site_binding {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $name,
        [Parameter(Mandatory=$true, Position=1)]
        [string] $protocol,
        [Parameter(Mandatory=$true, Position=2)]
        [string] $ip,
        [Parameter(Mandatory=$true, Position=3)]
        [int] $port
    )
    Write-Output "Remove Web Site Binding Protocol $protocol IP $ip Port $port"
    Get-WebBinding -Name "$name" -Protocol "$protocol" -IPAddress "$ip" -Port $port | Remove-WebBinding
}

function set_web_site_certificate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $cn,
        [Parameter(Mandatory=$true, Position=1)]
        [string] $ip,
        [Parameter(Mandatory=$true, Position=2)]
        [int] $port
    )
    Write-Output "Create Web site certificate $ip\$port $cn"
    Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object {$_.Subject -eq "CN=$cn"} | New-Item -Path "IIS:\SslBindings\$ip!$port"
    Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object {$_.Subject -eq "CN=$cn"} | Set-Item -Path "IIS:\SslBindings\$ip!$port"
}

function start_web_site {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $name
    )
    Write-Output "Start Web Site $name"
    Start-Website -Name "$name"
}

function stop_web_site {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $name
    )
    Write-Output "Stop Web Site $name"
    Stop-Website -Name "$name"
}

function restart_web_site {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $name
    )
    stop_web_site($name)
    start_web_site($name)
}

function create_certificate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $file,
        [Parameter(Mandatory=$true, Position=1)]
        [string] $psd
    )
    Write-Output "Create certificate $file"
    Import-PfxCertificate -FilePath "$file" -CertStoreLocation "Cert:\LocalMachine\My" -Password (ConvertTo-SecureString -String "$psd" -AsPlainText -Force)
}

function remove_certificate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $cn
    )
    Write-Output "Remove certificate cn $cn"
    Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object {$_.Subject -eq "CN=$cn"} | Remove-Item
}

# main
Set-ExecutionPolicy Bypass -Scope Process
Import-Module WebAdministration

if (![string]::IsNullOrEmpty($source) -and
    ![string]::IsNullOrEmpty($destination) -and
    ![string]::IsNullOrEmpty($webName) -and
    $port -gt 0) {
    $physicalPath=(Get-Item "$source").Name
    $physicalPath="$destination\$physicalPath"
    iis_init($preloadEnable, $webSocketEnable)
    stop_web_site($DEFAULT_WEB_SITE_NAME)
    copy_file($source, $destination)
    create_new_app_pool($webName)
    create_new_web_site($webName, $webName, "*", $port, $destination, $preloadEnable, $physicalPath)
}
