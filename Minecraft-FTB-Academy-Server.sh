#!/usr/bin/env bash

# --- Static Settings ---
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
WARN="${YW}⚠${CL}"
INFO="${BL}ℹ${CL}"

# --- User-configurable settings ---
CT_ID="120"
CT_HOSTNAME="ftb-academy"
CT_PASSWORD="changeme" # Please change this!
CT_CORES="2"
CT_RAM="6144" # 4GB is a good minimum, use 6144 or 8192 for smoother play
CT_STORAGE="10G"
CT_BRIDGE="vmbr0"
CT_OS_TYPE="debian"
CT_OS_VERSION="12"
# URL for the FTB Server Pack files (Check FTB/CurseForge for the latest version if needed)
FTB_SERVER_URL="https://edge.forgecdn.net/files/4574/611/FTBAcademyServer-1.5.0.zip"

# --- Functions ---
function header_info {
  cat <<"EOF"
   ______ ____  ____      _    ____ ___ _   _    _    ____ _____
  |  ____|  _ \|  _ \    / \  / ___|_ _| \ | |  / \  / ___|_   _|
  | |_   | |_) | |_) |  / _ \| |    | ||  \| | / _ \| |     | |
  |  _|  |  _ <|  __/  / ___ \ |___ | || |\  |/ ___ \ |___  | |
  |_|    |_| \_\_|   /_/   \_\____|___|_| \_/_/   \_\____| |_|

  This script will create a new FTB Academy LXC Container.
EOF
}

function msg_info() {
  echo -e "${INFO} ${BL}$1${CL}"
}

function msg_ok() {
  echo -e "${CM} ${GN}$1${CL}"
}

function msg_warn() {
  echo -e "${WARN} ${YW}$1${CL}"
}

function msg_error() {
  echo -e "${CROSS} ${RD}$1${CL}"
}

function get_latest_storage() {
  local lxc_storage_list
  local latest_storage
  lxc_storage_list=$(pvesm status -content images | awk 'NR>1 {print $1}')
  latest_storage=$(echo "$lxc_storage_list" | tail -n 1)
  if [ -z "$latest_storage" ]; then
    msg_error "Unable to detect a suitable storage location for CT templates."
    exit 1
  fi
  CT_STORAGE_LOCATION="$latest_storage"
  msg_ok "Using '${CT_STORAGE_LOCATION}' for CT template storage."
}

function update_script() {
  msg_info "Updating LXC template list..."
  pveam update >/dev/null
  msg_ok "Finished updating LXC template list."

  msg_info "Downloading latest Debian 12 template..."
  pveam download "$CT_STORAGE_LOCATION" "${CT_OS_TYPE}-${CT_OS_VERSION}-standard" >/dev/null
  msg_ok "Finished downloading template."

  msg_info "Creating LXC Container..."
  pct create "$CT_ID" \
    "${CT_STORAGE_LOCATION}:vztmpl/${CT_OS_TYPE}-${CT_OS_VERSION}-standard_${CT_OS_VERSION}.0-1_amd64.tar.zst" \
    --hostname "$CT_HOSTNAME" \
    --password "$CT_PASSWORD" \
    --cores "$CT_CORES" \
    --memory "$CT_RAM" \
    --swap "$CT_RAM" \
    --rootfs "${CT_STORAGE_LOCATION}:${CT_STORAGE}" \
    --net0 name=eth0,bridge=${CT_BRIDGE},ip=dhcp \
    --onboot 1 \
    --start 1 \
    --features nesting=1 >/dev/null
  msg_ok "LXC Container ${CT_ID} created."

  msg_info "Waiting for container to start and get an IP..."
  sleep 5
  CT_IP=$(pct exec "$CT_ID" ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
  msg_ok "Container started successfully."

  msg_info "Updating container OS..."
  pct exec "$CT_ID" -- bash -c "apt-get update >/dev/null && apt-get -y upgrade >/dev/null"
  msg_ok "Container OS updated."

  msg_info "Installing dependencies (Java, wget, unzip)..."
  pct exec "$CT_ID" -- bash -c "apt-get install -y openjdk-17-jre-headless wget unzip >/dev/null"
  msg_ok "Dependencies installed."

  msg_info "Setting up Minecraft server environment..."
  pct exec "$CT_ID" -- bash -c "mkdir /opt/minecraft"
  pct exec "$CT_ID" -- bash -c "cd /opt/minecraft && wget -q '$FTB_SERVER_URL' -O server.zip && unzip -q server.zip && rm server.zip"
  msg_ok "Server files downloaded and extracted to /opt/minecraft."

  msg_info "Configuring server and accepting EULA..."
  pct exec "$CT_ID" -- bash -c "cd /opt/minecraft && echo 'eula=true' > eula.txt"
  # FTB packs use start.sh or ServerStart.sh
  pct exec "$CT_ID" -- bash -c "cd /opt/minecraft && chmod +x start.sh || chmod +x ServerStart.sh"
  msg_ok "EULA accepted and start script made executable."

  msg_info "Starting Minecraft Server to generate initial files..."
  pct exec "$CT_ID" -- bash -c "cd /opt/minecraft && ./start.sh" &
  # The server will start in the background. You can attach to the console later.
  
  echo -e "\n${BGN}Installation Complete!${CL}\n"
  echo -e "Your FTB Academy server is running in LXC Container ${GN}${CT_ID}${CL}."
  echo -e "Connect to it using the IP Address: ${GN}${CT_IP}${CL}\n"
  msg_warn "The server is starting for the first time in the background. This may take a few minutes."
  msg_warn "To manage the server, open the console for LXC ${CT_ID} in Proxmox and run:"
  echo -e "${DGN}cd /opt/minecraft && ./start.sh${CL}"
}

# --- Main execution ---
clear
header_info
echo -e "\n${INFO} Using the following settings:\n"
echo -e "  CT ID:          ${BL}${CT_ID}${CL}"
echo -e "  CT Hostname:    ${BL}${CT_HOSTNAME}${CL}"
echo -e "  CT Cores:       ${BL}${CT_CORES}${CL}"
echo -e "  CT RAM:         ${BL}${CT_RAM} MB${CL}"
echo -e "  CT Storage:     ${BL}${CT_STORAGE}${CL}"
echo -e "  Network Bridge: ${BL}${CT_BRIDGE}${CL}"
echo -e "\n"

read -p "Proceed with these settings? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  get_latest_storage
  update_script
else
  msg_error "Aborted by user."
  exit 0
fi
