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

if [ "root" != "$USER" ]; then
  echo "Enter su"
  su -c "$0" root
  exit
fi

echo "select the /root disk. this disk will be mount to /mnt and will chroot it"
select disk in "$(fdisk -l | awk '/^\/dev/ {print $1}')"; do break;done 
echo "$disk"
e2fsck -f "$disk"
set -e

mount /dev/"$disk" /mnt
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

slackpkg update gpg
slackpkg update
slackpkg upgrade aaa_glibc-solibs
slackpkg install-new 
slackpkg upgrade-all

echo "You may need to update your bootloader"
echo "lilo,elilo,Grub..."

