# Krita PIP by Tomáš Weiss
# This script is a simplified version of pip for installing PyPI packages for Krita python plugins automatically.
#
# Usage: .\kritapip.ps1 [plugin_folder_name] [pip command]

# Example: .\kritapip.ps1 my_plugin install numpy
#          .\kritapip.ps1 my_plugin install numpy==2.1.3
#          .\kritapip.ps1 my_plugin remove numpy
#          .\kritapip.ps1 my_plugin list


# Arguments
[CmdletBinding()]
param(
    [Parameter(Mandatory = $True, Position = 0)]
    [string]$Plugin,
    [Parameter(Mandatory = $True, Position = 1)]
    [string]$Command,
    [Parameter(Position = 2)]
    [string]$Package
)
$Python="3.10"
$Platform="win_amd64"


# Functions
function Get-KeyValue 
{
    # https://stackoverflow.com/questions/33520699/iterating-through-a-json-file-powershell
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        [PSCustomObject]$obj
    )
    $obj | Get-Member -MemberType NoteProperty | ForEach-Object {
        $key = $_.Name
        [PSCustomObject]@{Key = $key; Value = $obj."$key"}
    }
}

function Resolve-PackageVersion 
{
    param (
        [Parameter(Mandatory = $true)]
        $MetadataJson,
        [Parameter(Mandatory = $true)]
        [string]$PythonVersion,   
        [Parameter(Mandatory = $true)]
        [string]$Platform,        
        [string]$RequestedVersion 
    )

    $candidates = $MetadataJson.releases | Get-KeyValue | ForEach-Object { $_.Key } | Sort-Object -Descending

    # Filter candidates by version
    if ($RequestedVersion) 
    {
        if ($candidates -contains $RequestedVersion) 
        {
            $candidates = @($RequestedVersion)
        }
        else 
        {
            $candidates = $candidates | Where-Object { $_ -like "$RequestedVersion.*" }
            if (-not $candidates) 
            {
                Write-Host "No version starts with '$RequestedVersion' for package '$($MetadataJson.info.name)'" -ForegroundColor Red
                return $null
            }
        }
    }

    # Find specific package
    foreach ($candidate in $candidates) 
    {
        $releaseObjects = $MetadataJson.releases.$candidate

        foreach ($releaseObject in $releaseObjects) 
        {
            if ($releaseObject.python_version -eq $PythonVersion) 
            {
                $filenameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($releaseObject.filename)
                if ($filenameWithoutExt -match "$Platform$") 
                {
                    return [PSCustomObject]@{
                        Version = $candidate
                        Url     = $releaseObject.url
                        File    = $releaseObject.filename
                    }
                }
            }
        }
    }

    Write-Host "No matching wheel found for $($PypiMetadataJson.info.name) with version '$RequestedVersion' (Python=$PythonVersion, Platform=$Platform)" -ForegroundColor Red
    return $null
}

function Get-VendorDirectory 
{
    param (
        [Parameter(Mandatory = $true)]
        $PluginName,
        [Parameter(Mandatory = $true)]
        [string]$Create
    )

    $vendorDir = Join-Path -Path (Join-Path -Path $env:APPDATA -ChildPath "krita\pykrita\$PluginName") -ChildPath "vendor"
    if (-not (Test-Path $vendorDir)) 
    {
        if ($Create -eq $true)
        {
            New-Item -ItemType Directory -Path $vendorDir | Out-Null
        }
        else
        {
            Write-Host "No packages installed for plugin '$PluginName'." -ForegroundColor Yellow
        }
    }

    return $vendorDir
}


# Convert "3.10" => "cp310"
if ($Python -match "^(\d+)\.(\d+)")
{
    $pythonVersion = "cp" + $matches[1] + $matches[2]
} 
else 
{
    Write-Host "Invalid Python version format: $Python"
    return
}


# Execute command
switch ($Command.ToLower()) 
{
    "install" 
    {
        if (-not $Package) 
        {
            Write-Host "Usage: kritapip.ps1 <plugin> install <package> [==version]"
            return
        }

        # 1) Parse package name & version requirement
        if ($Package -match "^([^=]+)==(.+)$") 
        {
            $packageName      = $matches[1]
            $requestedVersion = $matches[2]
        }
        else {
            $packageName      = $Package
            $requestedVersion = $null
        }

        # 2) Fetch PyPI metadata
        try 
        {
            $json = (Invoke-WebRequest "https://pypi.org/pypi/$packageName/json").Content | ConvertFrom-Json
        }
        catch 
        {
            Write-Host "Failed to fetch package info from PyPI for '$packageName'." -ForegroundColor Red
            return
        }

        # 3) Resolve best matching version
        $match = Resolve-PackageVersion -MetadataJson $json `
                                        -PythonVersion $pythonVersion `
                                        -Platform $Platform `
                                        -RequestedVersion $requestedVersion
        if (-not $match) 
        {
            return
        }

        $foundVersion = $match.Version
        $urlToDownload = $match.Url
        $filename = $match.File

        # 4) Prepare vendor directory
        $vendorDir = Get-VendorDirectory -PluginName $Plugin `
                                         -Create $True

        Write-Host "Found version $foundVersion => $filename"
        Write-Host "Downloading from:"
        Write-Host "  $urlToDownload"

        # 5) Download
        $downloadPath = Join-Path $vendorDir $filename
        $webClient = New-Object System.Net.WebClient
        Write-Host "Downloading." -NoNewline
        $webClient.DownloadFileAsync([uri]$urlToDownload, $downloadPath)
        while ($webClient.IsBusy) 
        {
            Start-Sleep -Milliseconds 500
            Write-Host "." -NoNewline
        }
        Write-Host " Complete"

        # 6) Extract
        $zipPath = [System.IO.Path]::ChangeExtension($downloadPath, ".zip")
        Rename-Item -Path $downloadPath -NewName $zipPath
        Write-Host "Extracting $filename to $vendorDir"
        Expand-Archive -Path $zipPath -DestinationPath $vendorDir -Force

        Remove-Item -Path $downloadPath -ErrorAction Ignore
        Remove-Item -Path $zipPath -ErrorAction Ignore
        Write-Host "Done."
    }

    "uninstall" 
    {
        if (-not $Package) 
        {
            Write-Host "Usage: kritapip.ps1 <plugin> uninstall <package>"
            return
        }
        $vendorDir = Get-VendorDirectory -PluginName $Plugin `
                                         -Create $False

        $removed = $false
        Get-ChildItem $vendorDir -Directory | ForEach-Object 
        {
            if ($_.Name -match "^$Package" ) {
                Write-Host "Removing folder: $($_.FullName)"
                Remove-Item -Recurse -Force -Path $_.FullName
                $removed = $true
            }
        }
        if (-not $removed) 
        {
            Write-Host "No installed package found matching '$Package'." -ForegroundColor Yellow
        }
        else 
        {
            Write-Host "Uninstall complete."
        }
    }

    "list" 
    {
        $vendorDir = Get-VendorDirectory -PluginName $Plugin `
                                         -Create $False
        if (-not (Test-Path $vendorDir)) { return }

        Write-Host "Installed packages:"
        Write-Host ("Name".PadRight(30) + "Version")
        Write-Host ("----".PadRight(30) + "-------")

        foreach ($dir in (Get-ChildItem $vendorDir -Directory)) 
        {
            # Attempt to extract name and version from directory name
            # e.g. "requests-2.28.1.dist-info"
            if ($dir.Name -notmatch ".dist-info$")
            { continue }

            if ($dir.Name -match "^([^\.]+)-(\d[\w\.]+).dist-info") 
            {
                $name    = $matches[1]
                $version = $matches[2]
                # Trim any trailing `.dist-info` if present
                $version = $version -replace "\.dist-info$", ""
            }
            else 
            {
                # fallback: unknown name/version
                $name    = $dir.Name
                $version = "?"
            }

            $line = $name.PadRight(30) + $version
            Write-Host $line
        }
    }

    default 
    {
        Write-Host "Unknown command '$Command'. Supported commands: install, uninstall, list."
    }
}
