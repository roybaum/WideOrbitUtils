$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'Modules\WideOrbit\WideOrbit.psd1'

if (!(Test-Path $moduleManifest)) {
    throw "Could not find the project-local WideOrbit module at '$moduleManifest'. Run .\Install.ps1 first."
}

# Load commands from the project-local module copy.
Import-Module -Name $moduleManifest -Force -ErrorAction Stop
