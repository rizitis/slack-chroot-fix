#!/bin/bash

# running this script from a live-slack.iso as root, it
# chrooting a broken Slackware current system and try to fix it. 

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

mkdir -p /mnt/var/log/ || exit 1
exec > >(tee -a "/mnt/var/log/chroot_rescue_log.txt") 2>&1

if [ "root" != "$USER" ]; then
  echo "Enter su"
  su -c "$0" root
  exit
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
    exit 1
  fi
fi

read -p "Do you want to proceed with system upgrades? (y/n): " answer
if [[ "$answer" != [Yy]* ]]; then
  echo "Aborting."
  exit 0
fi

slackpkg update gpg
slackpkg update
slackpkg upgrade aaa_glibc-solibs
slackpkg install-new 
slackpkg upgrade-all

exit
umount /mnt/dev/pts
umount /mnt/dev
umount /mnt/tmp
umount /mnt/run
umount /mnt/proc
umount /mnt/sys
umount /mnt


echo "You may need to update your bootloader"
echo "lilo,elilo,Grub..."

