#------------------------------------------
# Script to dump a MySQL database from one environment and restore it to another.
# Database connection details are read from a single .env file using environment-prefixed variables.
#
# .env file format:
#   Variables are prefixed with the environment name, e.g.:
#     SOURCE_MYSQL_HOST="127.0.0.1"
#     SOURCE_MYSQL_PORT="3306"
#     SOURCE_MYSQL_DATABASE="database"
#     SOURCE_MYSQL_USER="admin"
#     SOURCE_MYSQL_PASSWORD="password"
#     SOURCE_MYSQL_SSL_MODE="REQUIRED"     # optional; use REQUIRED for Azure MySQL
#     TARGET_MYSQL_HOST="127.0.0.1"
#     TARGET_MYSQL_PORT="3306"
#     TARGET_MYSQL_DATABASE="database"
#     TARGET_MYSQL_USER="admin"
#     TARGET_MYSQL_PASSWORD="password"
#     MYSQL_BIN_PATH="C:\Program Files\MySQL\MySQL Server 8.0\bin"
#
# Usage:
#   .\DumpAndRestore.ps1 -EnvFile ".env"

param (
    [string]$EnvFile = "./config/.env__dump_and_restore"
)

#------------------------------------------
# Helper: Parse a .env file into a hashtable

function Read-EnvFile {
    param ([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host "ERROR: .env file not found: $Path" -ForegroundColor Red
        exit 1
    }

    $envVars = @{}

    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()

        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
            continue
        }

        # Match KEY=VALUE (value may be quoted, may have inline comment)
        if ($trimmed -match '^\s*([^=]+?)\s*=\s*"?(.*?)"?\s*(#.*)?$') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            $envVars[$key] = $value
        }
    }

    return $envVars
}

#------------------------------------------
# Helper: Extract DB connection details for a given environment prefix

function Get-DbConfig {
    param ([hashtable]$EnvVars)

    $config = @{
        TARGET_MYSQL_Host     = $EnvVars["TARGET_MYSQL_HOST"]
        TARGET_MYSQL_Port     = $EnvVars["TARGET_MYSQL_PORT"]
        TARGET_MYSQL_Database = $EnvVars["TARGET_MYSQL_DATABASE"]
        TARGET_MYSQL_User     = $EnvVars["TARGET_MYSQL_USER"]
        TARGET_MYSQL_Password = $EnvVars["TARGET_MYSQL_PASSWORD"]
        SOURCE_MYSQL_Host     = $EnvVars["SOURCE_MYSQL_HOST"]
        SOURCE_MYSQL_Port     = $EnvVars["SOURCE_MYSQL_PORT"]
        SOURCE_MYSQL_Database = $EnvVars["SOURCE_MYSQL_DATABASE"]
        SOURCE_MYSQL_User     = $EnvVars["SOURCE_MYSQL_USER"]
        SOURCE_MYSQL_Password  = $EnvVars["SOURCE_MYSQL_PASSWORD"]
        SOURCE_MYSQL_Ssl_Mode = if ($EnvVars["SOURCE_MYSQL_SSL_MODE"]) { $EnvVars["SOURCE_MYSQL_SSL_MODE"] } else { "DISABLED" }
        MYSQL_BIN_PATH        = $EnvVars["MYSQL_BIN_PATH"]
    }

    $required = $config.Keys | Where-Object { $_ -ne "SOURCE_MYSQL_Ssl_Mode" }
    foreach ($key in $required) {
        if ([string]::IsNullOrWhiteSpace($config[$key])) {
            Write-Host "ERROR: Missing '$key' in $EnvFile" -ForegroundColor Red
            exit 1
        }
    }

    return $config
}

#------------------------------------------
# Parse .env file and extract DB config

$envVars = Read-EnvFile -Path $EnvFile
$dbConfig = Get-DbConfig -EnvVars $envVars

#------------------------------------------
# Set up paths and variables

$DumpDir = "./data/dump_and_restore_area"
$MysqlDump = Join-Path $dbConfig.MYSQL_BIN_PATH "mysqldump"
$MysqlClient = Join-Path $dbConfig.MYSQL_BIN_PATH "mysql"

#------------------------------------------
# DUMP



Write-Host
Write-Host "========================================" -ForegroundColor Yellow
Write-Host " DUMP" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Source host:     $($dbConfig.SOURCE_MYSQL_Host)" -ForegroundColor Cyan
Write-Host "Source port:     $($dbConfig.SOURCE_MYSQL_Port)" -ForegroundColor Cyan
Write-Host "Source database: $($dbConfig.SOURCE_MYSQL_Database)" -ForegroundColor Cyan
Write-Host "Source user:     $($dbConfig.SOURCE_MYSQL_User)" -ForegroundColor Cyan
Write-Host

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$DumpFile = "$DumpDir/dump_$($dbConfig.SOURCE_MYSQL_Database)_$timestamp.sql"

Write-Host "Dumping database to: $DumpFile" -ForegroundColor Green

$env:MYSQL_PWD = $dbConfig.SOURCE_MYSQL_Password

& $MysqlDump `
    --host=$($dbConfig.SOURCE_MYSQL_Host) `
    --port=$($dbConfig.SOURCE_MYSQL_Port) `
    --user=$($dbConfig.SOURCE_MYSQL_User) `
    --ssl-mode=$($dbConfig.SOURCE_MYSQL_Ssl_Mode) `
    --single-transaction `
    --routines `
    --triggers `
    --events `
    --add-drop-database `
    --add-drop-table `
    --databases $($dbConfig.SOURCE_MYSQL_Database) `
    --result-file=$DumpFile

$env:MYSQL_PWD = $null

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Database dump failed with exit code $LASTEXITCODE." -ForegroundColor Red
    exit 1
}

$fileSize = (Get-Item $DumpFile).Length / 1MB

Write-Host "Dump completed successfully. File size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Green

#------------------------------------------
# RESTORE

if (-not (Test-Path $DumpFile)) {
    Write-Host "ERROR: Dump file not found: $DumpFile" -ForegroundColor Red
    exit 1
}

Write-Host
Write-Host "========================================" -ForegroundColor Yellow
Write-Host " RESTORE" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Target host:     $($dbConfig.TARGET_MYSQL_Host)" -ForegroundColor Cyan
Write-Host "Target port:     $($dbConfig.TARGET_MYSQL_Port)" -ForegroundColor Cyan
Write-Host "Target database: $($dbConfig.TARGET_MYSQL_Database)" -ForegroundColor Cyan
Write-Host "Target user:     $($dbConfig.TARGET_MYSQL_User)" -ForegroundColor Cyan
Write-Host "Dump file:       $DumpFile" -ForegroundColor Cyan
Write-Host

# Safety confirmation
if (-not $SkipConfirm) {
    Write-Host "WARNING: This will OVERWRITE the '$($dbConfig.TARGET_MYSQL_Database)' database on '$($dbConfig.TARGET_MYSQL_Host)'!" -ForegroundColor Red
    $confirm = Read-Host "Type 'Y' to continue"

    if ($confirm -ne "Y") {
        Write-Host "Restore aborted." -ForegroundColor Red
        exit 0
    }
}

Write-Host "Restoring database from: $DumpFile" -ForegroundColor Green

$env:MYSQL_PWD = $dbConfig.TARGET_MYSQL_Password

# Create the target database if it doesn't exist
& $MysqlClient `
    --host=$($dbConfig.TARGET_MYSQL_Host) `
    --port=$($dbConfig.TARGET_MYSQL_Port) `
    --user=$($dbConfig.TARGET_MYSQL_User) `
    --execute="CREATE DATABASE IF NOT EXISTS ``$($dbConfig.TARGET_MYSQL_Database)``;"

# Restore the dump
& $MysqlClient `
    --host=$($dbConfig.TARGET_MYSQL_Host) `
    --port=$($dbConfig.TARGET_MYSQL_Port) `
    --user=$($dbConfig.TARGET_MYSQL_User) `
    --database=$($dbConfig.TARGET_MYSQL_Database) `
    --execute="source $DumpFile"

$env:MYSQL_PWD = $null

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Database restore failed with exit code $LASTEXITCODE." -ForegroundColor Red
    exit 1
}

Write-Host "Restore completed successfully." -ForegroundColor Green

#------------------------------------------
# Summary

Write-Host
Write-Host "========================================" -ForegroundColor Green
Write-Host " Done!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

if (-not $RestoreOnly) {
    Write-Host "Dump file: $DumpFile" -ForegroundColor Cyan
}

Write-Host