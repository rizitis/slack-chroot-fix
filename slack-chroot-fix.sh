#!/bin/bash

# Running this script from a live-slack.iso as root, it
# chrooting a broken Slackware current system and try to fix it. 

# BE CAREFULLY NOT RUN THIS SCRIPT IN A WORKING SYSTEM IF YOU DONT UNDERSTAND IT.
# IT WILL DESTROY YOUR SYSTEM...FOR EVER.
# 
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
#  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO
#  EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
#  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
#  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
#  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

mkdir -p /mnt/var/log/ || { echo "Error: Failed to create log directory. Exiting."; exit 1; }
exec > >(tee -a "/mnt/var/log/chroot_rescue_log.txt") 2>&1

if [ "root" != "$USER" ]; then
  echo "Enter su"
  su -c "$0" root
  exit
fi

flash_text() {
  local text="$1"
  while true; do
    echo -e "\033[5m$text\033[0m" # \033[5m and \033[0m are escape codes for blinking and reset
    sleep 0.5
    clear
    sleep 0.5
  done
}


flash_text "BE CAREFUL! DO NOT RUN THIS SCRIPT ON A WORKING SYSTEM IF YOU DON'T UNDERSTAND IT. IT MAY DESTROY YOUR SYSTEM PERMANENTLY." &

read -p "If you understand the risks and want to proceed, type 'yes' and press Enter: " confirmation

if [[ "$confirmation" != "yes" ]]; then
  echo "Aborted. Script not executed."
  pkill -f "flash_text"
  exit 1
fi

echo "select the /root disk. this disk will be mount to /mnt and will be chrooted"
select disk in "$(fdisk -l | awk '/^\/dev/ {print $1}')"; do break;done 
echo "$disk"
e2fsck -f "$disk"
set -e

mount "$disk" /mnt

if ! mount "$disk" /mnt; then
  echo "Error: Failed to mount $disk. Exiting."
  exit 1
fi

mount --bind /dev /mnt/dev
mount --bind /tmp /mnt/tmp
mount --bind /run /mnt/run
mount -t proc proc /mnt/proc
mount -t sysfs none /mnt/sys
mount -t devpts -o noexec,nosuid,gid=tty,mode=0620 devpts /mnt/dev/pts

efi="$(lsblk -o MOUNTPOINT | grep -q '/boot/efi' && echo "Yes" || echo "No")"
echo "$efi"
if [ "$efi" = "Yes" ]; then
mount --bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars
else
echo "No UEFI system"
fi

chroot /mnt /bin/bash

if [ $? -eq 0 ]; then
  echo "Chroot into /mnt was successful."
else
  echo "Error: Chroot into /mnt failed."
  exit 1
fi

read -p "Do you want to proceed with manual intervention? (y/n): " answer
if [[ "$answer" != [Yy]* ]]; then
  echo "Exiting script."
  exit 1
fi

manual_intervention() {
  echo "Proceeding with manual intervention..."
  
  echo "You are now in the chroot environment. Please perform the following tasks:"
  echo "1. Inspect and modify necessary files."
  echo "2. Execute custom commands."
  echo "3. Troubleshoot and fix issues."
}

while true; do
  read -p "You are now in the chroot environment. Do you want to continue manually? (y/n): " response
  case "$response" in
    [Yy]* ) manual_intervention ;;
    [Nn]* ) 
      echo "Exiting manual intervention. Resuming script..."
      break ;;  # Exit the loop and continue with the rest of the script
    * ) echo "Please answer yes (y) or no (n)." ;;
  esac
done

arch="$(lscpu | grep Architecture | awk '{print $2}')"
echo "$arch"

if [ "$arch" =  x86_64 ]; then
echo "http://slackware.uk/slackware/slackware64-current/" > /etc/slackpkg/mirrors
elif 
[ "$arch" = i686 ]; then
echo "http://slackware.uk/slackware/slackware-current/" > /etc/slackpkg/mirrors
else
echo "unkown arch...do it yourself"
exit
fi

check_internet() {
  if ping -q -c 1 -W 1 google.com >/dev/null; then
    echo "Internet connection is up."
    return 0  # Success
  else
    echo "Error: No internet connection."
    return 1  # Failure
  fi
}

start_network() {
  echo "Attempting to start the network with dhclient..."

  echo "Available network interfaces:"
  select network_interface in $(ls /sys/class/net); do
    break
  done

  read -p "Enter client identifier (press Enter if none): " client_identifier

  if dhclient -C "$client_identifier" "$network_interface"; then
    echo "dhclient succeeded. Network started."
    return 0  # Success
  else
    echo "Error: dhclient failed. Unable to start the network."
    return 1  # Failure
  fi
}


if ! check_internet; then
  if start_network; then
    echo "Network started successfully."
  else
    echo "Failed to start the network. Exiting."
    cleanup_and_exit
  fi
fi

read -p "Do you want to proceed with system upgrades? (y/n): " answer
if [[ "$answer" != [Yy]* ]]; then
  echo "Aborting."
  cleanup_and_exit
fi

slackpkg update gpg
slackpkg update
slackpkg upgrade aaa_glibc-solibs
slackpkg install-new 
slackpkg upgrade-all

echo "You may need to update your bootloader"
echo "lilo,elilo,Grub..."

choose_bootloader_command() {
  echo "Choose bootloader update command:"
  echo "1. lilo"
  echo "2. elilo"
  echo "3. grub"
  echo "4. Custom Command"
  echo "5. No, keep going"

  read -p "Enter the number corresponding to your choice: " bootloader_choice

  case "$bootloader_choice" in
    1) update_lilo ;;
    2) update_eliloconfig ;;
    3) update_grub ;;
    4) custom_command ;;
    5) echo "Continuing without updating the bootloader." ;;
    *) echo "Invalid choice. Please enter a number from 1 to 5." ;;
  esac
}

update_lilo() {
  echo "Updating lilo..."
  lilo
}

update_eliloconfig() {
  echo "Updating eliloconfig..."
  eliloconfig 
}

update_grub() {
  echo "Updating grub-mkconfig..."
  grub-mkconfig -o /boot/grub/grub.cfg
}

custom_command() {
  read -p "Enter custom command: " user_custom_command
  echo "Executing custom command: $user_custom_command"
  eval "$user_custom_command"
}

choose_bootloader_command

cleanup_and_exit() {
  umount /mnt/dev/pts
  umount /mnt/dev
  umount /mnt/tmp
  umount /mnt/run
  umount /mnt/proc
  umount /mnt/sys
  umount /mnt

  
  exit
}

cleanup_and_exit
