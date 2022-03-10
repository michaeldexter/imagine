#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2022 Michael Dexter
# All rights reserved
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted providing that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# Version v0
# VARIABLES - NOTE THE VERSIONED ONES

password="freebsd"
wifi_ssid="my_wifi_ap"
wifi_pass="my_wifi_password"
subnet="10.0.0"
work_dir="/root/imagine-work"
bits_dir="/lab/imagine-bits"
packages="tmux rsync smartmontools smart fio git-lite iperf3"
md_id="md43"

release_img_url="https://download.freebsd.org/ftp/releases/VM-IMAGES/13.0-RELEASE/amd64/Latest/FreeBSD-13.0-RELEASE-amd64.raw.xz"

release_src_url="https://download.freebsd.org/ftp/releases/amd64/13.0-RELEASE/src.txz"

current_img_url="https://download.freebsd.org/ftp/snapshots/VM-IMAGES/14.0-CURRENT/amd64/Latest/FreeBSD-14.0-CURRENT-amd64.raw.xz"

current_src_url="https://download.freebsd.org/ftp/snapshots/amd64/amd64/14.0-CURRENT/src.txz"

[ -f ./lib_xenomorph.sh ] || \
	{ echo lib_xenomorph.sh missing ; exit 1 ; }
. ./lib_xenomorph.sh || \
	{ echo lib_xenomorph.sh failed to source ; exit 1 ; }

[ -d "$work_dir" ] || mkdir -p $work_dir

echo ; echo What version would you like to download? \(release\)/\(current\)
read version

if [ "$version" = "release" ] ; then
	img_url="$release_img_url"
	src_url="$release_src_url"

elif [ "$version" = "current" ] ; then

	img_url="$current_img_url"
	src_url="$current_src_url"
else
	echo Invalid input
	exit 1
fi

src_dir="$work_dir/$version"

[ -d "$src_dir" ] || mkdir -p $src_dir

xzimg="$( basename "$img_url" )"
img="${xzimg%.xz}"

echo Unmouting /media
# THIS TEST IS NOT RELIABLE
mount | grep "/media" && umount -f /media #|| \
#	{ echo /media failed to unmount ; exit 1 ; }

# FOR WANT OF A RELIABLE TEST
umount -f /media
mdconfig -du "$md_id" > /dev/null 2>&1
mdconfig -du "$md_id" > /dev/null 2>&1

echo Removing previous VM image if present
[ -f $work_dir/$version/$img ] && rm $work_dir/$version/$img

if [ -f $work_dir/$version/$xzimg ] ; then
	echo $xzimg exists. Download fresh? \(y/n\) ; read fresh
	if [ "$fresh" = "y" ] ; then
		rm $work_dir/$version/$xzimg
		echo ; echo Feching $img from $img_url
		# NOT WORKING
		#fetch -qo - $img_url | tar -xf -
		cd $work_dir/$version

		#fetch -i $img_url
		# Does -i require the file to exist, else fails?
		fetch $img_url
		echo ; echo Uncompressing $xzimg
		unxz --keep $xzimg
	else
		cd $work_dir/$version
		echo ; echo Uncompressing $xzimg
		unxz --keep $xzimg
	fi
else
	cd $work_dir/$version
	fetch $img_url
	echo ; echo Uncompressing $xzimg
	unxz --keep $xzimg
fi

file -s $work_dir/$version/$img | grep "boot sector" || \
	{ echo $work_dir/$version/$img not a disk image? ; exit 1 ; }

echo ; echo Attaching $work_dir/$version/$img
mdconfig -a -u "$md_id" -f $work_dir/$version/$img
mdconfig -lv

echo ; echo Mounting $md_id to /media

mount /dev/${md_id}p4 /media || { echo mount failed ; exit 1 ; }


# UNIVERSAL SETTINGS

# Optionally read the rc.conf prior to modification
#sysrc -a -R /media
#cat /media/etc/rc.conf

echo ; echo Changing hostname to $version
sysrc -R /media hostname="$version"

echo ; echo Enabling SSHd 
sysrc -R /media sshd_enable=YES

echo ; echo Copying in .ssh from this host
cp -rp $bits_dir/.ssh /media/root/

echo ; echo Enabling NTPd
sysrc -R /media ntpdate_enable=YES
sysrc -R /media ntpd_enable=YES

echo ; echo Setting dumpdev
sysrc -R /media dumpdev=AUTO

echo ; echo Setting rc_debug
sysrc -R /media rc_debug=YES

echo ; echo Setting verbose_loading and boot_verbose
sysrc -f /media/boot/loader.conf verbose_loading="YES"
sysrc -f /media/boot/loader.conf boot_verbose="YES"

echo ; echo Shortening autoboot_delay
sysrc -f /media/boot/loader.conf autoboot_delay=5


# NETWORKING SETTINGS

echo ; echo Enter \(wifi/fixed\) or nothing for DHPC
read net

case $net in
#	# Default behavior of the VM images and thus nothing to do
#	dhcp)
#		sysrc -R /media ifconfig_DEFAULT="DHCP"
#	;;
	wifi)
		echo Removing ifconfig_DEFAULT
		sysrc -x -R /media ifconfig_DEFAULT
		sysrc -R /media wlans_iwn0="wlan0"
		sysrc -R /media ifconfig_wlan0="WPA DHCP"
		sysrc -R /media create_args_wlan0="country US regdomain FCC"

		echo ; echo Generating wpa_supplicant.conf
		cat > /media/etc/wpa_supplicant.conf <<EOF
ctrl_interface=/var/run/wpa_supplicant
eapol_version=2
ap_scan=1
fast_reauth=1

network={
        ssid="$wifi_ssid"
        scan_ssid=0
        psk="$wifi_pass"
        priority=5
}
EOF
	;;
	fixed)
		echo ; echo What last digits of the IP i.e. 20 ?
		read ip

		echo ; echo Setting default router
		sysrc -R /media defaultrouter="$subnet.1"

		echo ; echo Setting fixed IP to $subnet.$ip
		sysrc -R /media ifconfig_DEFAULT="$subnet.$ip/24"

		echo ; echo Setting the nameserver
		# sysrc does not support this
		echo "search localdomain" > /media/etc/resolv.conf
		echo "nameserver $subnet.1" >> /media/etc/resolv.conf
	;;
esac

echo ; echo Setting root password with pw
#pw -R /media/
echo "$password" | pw -R /media/ usermod -n root -h 0

echo ; echo Enable serial port? \(y/n\) ; read serial
if [ "$serial" = "y" ] ; then
	echo Configurating /boot.config and /boot/loader.conf for serial output
	# sysrc does not support this

# sysrc does not support this and attempting idempotence
if [ -f /media/boot.config ] ; then
	grep S115200 /media/boot.config || \
		printf "%s" "-D -h -S115200 -v" >> /media/boot.config
else
	printf "%s" "-h -S115200 -v" > /media/boot.config
fi

	sysrc -f /media/boot/loader.conf boot_multicons="YES"
	sysrc -f /media/boot/loader.conf boot_serial="YES"
	sysrc -f /media/boot/loader.conf comconsole_speed="115200"

	echo ; echo Will the target system boot UEFI? \(y/n\) ; read uefi
	if [ "$uefi" = "y" ] ; then
		sysrc -f /media/boot/loader.conf console="comconsole,efi"
	else
		sysrc -f /media/boot/loader.conf console="comconsole,vidconsole"
	fi
fi

echo ; echo Enabling PermitRootLogin yes
sed -i '' -e "s/#PermitRootLogin no/PermitRootLogin yes/" \
	/media/etc/ssh/sshd_config

echo ; echo Searching for PermitRootLogin in sshd_config
grep PermitRootLogin /media/etc/ssh/sshd_config


# REMOVE AND ADD ENTRIES TO MEET YOUR NEEDS

echo ; echo Copying in .ssh directory if present
[ -d "$bits_dir/.ssh" ] && cp -rp $bits_dir/.ssh /media/root/

# Everyone has one of these
echo ; echo Copying in labnfs.sh if present
[ -f "$bits_dir/labnfs.sh" ] && cp -p $bits_dir/labnfs.sh /media/root/


# PACKAGES

echo ; echo Installing Packages
# Yes, pkg checks for different OS versions!
# But, the arguments must be in this precise order to work
pkg -r /media install -y $packages

echo ; echo Reviewing boot.config loader.conf rc.conf resolv.conf

# Note that the boot.config serial entry does not have a line feed
echo ; cat /media/boot.config
cat /media/boot/loader.conf
echo ; cat /media/etc/sysctl.conf
echo ; cat /media/etc/rc.conf
echo ; cat /media/etc/resolv.conf

echo ; echo About to unmount /media.
echo  Make any final changes now and press Enter when finished ; read lastchance

echo ; echo Unmounting /media
umount /media || { echo umount failed ; exit 1 ; }

echo ; echo Destroying $md_id
mdconfig -du $md_id || { echo $md_id destroy failed ; mdconfig -lv ; exit 1 ; }

echo ; echo dd the configured VM image to a hardware device? \(y/n\) ; read dd 
[ "$dd" = "y" ] || exit 0

echo ; echo The availble hardware devices are:

sysctl kern.disks

echo ; echo What device would you like to dd the VM image to?
read device

echo ; echo diskinfo -v for $device reads
diskinfo -v $device

echo ; echo WARNING! About to write $img to $device! ; echo
echo ; echo Continue? \(y/n\) ; read warning
[ "$warning" = "y" ] || exit 0

\time -h dd if=$img of=/dev/$device bs=1m conv=sync || \
	{ echo dd operation failed ; exit 1 ; }

echo ; echo Recovering $device partitioning
gpart recover $device

echo ; echo Resizing ${device}p4
gpart resize -i 4 $device
echo ; echo Growing /dev/${device}p4
growfs /dev/${device}p4

echo ; echo Install /usr/src? \(y/n\) ; read src
if [ "$src" = "y" ] ; then

	if [ -f $work_dir/$version/src.txz ] ; then
		echo $work_dir/$version/src.txz exists. Fetch fresh? \(y/n\)
		read freshsrc
		if [ "$freshsrc" = "y" ] ; then
			cd $work_dir/$version/
			rm src.txz
			echo Fetching $src_url
			fetch $src_url
		fi
	else
		cd $work_dir/$version/
		echo Fetching $src_url
		fetch $src_url
	fi

	echo ; echo Mounting /dev/${device}p4 on /media
	mount /dev/${device}p4 /media || \
		{ echo /dev/${device}p4 failed to mount ; exit 1 ; }

	echo ; echo Extracting src.txz to /media
	cat src.txz | tar -xf - -C /media/

	echo ; echo Listing /media/usr/src ; ls /media/usr/src
fi

echo ; echo Configure system as a Xen Dom0? \(y/n\) ; read xen
if [ "$xen" = "y" ] ; then

	echo ; echo How much Dom0 RAM? i.e. 2048, 4096, 8192, or 16384...
	read dom0_mem

	echo ; echo How many Dom0 CPUs? i.e. 2, 4, 8, or 16...
	read dom0_cpus

	if [ "$uefi" = "y" ] ; then
		uefi_string="-e"
	fi

	if [ "$serial" = "y" ] ; then
		serial_string="-s"
	fi

	xenomorph -r /media -m $dom0_mem -c $dom0_cpus $uefi_string $serial_string || \
		{ echo xenomorph failed ; exit 1 ; }
fi

echo ; echo This is your last chance to modify the VM image mounted on /media
echo ; echo Unmount the configured image? \(y/n\) ; read bye
[ "$bye" = "y" ] || exit 0

echo ; echo Unmounting /media
umount /media

echo ; echo Have a nice day!
exit 0
