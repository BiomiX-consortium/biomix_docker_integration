# =============================================================================
# BiomiX launcher (Windows) - simple graphical setup window.
#
# - Makes sure Docker Desktop is running (tries to start it automatically).
# - Shows which BiomiX images are already downloaded, with a button to
#   download the missing ones.
# - Lets the user pick the data folder and (optionally) an NCBI API key.
# - Starts BiomiX.
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

$GuiImage    = "ghcr.io/biomix-consortium/biomix-gui:V2"
$ConfigDir   = Join-Path $env:APPDATA "BiomiX"
$ConfigFile  = Join-Path $ConfigDir "config.json"

# Images shown in the checklist. The GUI image is required to start BiomiX at
# all; the others are used during specific analysis steps and can be pulled
# ahead of time so the pipeline doesn't stall later.
$RequiredImages = @(
    @{ Name = "GUI (required)";        Image = "ghcr.io/biomix-consortium/biomix-gui:V2" },
    @{ Name = "Transcriptomics";       Image = "ghcr.io/biomix-consortium/biomix-transcriptomics:V2" },
    @{ Name = "Metabolomics";          Image = "ghcr.io/biomix-consortium/biomix-metabolomics:V2" },
    @{ Name = "Methylomics";           Image = "ghcr.io/biomix-consortium/biomix-methylomics:V2" },
    @{ Name = "MOFA / DIABLO";         Image = "ghcr.io/biomix-consortium/biomix-mofa-diablo:V2" },
    @{ Name = "SNF / NEMO";            Image = "ghcr.io/biomix-consortium/biomix-snf-nemo:V2" },
    @{ Name = "Interpretation";        Image = "ghcr.io/biomix-consortium/biomix-interpretation:V2" }
)

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

# --- Helper: is an image present locally? ------------------------------------
function Test-ImagePresent {
    param([string]$ImageRef)
    $found = & docker images -q $ImageRef 2>$null
    return (-not [string]::IsNullOrWhiteSpace($found))
}

# =============================================================================
# Build the window
# =============================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "BiomiX"
$form.Size = New-Object System.Drawing.Size(560, 560)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# --- Images checklist section -------------------------------------------------
$lblImages = New-Object System.Windows.Forms.Label
$lblImages.Text = "BiomiX components (check the ones to download):"
$lblImages.Location = New-Object System.Drawing.Point(15, 15)
$lblImages.Size = New-Object System.Drawing.Size(400, 20)
$lblImages.Font = New-Object System.Drawing.Font($lblImages.Font, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblImages)

$dotLabels = @{}
$checkBoxes = @{}
$y = 40
foreach ($img in $RequiredImages) {
    $dot = New-Object System.Windows.Forms.Label
    $dot.Text = "*"
    $dot.Location = New-Object System.Drawing.Point(20, $y)
    $dot.Size = New-Object System.Drawing.Size(20, 20)
    $dot.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($dot)
    $dotLabels[$img.Image] = $dot

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = $img.Name
    $chk.Location = New-Object System.Drawing.Point(45, ($y + 1))
    $chk.Size = New-Object System.Drawing.Size(480, 20)
    # Pre-check components that are not yet downloaded, as a helpful default.
    $chk.Checked = -not (Test-ImagePresent -ImageRef $img.Image)
    $form.Controls.Add($chk)
    $checkBoxes[$img.Image] = $chk

    $y += 24
}

function Update-ImageDots {
    foreach ($img in $RequiredImages) {
        $present = Test-ImagePresent -ImageRef $img.Image
        $dot = $dotLabels[$img.Image]
        if ($present) {
            $dot.Text = [char]0x25CF
            $dot.ForeColor = [System.Drawing.Color]::ForestGreen
        } else {
            $dot.Text = [char]0x25CF
            $dot.ForeColor = [System.Drawing.Color]::Firebrick
        }
    }
}

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(15, ($y + 5))
$logBox.Size = New-Object System.Drawing.Size(515, 90)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 8)
$form.Controls.Add($logBox)
$y += 100

$btnPull = New-Object System.Windows.Forms.Button
$btnPull.Text = "Download checked components"
$btnPull.Location = New-Object System.Drawing.Point(15, $y)
$btnPull.Size = New-Object System.Drawing.Size(240, 28)
$form.Controls.Add($btnPull)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"
$btnRefresh.Location = New-Object System.Drawing.Point(265, $y)
$btnRefresh.Size = New-Object System.Drawing.Size(100, 28)
$form.Controls.Add($btnRefresh)

$btnRefresh.Add_Click({ Update-ImageDots })

$btnPull.Add_Click({
    $btnPull.Enabled = $false
    $btnRefresh.Enabled = $false
    $logBox.Clear()

    $anyChecked = $false
    foreach ($img in $RequiredImages) {
        if (-not $checkBoxes[$img.Image].Checked) { continue }
        $anyChecked = $true
        if (-not (Test-ImagePresent -ImageRef $img.Image)) {
            $logBox.AppendText("Downloading: $($img.Name)...`r`n")
            $logBox.SelectionStart = $logBox.Text.Length
            $logBox.ScrollToCaret()
            [System.Windows.Forms.Application]::DoEvents()

            & docker pull $img.Image 2>&1 | ForEach-Object {
                $logBox.AppendText("$_`r`n")
                $logBox.SelectionStart = $logBox.Text.Length
                $logBox.ScrollToCaret()
                [System.Windows.Forms.Application]::DoEvents()
            }

            $logBox.AppendText("Done: $($img.Name)`r`n`r`n")
            [System.Windows.Forms.Application]::DoEvents()
        } else {
            $logBox.AppendText("Already downloaded: $($img.Name)`r`n")
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    if (-not $anyChecked) {
        $logBox.AppendText("No components were checked - nothing to download.`r`n")
    } else {
        $logBox.AppendText("All done.`r`n")
    }
    Update-ImageDots
    $btnPull.Enabled = $true
    $btnRefresh.Enabled = $true
})

$y += 38

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

Update-ImageDots

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
if (-not (Test-ImagePresent -ImageRef $GuiImage)) {
    [System.Windows.Forms.MessageBox]::Show(
        "The BiomiX GUI component has not been downloaded yet.`n`nPlease click 'Download missing components' first.",
        "BiomiX", "OK", "Warning"
    ) | Out-Null
    Read-Host "Press Enter to close this window"
    exit 1
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
Write-Host ""

# --- Open the browser automatically after a short delay ----------------------
Start-Job -ScriptBlock {
    Start-Sleep -Seconds 6
    Start-Process "http://localhost:3838"
} | Out-Null

# --- Build and run the docker command -----------------------------------------
$dockerArgs = @(
    "run", "-p", "3838:3838", "--rm", "-it",
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
