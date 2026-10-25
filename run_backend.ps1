$ErrorActionPreference = 'Stop'
if (-not $env:SQL_SERVER) { $env:SQL_SERVER = 'lpc:.' }
if (-not $env:SQL_DATABASE) { $env:SQL_DATABASE = 'DB' }
if (-not $env:SQL_USER) { $env:SQL_USER = 'Codex' }
$passwordWasProvided = -not [string]::IsNullOrEmpty($env:SQL_PASSWORD)
if (-not $passwordWasProvided) {
    $secret = Read-Host "Contrasena del usuario SQL $($env:SQL_USER)" -AsSecureString
    $env:SQL_PASSWORD = [System.Net.NetworkCredential]::new('', $secret).Password
}
try {
    dotnet run --project "$PSScriptRoot\backend\Platformer.Api.csproj" --no-launch-profile
} finally {
    if (-not $passwordWasProvided) {
        Remove-Item Env:\SQL_PASSWORD -ErrorAction SilentlyContinue
    }
}
