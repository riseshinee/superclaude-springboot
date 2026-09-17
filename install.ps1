<#
.SYNOPSIS
    Installs superclaude-springboot skills into a target Spring Boot project.
.EXAMPLE
    ./install.ps1 -TargetProject "C:\Users\me\workspace\my-spring-app"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetProject
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceDir = Join-Path $ScriptDir "skills"

if (-not (Test-Path $TargetProject)) {
    Write-Error "Target path does not exist: $TargetProject"
    exit 1
}

$DestDir = Join-Path (Join-Path $TargetProject ".claude") "skills"
New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

Get-ChildItem -Directory $SourceDir | ForEach-Object {
    $skillName = $_.Name
    $targetPath = Join-Path $DestDir $skillName

    if (Test-Path $targetPath) {
        $answer = Read-Host "'$skillName' already exists. Overwrite? [y/N]"
        if ($answer -notmatch '^[Yy]$') {
            Write-Host "Skipped: $skillName"
            return
        }
        Remove-Item -Recurse -Force $targetPath
    }

    Copy-Item -Recurse $_.FullName $targetPath
    Write-Host "Installed: $skillName -> $targetPath"
}

Write-Host "Done. Skills installed in ${DestDir}:"
Get-ChildItem -Name $DestDir
