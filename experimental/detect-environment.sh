#!/bin/bash
#
# Detects the environment required to run FFXIV.
#

# ============================== Helpers ============================== #

. ../helpers/error.sh
. ../helpers/prompt.sh

get_ffxiv_pid() {
    FFXIV_PID="$(ps axo pid,cmd | grep -Pi '(|ff)xivlauncher(|64).exe' | grep -vi grep | sed -e 's/^[[:space:]]*//' | cut -d' ' -f1)"
}

# ============================== Main ============================== #

echo "Setting up the FFXIV Environment scripts."
echo
echo "This script will require you to open the FFXIV launcher from Lutris or Steam as if you were going to play the game normally."
echo

PROMPT_CONTINUE

#
# Detect PID of the running launcher application
#

get_ffxiv_pid

if [[ "$FFXIV_PID" == "" ]]; then
    warn "Please open the FFXIV Launcher. Checking for process \"xivlauncher.exe\", \"ffxivlauncher.exe\" or \"ffxivlauncher64.exe\"..."
    while [[ "$FFXIV_PID" == "" ]]; do
        sleep 1
        get_ffxiv_pid
    done
fi

success "FFXIV Launcher PID found! ($FFXIV_PID)"

#
# Extract environment used by the launcher
#

echo "Detecting environment information based on FFXIV Launcher environment..."

FFXIV_ENV="$(cat /proc/$FFXIV_PID/environ | xargs -0 bash -c 'printf "export %q\n" "$@"')"

IS_STEAM=0
REQ_ENV_VARS_REGEX="(DRI_PRIME|LD_LIBRARY_PATH|PYTHONPATH|SDL_VIDEO_FULLSCREEN_DISPLAY|STEAM_RUNTIME|WINEDLLPATH|WINEPREFIX|WINE_MONO_OVERRIDES|WINEESYNC|PROTON_VR_RUNTIME|WINEDLLOVERRIDES|WINELOADERNOEXEC|WINEPRELOADRESERVE|DXVK|export WINE=)"

if [[ "$(echo "$FFXIV_ENV" | grep SteamGameId)" != "" ]]; then
    warn "Looks like you're using Steam, configuring for Steam runtime."
    IS_STEAM=1
    REQ_ENV_VARS_REGEX="(LD_LIBRARY_PATH|SteamUser|ENABLE_VK_LAYER_VALVE_steam_overlay_1|SteamGameId|STEAM_RUNTIME_LIBRARY_PATH|STEAM_CLIENT_CONFIG_FILE|SteamAppId|SDL_GAMECONTROLLERCONFIG|SteamStreamingHardwareEncodingNVIDIA|SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD|STEAM_ZENITY|STEAM_RUNTIME|SteamClientLaunch|SteamStreamingHardwareEncodingIntel|STEAM_COMPAT_CLIENT_INSTALL_PATH|STEAM_COMPAT_DATA_PATH|EnableConfiguratorSupport|SteamAppUser|SDL_VIDEO_X11_DGAMOUSE|SteamStreamingHardwareEncodingAMD|SDL_GAMECONTROLLER_IGNORE_DEVICES|STEAMSCRIPT_VERSION|DXVK_LOG_LEVEL|WINEDLLPATH|WINEPREFIX|WINE_MONO_OVERRIDES|WINEESYNC|PROTON_VR_RUNTIME|WINEDLLOVERRIDES|WINELOADERNOEXEC|WINEPRELOADRESERVE|export WINE=|export PATH=)"
fi

FFXIV_ENV_FINAL="$(echo "$FFXIV_ENV" | grep -P "$REQ_ENV_VARS_REGEX")"

if [[ "$IS_STEAM" == "1" ]]; then
    # Add WINE= env var for Steam setup - it is not present otherwise
    FFXIV_ENV_FINAL="$FFXIV_ENV_FINAL"$'\n'"export WINE=$(echo "$FFXIV_ENV_FINAL" | grep 'export PATH' | cut -d'=' -f2 | tr ':' $'\n' | grep -i '/dist/')wine"

    # Remove PATH= from Environment now that we have the Proton path
    FFXIV_ENV_FINAL="$(echo "$FFXIV_ENV_FINAL" | grep -v 'export PATH=')"
fi

# Add FFXIV game path to environment for use in stage3 scripts
FFXIV_PATH=$(readlink -f /proc/$FFXIV_PID/cwd)
FFXIV_ENV_FINAL="$FFXIV_ENV_FINAL"$'\n'"export FFXIV_PATH=\"$FFXIV_PATH\""

# Add proton path (same as wine path)
PROTON_PATH="$(echo "$FFXIV_ENV_FINAL" | grep 'export WINE=' | cut -d'=' -f2)"
PROTON_DIST_PATH="$(dirname "$(dirname "$PROTON_PATH")")"

WINEPREFIX="$(echo "$FFXIV_ENV_FINAL" | grep 'export WINEPREFIX=' | cut -d'=' -f2)"

if [[ "$(echo "$PROTON_PATH" | grep '\\ ')" != "" ]] || [[ "$(echo "$WINEPREFIX" | grep '\\ ')" != "" ]]; then
    error "There is a space in your Proton or Wine Prefix path."
    error "There's a known issue with spaces causing issues with the setup."
    error "Please remove spaces from the path(s) and try again."
    error "Proton distribution path detected: $PROTON_DIST_PATH"
    error "Proton path detected: $PROTON_PATH"
    error "Prefix path detected: $WINEPREFIX"
    error "Full environment detected:"
    error "$FFXIV_ENV_FINAL"
    exit 1
fi

# Check for wine already being setcap'd, fail if so
if [[ "$(getcap "$PROTON_PATH")" != "" ]]; then
    error "Detected that you're running this against an already configured Proton (the binary at path \"$PROTON_PATH\" has capabilities set already)"
    error "You must run this script against a fresh proton install, or else the LD_LIBRARY_PATH environment variable configured by your runtime cannot be detected"
    exit 1
fi

if [[ "$(echo "$FFXIV_ENV_FINAL" | grep 'export LD_LIBRARY_PATH=')" == "" ]]; then
    warn "Unable to determine runtime LD_LIBRARY_PATH."
    warn "This may indicate something strange with your setup."
    warn "Continuing is not advised unless you know how to fix any issues that may come up related to missing libraries."
    exit 1
fi

echo
success "Detected the following information about your setup. If any of this looks incorrect, please abort and report a bug to the Github repo..."

echo 
if [[ "$IS_STEAM" == "1" ]]; then
    echo "    Runtime Environment:          Steam"
else
    echo "    Runtime Environment:          Lutris"
fi
echo "    Wine Executable Location:     $PROTON_PATH"
echo "    Proton Distribution Path:     $PROTON_DIST_PATH"
echo "    Wine Prefix:                  $WINEPREFIX"
echo

PROMPT_CONTINUE

#
# Setup install directory
#

INSTALL_DIR_CONFIRMED="N"
INSTALL_DIR_DEFAULT="$HOME/bin"
INSTALL_DIR=$INSTALL_DIR_DEFAULT

# Prompt the user to provide an alternate installation path if desired
while [[ "$INSTALL_DIR_CONFIRMED" != "Y" ]] || [[ "$INSTALL_DIR_CONFIRMED" != "y" ]]; do

    read -p "Specify where to install ffxiv-tools [$INSTALL_DIR_DEFAULT]: " INSTALL_DIR
    [[ $INSTALL_DIR == "" ]] && INSTALL_DIR=$INSTALL_DIR_DEFAULT # Default if empty
    echo "The ffxiv-tools will be installed to: $INSTALL_DIR"

    PROMPT_CONFIRM
    if [[ $? == 0 ]]; then 
        break
    fi

done

echo "Creating destination directory at $INSTALL_DIR if it doesn't exist."
mkdir -p "$INSTALL_DIR"

#
# Install environment scripts
#

echo "Creating source-able environment script at $INSTALL_DIR/ffxiv-env-setup.sh"

cat << EOF > $INSTALL_DIR/ffxiv-env-setup.sh
#!/bin/bash
$FFXIV_ENV_FINAL
export WINEDEBUG=-all
export PROTON_PATH="$PROTON_PATH"
export PROTON_DIST_PATH="$PROTON_DIST_PATH"
export WINEPREFIX="$WINEPREFIX"
export IS_STEAM="$IS_STEAM"
export PATH="$PROTON_DIST_PATH/bin:\$PATH"
export FFXIV_TOOLS_PATH=$INSTALL_DIR
EOF

chmod +x $INSTALL_DIR/ffxiv-env-setup.sh

echo "Creating environment wrapper at $INSTALL_DIR/ffxiv-env.sh"

cat << EOF > $INSTALL_DIR/ffxiv-env.sh
#!/bin/bash
. $INSTALL_DIR/ffxiv-env-setup.sh
cd \$WINEPREFIX
/bin/bash
EOF

chmod +x $INSTALL_DIR/ffxiv-env.sh