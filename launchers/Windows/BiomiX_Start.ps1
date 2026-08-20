# =============================================================================
# BiomiX launcher (Windows) - simple graphical setup window.
#
# - Makes sure Docker Desktop is running (tries to start it automatically).
# - Lets the user pick the data folder and (optionally) an NCBI API key.
# - Starts BiomiX. Docker will automatically download any image that isn't
#   already present locally (the GUI image, and any sibling analysis image
#   it launches during a run), so no manual download step is needed here.
#
# This script is meant to be launched by BiomiX_Start.bat, which passes its
# own folder via -ScriptDir. Both files must be kept together.
# =============================================================================

param(
    [string]$ScriptDir = $PSScriptRoot
)

trap {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Red
    Write-Host " An error occurred:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ""
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            "BiomiX ran into a problem:`n`n$($_.Exception.Message)",
            "BiomiX - Error", "OK", "Error"
        ) | Out-Null
    } catch {}
    Read-Host "Press Enter to close this window"
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$GuiImage    = "ghcr.io/biomix-consortium/biomix-gui:latest"
$ConfigDir   = Join-Path $env:APPDATA "BiomiX"
$ConfigFile  = Join-Path $ConfigDir "config.json"

# --- Make sure Docker Desktop is running, trying to start it if not ---------
function Test-DockerReady {
    docker info *> $null
    return ($LASTEXITCODE -eq 0)
}

if (-not (Test-DockerReady)) {

    $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $dockerExePaths = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "$pf86\Docker\Docker\Docker Desktop.exe"
    )
    $dockerExe = $dockerExePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($dockerExe) {
        Write-Host "Docker Desktop is not running yet - starting it..."
        Start-Process -FilePath $dockerExe | Out-Null

        $waited = 0
        $timeoutSeconds = 90
        while (-not (Test-DockerReady) -and $waited -lt $timeoutSeconds) {
            Start-Sleep -Seconds 3
            $waited += 3
            Write-Host "Waiting for Docker Desktop to be ready... ($waited s)"
        }
    }

    if (-not (Test-DockerReady)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Docker Desktop does not appear to be running, and it could not be started automatically.`n`nPlease start Docker Desktop yourself, wait until it says 'Docker Desktop is running', then run this again.",
            "BiomiX", "OK", "Error"
        ) | Out-Null
        Read-Host "Press Enter to close this window"
        exit 1
    }
}

# --- Load previously used settings, if any ----------------------------------
$SavedFolder = ""
$SavedKey    = ""
if (Test-Path $ConfigFile) {
    try {
        $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        $SavedFolder = $cfg.SharedFolder
        $SavedKey    = $cfg.NcbiKey
    } catch {}
}
if ([string]::IsNullOrWhiteSpace($SavedFolder)) {
    $SavedFolder = Join-Path $env:USERPROFILE "Desktop\biomix_shared"
}

# =============================================================================
# Build the window
# =============================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "BiomiX"
$form.Size = New-Object System.Drawing.Size(560, 280)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$y = 20

# --- Data folder section -------------------------------------------------------
$lbl1 = New-Object System.Windows.Forms.Label
$lbl1.Text = "Data folder (your input files and analysis results):"
$lbl1.Location = New-Object System.Drawing.Point(15, $y)
$lbl1.Size = New-Object System.Drawing.Size(480, 20)
$form.Controls.Add($lbl1)
$y += 22

$txtFolder = New-Object System.Windows.Forms.TextBox
$txtFolder.Text = $SavedFolder
$txtFolder.Location = New-Object System.Drawing.Point(15, $y)
$txtFolder.Size = New-Object System.Drawing.Size(410, 20)
$form.Controls.Add($txtFolder)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Location = New-Object System.Drawing.Point(435, ($y - 2))
$btnBrowse.Size = New-Object System.Drawing.Size(95, 24)
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Choose (or create) the folder BiomiX will use for data and results"
    if (Test-Path $txtFolder.Text) { $dlg.SelectedPath = $txtFolder.Text }
    if ($dlg.ShowDialog() -eq "OK") { $txtFolder.Text = $dlg.SelectedPath }
})
$form.Controls.Add($btnBrowse)
$y += 32

# --- NCBI key section ------------------------------------------------------------
$lbl2 = New-Object System.Windows.Forms.Label
$lbl2.Text = "NCBI API key (optional - speeds up PubMed searches):"
$lbl2.Location = New-Object System.Drawing.Point(15, $y)
$lbl2.Size = New-Object System.Drawing.Size(480, 20)
$form.Controls.Add($lbl2)
$y += 22

$txtKey = New-Object System.Windows.Forms.TextBox
$txtKey.Text = $SavedKey
$txtKey.Location = New-Object System.Drawing.Point(15, $y)
$txtKey.Size = New-Object System.Drawing.Size(515, 20)
$form.Controls.Add($txtKey)
$y += 22

$lbl3 = New-Object System.Windows.Forms.Label
$lbl3.Text = "Get one for free at ncbi.nlm.nih.gov/account/settings"
$lbl3.Location = New-Object System.Drawing.Point(15, $y)
$lbl3.Size = New-Object System.Drawing.Size(485, 18)
$lbl3.ForeColor = [System.Drawing.Color]::Gray
$lbl3.Font = New-Object System.Drawing.Font($lbl3.Font.FontFamily, 8)
$form.Controls.Add($lbl3)
$y += 30

$lbl4 = New-Object System.Windows.Forms.Label
$lbl4.Text = "The first run will take longer while Docker downloads BiomiX components."
$lbl4.Location = New-Object System.Drawing.Point(15, $y)
$lbl4.Size = New-Object System.Drawing.Size(515, 18)
$lbl4.ForeColor = [System.Drawing.Color]::Gray
$lbl4.Font = New-Object System.Drawing.Font($lbl4.Font.FontFamily, 8)
$form.Controls.Add($lbl4)
$y += 30

# --- Start / Cancel buttons -------------------------------------------------------
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start BiomiX"
$btnStart.Location = New-Object System.Drawing.Point(335, $y)
$btnStart.Size = New-Object System.Drawing.Size(195, 35)
$btnStart.DialogResult = "OK"
$form.Controls.Add($btnStart)
$form.AcceptButton = $btnStart

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Location = New-Object System.Drawing.Point(220, $y)
$btnCancel.Size = New-Object System.Drawing.Size(100, 35)
$btnCancel.DialogResult = "Cancel"
$form.Controls.Add($btnCancel)
$form.CancelButton = $btnCancel

$form.ClientSize = New-Object System.Drawing.Size(550, ($y + 55))

$result = $form.ShowDialog()
if ($result -ne "OK") { exit 0 }

$SharedFolder = $txtFolder.Text.Trim()
$NcbiKey      = $txtKey.Text.Trim()

if ([string]::IsNullOrWhiteSpace($SharedFolder)) {
    [System.Windows.Forms.MessageBox]::Show("Please choose a folder.", "BiomiX", "OK", "Warning") | Out-Null
    Read-Host "Press Enter to close this window"
    exit 1
}
if (-not (Test-Path $SharedFolder)) {
    New-Item -ItemType Directory -Path $SharedFolder -Force | Out-Null
}

# --- Save settings for next time ---------------------------------------------
if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null }
@{ SharedFolder = $SharedFolder; NcbiKey = $NcbiKey } | ConvertTo-Json | Set-Content $ConfigFile
# NOTE: the NCBI key is stored in plain text in this local config file
# (%APPDATA%\BiomiX\config.json), for convenience across runs.

$SharedFolderDocker = $SharedFolder -replace '\\', '/'

Write-Host ""
Write-Host "Data folder: $SharedFolder"
Write-Host "Starting BiomiX... this window must stay open while you use BiomiX."
Write-Host "Close this window (or press Ctrl+C) to stop it."
Write-Host "(If this is the first run, Docker will download BiomiX components now - this can take a while.)"
Write-Host ""

# --- Open the browser automatically after a short delay ----------------------
Start-Job -ScriptBlock {
    Start-Sleep -Seconds 6
    Start-Process "http://localhost:3838"
} | Out-Null

# --- Build and run the docker command -----------------------------------------
$dockerArgs = @(
    "run", "-p", "3838:3838", "-p", "3840:3840", "--rm", "-it",
    "-e", "BIOMIX_HOST_SHARED_PATH=$SharedFolderDocker",
    "-v", "/var/run/docker.sock:/var/run/docker.sock",
    "-v", "${SharedFolderDocker}:/shared"
)
if (-not [string]::IsNullOrWhiteSpace($NcbiKey)) {
    $dockerArgs += @("-e", "NCBI_API_KEY=$NcbiKey")
}
$dockerArgs += $GuiImage

& docker @dockerArgs

Write-Host ""
Write-Host "BiomiX has stopped."
Read-Host "Press Enter to close this window"
