#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# BiomiX launcher (macOS / Linux)
#
# - Checks Docker is running (tries to start it automatically on macOS).
# - Shows which BiomiX components are already downloaded, and lets you
#   choose which ones to download.
# - Lets you pick the data folder and (optionally) an NCBI API key.
# - Starts BiomiX.
# =============================================================================

GUI_IMAGE="ghcr.io/biomix-consortium/biomix-gui:V2"
CONFIG_DIR="$HOME/.biomix"
CONFIG_FILE="$CONFIG_DIR/config"
mkdir -p "$CONFIG_DIR"

# Name|Image pairs - keep in sync with the Windows launcher.
COMPONENTS=(
  "GUI (required)|ghcr.io/biomix-consortium/biomix-gui:V2"
  "Transcriptomics|ghcr.io/biomix-consortium/biomix-transcriptomics:V2"
  "Metabolomics|ghcr.io/biomix-consortium/biomix-metabolomics:V2"
  "Methylomics|ghcr.io/biomix-consortium/biomix-methylomics:V2"
  "MOFA / DIABLO|ghcr.io/biomix-consortium/biomix-mofa-diablo:V2"
  "SNF / NEMO|ghcr.io/biomix-consortium/biomix-snf-nemo:V2"
  "Interpretation|ghcr.io/biomix-consortium/biomix-interpretation:V2"
)

IS_MAC=false
[[ "$OSTYPE" == "darwin"* ]] && IS_MAC=true

# --- Helper: is an image present locally? ------------------------------------
image_present() {
    local ref="$1"
    [ -n "$(docker images -q "$ref" 2>/dev/null)" ]
}

# --- Check Docker is installed --------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] Docker was not found. Please install Docker Desktop (Mac) or Docker Engine (Linux) first."
    exit 1
fi

# --- Check Docker is running, try to start it automatically on macOS -----------
if ! docker info >/dev/null 2>&1; then
    if $IS_MAC && [ -d "/Applications/Docker.app" ]; then
        echo "Docker Desktop is not running yet - starting it..."
        open -a Docker

        waited=0
        timeout_seconds=90
        while ! docker info >/dev/null 2>&1 && [ "$waited" -lt "$timeout_seconds" ]; do
            sleep 3
            waited=$((waited + 3))
            echo "Waiting for Docker Desktop to be ready... (${waited}s)"
        done
    fi

    if ! docker info >/dev/null 2>&1; then
        if $IS_MAC; then
            echo "[ERROR] Docker Desktop does not appear to be running, and it could not be started automatically."
            echo "Please start Docker Desktop yourself, wait until it is ready, then run this again."
        else
            echo "[ERROR] The Docker service does not appear to be running."
            echo "Please start it (e.g. 'sudo systemctl start docker') and run this again."
        fi
        exit 1
    fi
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
# Component selection
# =============================================================================
echo ""
echo "Checking which BiomiX components are already downloaded..."
declare -a TO_PULL=()

if $IS_MAC && command -v osascript >/dev/null 2>&1; then

    # Build the AppleScript list, pre-selecting components not yet downloaded.
    items_list=""
    default_list=""
    for entry in "${COMPONENTS[@]}"; do
        name="${entry%%|*}"
        image="${entry##*|}"
        if image_present "$image"; then
            status="[downloaded] $name"
        else
            status="[missing] $name"
            default_list="${default_list}\"${status}\", "
        fi
        items_list="${items_list}\"${status}\", "
    done
    items_list="${items_list%, }"
    default_list="${default_list%, }"
    [ -z "$default_list" ] && default_list="{}"  || default_list="{${default_list}}"

    selected=$(osascript -e "
        set theItems to {${items_list}}
        set theDefaults to ${default_list}
        set chosen to choose from list theItems with title \"BiomiX\" with prompt \"Select the components to download:\" default items theDefaults with multiple selections allowed
        if chosen is false then
            return \"CANCELLED\"
        end if
        set AppleScript's text item delimiters to \"|||\"
        set chosenText to chosen as text
        return chosenText
    ") || selected="CANCELLED"

    if [ "$selected" = "CANCELLED" ]; then
        echo "Cancelled."
        exit 0
    fi

    IFS='|||' read -ra chosen_arr <<< "$selected"
    for entry in "${COMPONENTS[@]}"; do
        name="${entry%%|*}"
        image="${entry##*|}"
        for c in "${chosen_arr[@]}"; do
            if [[ "$c" == *"$name" ]]; then
                TO_PULL+=("$image|$name")
            fi
        done
    done

elif command -v zenity >/dev/null 2>&1; then

    zenity_args=(--list --checklist --width=520 --height=350
        --title="BiomiX" --text="Select the components to download:"
        --column="Download" --column="Status" --column="Component" --separator="\n" --print-column=3)

    declare -A image_by_name
    for entry in "${COMPONENTS[@]}"; do
        name="${entry%%|*}"
        image="${entry##*|}"
        image_by_name["$name"]="$image"
        if image_present "$image"; then
            zenity_args+=(FALSE "downloaded" "$name")
        else
            zenity_args+=(TRUE "missing" "$name")
        fi
    done

    selected=$(zenity "${zenity_args[@]}") || { echo "Cancelled."; exit 0; }

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        TO_PULL+=("${image_by_name[$name]}|$name")
    done <<< "$selected"

else
    echo "(No graphical dialog tool found - install 'zenity' for a nicer experience: sudo apt install zenity)"
    echo ""
    for entry in "${COMPONENTS[@]}"; do
        name="${entry%%|*}"
        image="${entry##*|}"
        if image_present "$image"; then
            default="n"
            status="already downloaded"
        else
            default="y"
            status="missing"
        fi
        read -r -p "Download '$name' ($status)? [Y/n default: $default] " answer
        answer="${answer:-$default}"
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            TO_PULL+=("$image|$name")
        fi
    done
fi

# --- Pull the selected components ------------------------------------------------
if [ "${#TO_PULL[@]}" -eq 0 ]; then
    echo "No components selected to download."
else
    for pair in "${TO_PULL[@]}"; do
        image="${pair%%|*}"
        name="${pair##*|}"
        if image_present "$image"; then
            echo "Already downloaded: $name"
        else
            echo "Downloading: $name..."
            docker pull "$image"
            echo "Done: $name"
            echo ""
        fi
    done
fi

if ! image_present "$GUI_IMAGE"; then
    echo ""
    echo "[ERROR] The BiomiX GUI component has not been downloaded. Cannot start BiomiX without it."
    exit 1
fi

# =============================================================================
# Data folder + NCBI key
# =============================================================================
SHARED_FOLDER=""
NCBI_KEY=""

if $IS_MAC && command -v osascript >/dev/null 2>&1; then

    SHARED_FOLDER=$(osascript -e "
        set defaultFolder to POSIX file \"$DEFAULT_FOLDER\"
        try
            set chosenFolder to choose folder with prompt \"Choose (or create) the folder BiomiX will use for data and results:\" default location defaultFolder
        on error
            set chosenFolder to choose folder with prompt \"Choose (or create) the folder BiomiX will use for data and results:\"
        end try
        POSIX path of chosenFolder
    ") || { echo "Cancelled."; exit 0; }

    NCBI_KEY=$(osascript -e "
        text returned of (display dialog \"NCBI API key (optional - speeds up PubMed searches). Get one free at ncbi.nlm.nih.gov/account/settings\" default answer \"$SAVED_KEY\" with title \"BiomiX\")
    ") || NCBI_KEY=""

elif command -v zenity >/dev/null 2>&1; then

    SHARED_FOLDER=$(zenity --file-selection --directory \
        --title="Choose (or create) the folder BiomiX will use for data and results" \
        --filename="$DEFAULT_FOLDER/") || { echo "Cancelled."; exit 0; }

    NCBI_KEY=$(zenity --entry \
        --title="BiomiX" \
        --text="NCBI API key (optional - speeds up PubMed searches).\nGet one free at ncbi.nlm.nih.gov/account/settings" \
        --entry-text="$SAVED_KEY") || NCBI_KEY=""

else
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
echo ""

# --- Open the browser automatically after a short delay ------------------------
(
  sleep 6
  if command -v open >/dev/null 2>&1; then
    open "http://localhost:3838"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "http://localhost:3838"
  fi
) &

# --- Build and run the docker command --------------------------------------------
DOCKER_ARGS=(run -p 3838:3838 --rm -it
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
