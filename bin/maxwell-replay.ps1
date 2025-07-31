#!/usr/bin/env pwsh

# Exit on error
$ErrorActionPreference = "Stop"

# Get the actual directory of the script
$actual_dir = $MyInvocation.MyCommand.Path
if ($actual_dir) {
    $actual_dir = [System.IO.Path]::GetFullPath($actual_dir)
}

$base_dir = Join-Path (Split-Path $actual_dir) ".."
$lib_dir = Join-Path $base_dir "lib"
$lib_dir_development = Join-Path $base_dir "target\lib"

if (-not (Test-Path $lib_dir) -and (Test-Path $lib_dir_development)) {
    $lib_dir = $lib_dir_development
    $env:CLASSPATH = "$env:CLASSPATH;$base_dir\target\classes"
}

$env:CLASSPATH = "$env:CLASSPATH;$lib_dir\*"

$KAFKA_VERSION = "1.0.0"

function Use-Kafka {
    param([string]$wanted)
    # disambiguate versions into the latest,
    # e.g. asking for 0.10 means you want the
    # latest 0.10.x release
    switch ($wanted) {
        "0.11" { $script:KAFKA_VERSION = "0.11.0.1" }
        "0.10" { $script:KAFKA_VERSION = "0.10.2.1" }
        default { $script:KAFKA_VERSION = $wanted }
    }
}

$DAEMON_MODE = $false
$DAEMON_NAME = ""

# Parse command line arguments
for ($i = 0; $i -lt $args.Count; $i++) {
    $key = $args[$i]
    switch -Wildcard ($key) {
        "--kafka_version" {
            if ($i + 1 -lt $args.Count) {
                Use-Kafka $args[$i + 1]
                $i++
            }
        }
        "--kafka_version=*" {
            $version = $key.Substring("--kafka_version=".Length)
            Use-Kafka $version
        }
        "--daemon" {
            $DAEMON_MODE = $true
            $DAEMON_NAME = "MaxwellReplay"
        }
    }
}

if ($DAEMON_MODE) {
    # Log directory to use
    if (-not $env:LOG_DIR) {
        $env:LOG_DIR = Join-Path $base_dir "logs"
    }
    # Create logs directory
    if (-not (Test-Path $env:LOG_DIR)) {
        New-Item -ItemType Directory -Path $env:LOG_DIR -Force | Out-Null
    }
    # Console output file when maxwell runs as a daemon
    $CONSOLE_OUTPUT_FILE = Join-Path $env:LOG_DIR "$DAEMON_NAME.out"
    Write-Host "Redirecting STDOUT to $CONSOLE_OUTPUT_FILE"
}

$kafka_client_dir = Join-Path $lib_dir "kafka-clients"
$kafka_client_jar = Get-ChildItem -Path $kafka_client_dir -Filter "kafka-clients-$KAFKA_VERSION*.jar" -ErrorAction SilentlyContinue

if (-not $kafka_client_jar -or $kafka_client_jar.Count -gt 1) {
    if (-not $kafka_client_jar) {
        Write-Host "Error: No matches for kafka version: $KAFKA_VERSION"
    } else {
        Write-Host "Error: Multiple matches for kafka version: $KAFKA_VERSION"
    }
    Write-Host "Supported versions:"
    Get-ChildItem -Path $kafka_client_dir | ForEach-Object {
        $name = $_.Name -replace "^kafka-clients-", " - " -replace "\.jar$", ""
        Write-Host $name
    }
    exit 1
} else {
    $env:CLASSPATH = "$env:CLASSPATH;$($kafka_client_jar.FullName)"
}

if (-not $env:JAVA_HOME) {
    $JAVA = "java"
} else {
    $JAVA = Join-Path $env:JAVA_HOME "bin\java.exe"
}

# Launch mode
if ($DAEMON_MODE) {
    $javaArgs = @(
        $env:JAVA_OPTS,
        "-Dfile.encoding=UTF-8",
        "-Dlog4j.shutdownCallbackRegistry=com.djdch.log4j.StaticShutdownCallbackRegistry",
        "-cp", $env:CLASSPATH,
        "com.zendesk.maxwell.replay.MaxwellReplayFile"
    ) + $args
    
    Start-Process -FilePath $JAVA -ArgumentList $javaArgs -RedirectStandardOutput $CONSOLE_OUTPUT_FILE -RedirectStandardError $CONSOLE_OUTPUT_FILE -WindowStyle Hidden
} else {
    $javaArgs = @(
        $env:JAVA_OPTS,
        "-Dfile.encoding=UTF-8",
        "-Dlog4j.shutdownCallbackRegistry=com.djdch.log4j.StaticShutdownCallbackRegistry",
        "-cp", $env:CLASSPATH,
        "com.zendesk.maxwell.replay.MaxwellReplayFile"
    ) + $args
    
    & $JAVA @javaArgs
} 