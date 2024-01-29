#!/bin/sh
#
# Minstrel Configuration Tool for Kiosk Setup
#
# Author: Michael Czigler
# Version: 1.0.0
#
# This configuration tool is based on the 
# usage of Raspbian (Bookworm).
#

ASK_TO_REBOOT=0

calc_wt_size() {
  WT_HEIGHT=17
  WT_WIDTH=$(tput cols)
  if [ -z "$WT_WIDTH" ] || [ "$WT_WIDTH" -lt 60 ]; then
    WT_WIDTH=80
  fi
  if [ "$WT_WIDTH" -gt 178 ]; then
    WT_WIDTH=120
  fi
  WT_MENU_HEIGHT=$(($WT_HEIGHT-7))
}

do_finish() {
  if [ $ASK_TO_REBOOT -eq 1 ]; then
    whiptail --yesno "Would you like to reboot now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
      sync
      reboot
    fi
  fi
  exit 0
}

do_install_requirements() {
  apt update && apt install -y podman snapd
  ASK_TO_REBOOT=1
}

do_setup_container() {
  podman stop minstrel
  podman rm minstrel
  #podman pull ghcr.io/mcpcpc/minstrel:latest
  git clone http://github.com/mcpcpc/minstrel
  buildah bud -t minstrel minstrel/
  podman run -dt -p 8080:8080 \
    --name minstrel \
    --volume /home/prod/:/usr/local/var/minstrel-instance \
    minstrel
}

do_setup_service() {
  rm /home/prod/*.service
  podman generate systemd --new --files --name minstrel
  mkdir -p /home/prod/.config/systemd/user
  cp *.service /home/prod/.config/systemd/user
  systemctl --user daemon-reload
  systemctl --user start container-minstrel.service
  systemctl --user enable container-minstrel.service
  loginctl enable-linger prod
}

do_kiosk_mode() {
  snap install core
  snap install ubuntu-frame
  snap install ubuntu-frame-osk
  snap install wpe-webkit-mir-kiosk
  snap connect wpe-webkit-mir-kiosk:wayland
  snap set wpe-webkit-mir-kiosk url=http://127.0.0.1:8080
  snap start wpe-webkit-mir-kiosk
  snap set ubuntu-frame-osk daemon=true
  snap set wpe-webkit-mir-kiosk daemon=true
  snap set ubuntu-frame daemon=true
}

if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root. Try 'sudo minstrel-config'\n"
  exit 1 
fi

calc_wt_size
while true; do
  FUN=$(whiptail --title "Minstrel Configuration Tool (minstrel-config)" --menu "Setup Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Finish --ok-button Select \
    "1 Install Dependencies" "Ensure all dependencies are installed" \
    "2 Setup Container" "Install and configure the Minstrel container" \
    "3 Setup Service" "Setup and start service" \
    "4 Setup Kiosk" "Configure Kiosk mode and keyboard" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    do_finish
  elif [ $RET -eq 0 ]; then
    case "$FUN" in
      1\ *) do_install_requirements ;;
      2\ *) do_setup_container ;;
      3\ *) do_setup_service ;;
      4\ *) do_kiosk_mode ;;
      *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
    esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
  else
    exit 1
  fi
done
