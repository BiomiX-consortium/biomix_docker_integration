#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# BiomiX launcher (Linux)
#
# - Checks Docker is installed and running.
# - Lets you pick the data folder and (optionally) an NCBI API key.
# - Starts BiomiX. Docker will automatically download any image that isn't
#   already present locally (the GUI image, and any sibling analysis image
#   it launches during a run), so no manual download step is needed here.
#
# macOS users: use the dedicated BiomiX Launcher app instead of this script.
# =============================================================================

GUI_IMAGE="ghcr.io/biomix-consortium/biomix-gui:latest"
CONFIG_DIR="$HOME/.biomix"
CONFIG_FILE="$CONFIG_DIR/config"
mkdir -p "$CONFIG_DIR"

# --- Check Docker is installed --------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] Docker was not found. Please install Docker Engine first."
    exit 1
fi

# --- Check Docker is running -----------------------------------------------------
if ! docker info >/dev/null 2>&1; then
    echo "[ERROR] The Docker service does not appear to be running."
    echo "Please start it (e.g. 'sudo systemctl start docker') and run this again."
    exit 1
fi

# --- Load previously used settings, if any ------------------------------------
SAVED_FOLDER=""
SAVED_KEY=""
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    SAVED_FOLDER="${SHARED_FOLDER:-}"
    SAVED_KEY="${NCBI_KEY:-}"
fi
DEFAULT_FOLDER="${SAVED_FOLDER:-$HOME/biomix_shared}"

# =============================================================================
# Data folder + NCBI key
# =============================================================================
SHARED_FOLDER=""
NCBI_KEY=""

if command -v zenity >/dev/null 2>&1; then

    SHARED_FOLDER=$(zenity --file-selection --directory \
        --title="Choose (or create) the folder BiomiX will use for data and results" \
        --filename="$DEFAULT_FOLDER/") || { echo "Cancelled."; exit 0; }

    NCBI_KEY=$(zenity --entry \
        --title="BiomiX" \
        --text="NCBI API key (optional - speeds up PubMed searches).\nYou can leave this blank and click OK to skip.\nGet one free at ncbi.nlm.nih.gov/account/settings" \
        --entry-text="$SAVED_KEY") || NCBI_KEY=""

else
    echo "(No graphical dialog tool found - install 'zenity' for a nicer experience: sudo apt install zenity)"
    echo ""
    read -r -p "Data folder [$DEFAULT_FOLDER]: " SHARED_FOLDER
    SHARED_FOLDER="${SHARED_FOLDER:-$DEFAULT_FOLDER}"
    read -r -p "NCBI API key (optional, press Enter to skip) [$SAVED_KEY]: " NCBI_KEY
    NCBI_KEY="${NCBI_KEY:-$SAVED_KEY}"
fi

if [ -z "$SHARED_FOLDER" ]; then
    echo "No folder chosen - aborting."
    exit 1
fi
mkdir -p "$SHARED_FOLDER"

cat > "$CONFIG_FILE" << EOF
SHARED_FOLDER="$SHARED_FOLDER"
NCBI_KEY="$NCBI_KEY"
EOF
# NOTE: the NCBI key is stored in plain text in this local config file
# (~/.biomix/config), for convenience across runs.

echo ""
echo "Data folder: $SHARED_FOLDER"
echo "Starting BiomiX... this terminal must stay open while you use BiomiX."
echo "Press Ctrl+C to stop it."
echo "(If this is the first run, Docker will download BiomiX components now - this can take a while.)"
echo ""

# --- Open the browser automatically after a short delay ------------------------
(
  sleep 6
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "http://localhost:3838"
  fi
) &

# --- Build and run the docker command --------------------------------------------
# -p 3838: main BiomiX web UI
# -p 3840: QC preview for the "Undefined" data type, which runs inside this
#          same GUI container (see README "Architecture" section)
DOCKER_ARGS=(run -p 3838:3838 -p 3840:3840 --rm -it
  -e "BIOMIX_HOST_SHARED_PATH=$SHARED_FOLDER"
  -v /var/run/docker.sock:/var/run/docker.sock
  -v "$SHARED_FOLDER:/shared")

if [ -n "$NCBI_KEY" ]; then
    DOCKER_ARGS+=(-e "NCBI_API_KEY=$NCBI_KEY")
fi

DOCKER_ARGS+=("$GUI_IMAGE")

docker "${DOCKER_ARGS[@]}"

echo ""
echo "BiomiX has stopped."
