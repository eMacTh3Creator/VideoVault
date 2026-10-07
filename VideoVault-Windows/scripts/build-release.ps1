param(
    [ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64',
    [string]$Version = '1.4.0',
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root "artifacts\$Runtime" }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$publish = Join-Path $OutputDirectory 'publish'
Push-Location $root
try {
    dotnet publish VideoVault.Windows\VideoVault.Windows.csproj -c Release -r $Runtime --self-contained true -p:Version=$Version -o $publish
    if ($LASTEXITCODE -ne 0) { throw 'Publish failed.' }
    $tools = Join-Path $root '.tools'
    if (-not (Test-Path "$tools\vpk.exe")) {
        dotnet tool install vpk --version 1.2.161 --tool-path $tools
        if ($LASTEXITCODE -ne 0) { throw 'Velopack CLI installation failed.' }
    }
    Copy-Item (Join-Path $root 'README.md') (Join-Path $publish 'README.md')
    & "$tools\vpk.exe" pack --packId VideoVault --packVersion $Version --packDir $publish --mainExe VideoVault.Windows.exe --packTitle VideoVault --packAuthors 'Everett Jenkins' --icon "$root\VideoVault.Windows\Assets\VideoVault.ico" --runtime $Runtime --channel $Runtime --outputDir $OutputDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Installer packaging failed.' }
    Get-ChildItem $OutputDirectory -File | Where-Object { $_.Extension -in '.exe', '.zip', '.nupkg', '.json' } | ForEach-Object {
        $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    } | Set-Content (Join-Path $OutputDirectory 'SHA256SUMS')
    Write-Host "Windows $Runtime packages: $OutputDirectory"
} finally { Pop-Location }
