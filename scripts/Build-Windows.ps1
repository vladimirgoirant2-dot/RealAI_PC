[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$packagesDirectory = Join-Path $repositoryRoot 'packages'

function Restore-NuGetPackage {
    param(
        [string]$Id,
        [string]$Version,
        [string]$RequiredFile
    )

    $packageDirectory = Join-Path $packagesDirectory "$Id.$Version"
    if (Test-Path (Join-Path $packageDirectory $RequiredFile)) {
        return $packageDirectory
    }

    if (Test-Path $packageDirectory) {
        Remove-Item -LiteralPath $packageDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null

    $lowercaseId = $Id.ToLowerInvariant()
    $packageUrl = "https://api.nuget.org/v3-flatcontainer/$lowercaseId/$Version/$lowercaseId.$Version.nupkg"
    $archivePath = Join-Path $env:TEMP ([guid]::NewGuid().ToString() + '.nupkg')
    try {
        Write-Host "Downloading $Id $Version..."
        Invoke-WebRequest -Uri $packageUrl -OutFile $archivePath -UseBasicParsing
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $packageDirectory)
    }
    finally {
        if (Test-Path $archivePath) {
            Remove-Item -LiteralPath $archivePath -Force
        }
    }

    return $packageDirectory
}

$msbuildCommand = Get-Command 'MSBuild.exe' -ErrorAction SilentlyContinue
if ($msbuildCommand) {
    $msbuildPath = $msbuildCommand.Source
}
else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $msbuildPath = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
    }
}

if (-not $msbuildPath -or -not (Test-Path $msbuildPath)) {
    throw 'Visual Studio 2022 MSBuild was not found. Install Visual Studio 2022 Build Tools with the .NET desktop build tools, or add its MSBuild.exe to PATH.'
}

$msbuildVersion = & $msbuildPath -version -nologo | Select-Object -Last 1
if ([version]$msbuildVersion -lt [version]'17.0') {
    throw "Visual Studio 2022 MSBuild (version 17 or later) is required; found version $msbuildVersion."
}

$frameworkRoot = Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework'
if (Test-Path (Join-Path $frameworkRoot '.NETFramework\v4.7.2')) {
    $targetFrameworkRootPath = $frameworkRoot
}
else {
    $referencePackage = Restore-NuGetPackage -Id 'Microsoft.NETFramework.ReferenceAssemblies.net472' -Version '1.0.3' -RequiredFile '.NETFramework\v4.7.2\RedistList\FrameworkList.xml'
    $targetFrameworkRootPath = Join-Path $referencePackage 'build'
}

$sqlitePackage = Restore-NuGetPackage -Id 'Stub.System.Data.SQLite.Core.NetFramework' -Version '1.0.119' -RequiredFile 'build\net46\x64\SQLite.Interop.dll'
$managedProvider = Join-Path $sqlitePackage 'lib\net46\System.Data.SQLite.dll'
$nativeProvider = Join-Path $sqlitePackage 'build\net46\x64\SQLite.Interop.dll'
if (-not (Test-Path $managedProvider) -or -not (Test-Path $nativeProvider)) {
    throw "The SQLite NuGet package is missing required .NET or x64 files: $sqlitePackage"
}

$configuration = 'Release'
$platform = 'Any CPU'
$solutionPath = Join-Path $repositoryRoot 'Real AI.sln'
$buildOutput = Join-Path $repositoryRoot 'Real AI\bin\Release'
$artifactDirectory = Join-Path $repositoryRoot 'artifacts'
$stagingDirectory = Join-Path $artifactDirectory 'RealAI-PC-win-x64'
$archiveOutput = Join-Path $artifactDirectory 'RealAI-PC-win-x64.zip'

Write-Host "Building $solutionPath..."
& $msbuildPath $solutionPath /nologo /verbosity:minimal /target:Rebuild "/property:Configuration=$configuration" "/property:Platform=$platform" "/property:TargetFrameworkRootPath=$targetFrameworkRootPath"
if ($LASTEXITCODE -ne 0) {
    throw "MSBuild failed with exit code $LASTEXITCODE."
}

$executable = Join-Path $buildOutput 'Real AI.exe'
$providerOutput = Join-Path $buildOutput 'System.Data.SQLite.dll'
$nativeOutput = Join-Path $buildOutput 'x64\SQLite.Interop.dll'
foreach ($requiredFile in @($executable, "$executable.config", $providerOutput, $nativeOutput)) {
    if (-not (Test-Path $requiredFile)) {
        throw "Build output is missing a required runtime file: $requiredFile"
    }
}

New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
if (Test-Path $stagingDirectory) {
    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
}
if (Test-Path $archiveOutput) {
    Remove-Item -LiteralPath $archiveOutput -Force
}

New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
Copy-Item -Path (Join-Path $buildOutput '*') -Destination $stagingDirectory -Recurse -Force
$unusedX86Directory = Join-Path $stagingDirectory 'x86'
if (Test-Path $unusedX86Directory) {
    Remove-Item -LiteralPath $unusedX86Directory -Recurse -Force
}

Compress-Archive -Path (Join-Path $stagingDirectory '*') -DestinationPath $archiveOutput -CompressionLevel Optimal
Write-Host "Portable x64 application: $stagingDirectory"
Write-Host "Distribution archive: $archiveOutput"
