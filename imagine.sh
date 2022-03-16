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

# Version v0.8
# VARIABLES - NOTE THE VERSIONED ONES

password="freebsd"
wifi_ssid="my_wifi_ap"
wifi_pass="my_wifi_password"
subnet="10.0.0"
work_dir="/root/imagine-work"
bits_dir="/lab/imagine-bits"
package_list="tmux rsync smartmontools smart fio git-lite iperf3 xen-guest-tools open-vm-tools-nox11"
md_id="md43"

release_img_url="https://download.freebsd.org/ftp/releases/VM-IMAGES/13.0-RELEASE/amd64/Latest/FreeBSD-13.0-RELEASE-amd64.raw.xz"

release_dist_url="https://download.freebsd.org/ftp/releases/amd64/13.0-RELEASE"

current_img_url="https://download.freebsd.org/ftp/snapshots/VM-IMAGES/14.0-CURRENT/amd64/Latest/FreeBSD-14.0-CURRENT-amd64.raw.xz"

current_dist_url="https://download.freebsd.org/ftp/snapshots/amd64/amd64/14.0-CURRENT"

[ -f ./lib_xenomorph.sh ] || \
	{ echo lib_xenomorph.sh missing ; exit 1 ; }
. ./lib_xenomorph.sh || \
	{ echo lib_xenomorph.sh failed to source ; exit 1 ; }

[ -d "$work_dir" ] || mkdir -p "$work_dir"

echo ; echo What version of FreeBSD would you like to configure?
echo -n "(release/current): " ; read version

if [ "$version" = "release" ] ; then
	img_url="$release_img_url"
	dist_url="$release_dist_url"

elif [ "$version" = "current" ] ; then

	img_url="$current_img_url"
	dist_url="$current_dist_url"
else
	echo Invalid input
	exit 1
fi

src_dir="$work_dir/$version"

[ -d "$src_dir" ] || mkdir -p "$src_dir"

xzimg="$( basename "$img_url" )"
img="${xzimg%.xz}"
img_base="${img%.raw}"

if [ -f "$work_dir/$version/$xzimg" ] ; then
	echo ; echo $xzimg exists. Fetch fresh?
echo -n "(y/n): " ; read freshimg
	if [ "$freshimg" = "y" ] ; then
		rm "$work_dir/$version/$xzimg"
		echo ; echo Feching $img from $img_url
		# NOT WORKING
		#fetch -qo - $img_url | tar -xf -
		cd "$work_dir/$version"

		#fetch -i "$img_url"
		# Does -i require the file to exist, else fails?
		fetch "$img_url"
	else
		cd "$work_dir/$version"
	fi
else
	cd "$work_dir/$version"
	fetch "$img_url"
fi

# Useful while testing, strongly discouraged for use
#if [ -f "$work_dir/$version/$img" ] ; then
#	echo ; echo $img exists. Reuse uncompressed image?
#	echo This is strongly discouraged if partially configured!
#echo -n "(y/n): " ; read reuse
#	if ! [ "$reuse" = "y" ] ; then

		echo Removing previous VM image if present
		[ -f "$work_dir/$version/$img" ] && rm "$work_dir/$version/$img"
		[ -f "$work_dir/$version/${img}.gz" ] && \
			rm "$work_dir/$version/${img}.gz"
		[ -f "$work_dir/$version/${img_base}-flat.vmdk" ] && \
			rm "$work_dir/$version/${img_base}-flat.vmdk"
		[ -f "$work_dir/$version/${img_base}-flat.vmdk.gz" ] && \
			rm "$work_dir/$version/${img_base}-flat.vmdk.gz"

		cd "$work_dir/$version"
		echo ; echo Uncompressing "$xzimg"
		\time -h unxz --verbose --keep "$xzimg"
#	fi
#fi


# IMAGE SMOKE TEST

file -s "$work_dir/$version/$img" | grep "boot sector" || \
	{ echo $work_dir/$version/$img not a disk image? ; exit 1 ; }


# PRIMITIVE CLEAN UP

echo Unmouting /media
# THIS TEST IS NOT RELIABLE - make a better one
#mount | grep "/media" && umount -f /media || \
#	{ echo /media failed to unmount ; exit 1 ; }

# FOR WANT OF A RELIABLE TEST
umount -f /media > /dev/null 2>&1
mdconfig -du "$md_id" > /dev/null 2>&1
mdconfig -du "$md_id" > /dev/null 2>&1


# OPTIONAL RESIZE

echo ; echo Grow the image from from the default of 5GB?
echo -n "(y/n): " ; read grow
if [ "$grow" = "y" ] ; then
	echo ; echo Grow to how many GB? i.e. 10G
	echo Consider 8G for sources and use as a Xen Dom0
	# Would be nice to valildate this input
	echo -n "New image size: " ; read newsize
	truncate -s "$newsize" "$work_dir/$version/$img" ||
		{ echo image truncate failed. Invalid size? ; exit 1 ; }
fi

echo ; echo Attaching $work_dir/$version/$img
mdconfig -a -u "$md_id" -f "$work_dir/$version/$img"
mdconfig -lv

if [ "$grow" = "y" ] ; then
	echo ; echo Recovering $md_id partitioning
	gpart recover "$md_id" || \
		{ echo gpart recovery failed ; exit 1 ; }

	echo ; echo Resizing ${md_id}p4
	gpart resize -i 4 "$md_id" || \
		{ echo gpart resize failed ; exit 1 ; }

	echo ; echo Growing /dev/${md_id}p4
	growfs -y "/dev/${md_id}p4" || \
		{ echo growfs failed ; exit 1 ; }
fi

echo ; echo Mounting ${md_id}p4 to /media
mount "/dev/${md_id}p4" /media || { echo mount failed ; exit 1 ; }

gpart show "/dev/$md_id"
df -h |grep media


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

echo ; echo Touching /firstboot
touch /media/firstboot


# NETWORKING

echo ; echo Networking type:
echo -n "(dhcp/wifi/fixed): " ; read net

case $net in
	# Default behavior of the VM images and thus nothing to do
	dhcp)
		# This is the fault
		true
	;;
	wifi)
		echo Removing ifconfig_DEFAULT
		sysrc -x -R /media ifconfig_DEFAULT
		sysrc -R /media wlans_iwn0="wlan0"
		sysrc -R /media ifconfig_wlan0="WPA DHCP"
		sysrc -R /media create_args_wlan0="country US regdomain FCC"

		echo ; echo Generating wpa_supplicant.conf
		cat << EOF > /media/etc/wpa_supplicant.conf
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
		# Phrase this better
		echo ; echo What last digits of the IP? i.e. 20 ?
		echo -n "(IP address ending): " ; read ip

		echo ; echo What interface? i.e. em0, igb0 ?
		echo -n "(Network inteface): " ; read nic

		echo ; echo Setting default router
		sysrc -R /media defaultrouter="$subnet.1"

		echo ; echo Removing ifconfig_DEFAULT
		sysrc -x -R /media ifconfig_DEFAULT

		echo ; echo Setting fixed IP to $subnet.$ip
		sysrc -R /media ifconfig_${nic}="inet $subnet.${ip}/24"

		echo ; echo Setting the nameserver
		# sysrc does not support this
		echo "search localdomain" > /media/etc/resolv.conf
		echo "nameserver $subnet.1" >> /media/etc/resolv.conf
	;;
esac


# ROOT PASSWORD

echo ; echo Setting root password with pw
#pw -R /media/
echo "$password" | pw -R /media/ usermod -n root -h 0


# SERIAL OUTPUT

echo ; echo Enable serial port?
echo -n "(y/n): " ; read serial
if [ "$serial" = "y" ] ; then
	echo Configurating /boot.config and /boot/loader.conf for serial output

	# sysrc does not support this and attempting idempotence
	if [ -f /media/boot.config ] ; then
		grep S115200 /media/boot.config || \
			echo "-S115200 -v" >> /media/boot.config
			#printf "%s" "-S115200 -v" >> /media/boot.config
	else
		#printf "%s" "-S115200 -v" > /media/boot.config
		echo "-S115200 -v" > /media/boot.config
	fi

	sysrc -f /media/boot/loader.conf boot_multicons="YES"
	sysrc -f /media/boot/loader.conf boot_serial="YES"
	sysrc -f /media/boot/loader.conf comconsole_speed="115200"

	echo ; echo Will the target system boot UEFI?
	echo -n "(y/n): " ; read uefi
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


# LOCAL CUSTOMIZATION - ADJUST TO SUIT

echo ; echo Copying in .ssh directory if present
[ -d "$bits_dir/.ssh" ] && cp -rp $bits_dir/.ssh /media/root/

# Everyone has one of these
echo ; echo Copying in labnfs.sh if present
[ -f "$bits_dir/labnfs.sh" ] && cp -p $bits_dir/labnfs.sh /media/root/


# PACKAGES

echo ; echo Install packages?
echo -n "(y/n): " ; read packages
if [ "$packages" = "y" ] ; then
	echo ; echo Installing Packages
	# Yes, pkg checks for different OS versions!
	# But, the arguments must be in this precise order to work
	pkg -r /media install -y $package_list
fi

# OPTIONAL DISTRIBUTION SETS

echo ; echo Install distribution sets to /usr/freebsd-dist ?
echo -n "(y/n): " ; read dist
if [ "$dist" = "y" ] ; then

	if ! [ "$grow" = "y" ] ; then
		echo ; echo WARNING! It appers that you did not grow the image!
		echo dist set installation will likely fail. Continue?
		echo -n "(y/n): " ; read ungrown
		[ "$ungrown" = "y" ] || exit 1
	fi

	if [ -f $work_dir/$version/freebsd-dist/base.txz ] ; then
		echo base.txz found. Fetch all fresh?
		echo -n "(y/n): " ; read freshdist
		srcisfresh=0
		if [ "$freshdist" = "y" ] ; then
			cd $work_dir/$version/freebsd-dist/
			rm *.txz
			echo Fetching distributions sets
			fetch $dist_url/MANIFEST
			fetch $dist_url/base-dbg.txz
			fetch $dist_url/base.txz
			fetch $dist_url/kernel-dbg.txz
			fetch $dist_url/kernel.txz
			fetch $dist_url/lib32-dbg.txz
			fetch $dist_url/lib32.txz
			fetch $dist_url/ports.txz
			fetch $dist_url/src.txz
			fetch $dist_url/tests.txz
			srcisfresh=1
		fi
	else
		[ -d $work_dir/$version/freebsd-dist/ ] || \
			mkdir -p [ -f $work_dir/$version/freebsd-dist
		cd $work_dir/$version/freebsd-dist/
		echo Fetching distributions sets
		fetch $dist_url/MANIFEST
		fetch $dist_url/base-dbg.txz
		fetch $dist_url/base.txz
		fetch $dist_url/kernel-dbg.txz
		fetch $dist_url/kernel.txz
		fetch $dist_url/lib32-dgb.txz
		fetch $dist_url/lib32.txz
		fetch $dist_url/ports.txz
		fetch $dist_url/src.txz
		fetch $dist_url/tests.txz
		srcisfresh=1
	fi

	echo Copying distributions sets
	cp -rp $work_dir/$version/freebsd-dist /media/usr/
fi


# OPTIONAL SOURCES

echo ; echo Install /usr/src?
echo -n "(y/n): " ; read src
if [ "$src" = "y" ] ; then

	if ! [ "$grow" = "y" ] ; then
		echo ; echo WARNING! It appers that you did not grow the image!
		echo src installation will likely fail. Continue?
		echo -n "(y/n): " ; read ungrown
		[ "$ungrown" = "y" ] || exit 1
	fi

	if [ -f "$work_dir/$version/freebsd-dist/src.txz" ] ; then
		if ! [ "$srcisfresh" = 1 ] ; then
			echo src.txz exists. Fetch fresh?
			echo -n "(y/n): " ; read freshsrc
			if [ "$freshsrc" = "y" ] ; then
				cd $work_dir/$version/freebsd-dist/
				rm src.txz
				echo Fetching $dist_url/src.txz
				fetch $dist_url/src.txz
			fi
		fi
	else
		cd $work_dir/$version/freebsd-dist
		echo Fetching $dist_url/src.txz
		fetch $dist_url/src.txz
	fi

	cd $work_dir/$version/freebsd-dist/
	echo ; echo Extracting src.txz to /media
	cat src.txz | tar -xf - -C /media/

	echo ; echo Listing /media/usr/src ; ls /media/usr/src
fi


# OPTIONAL XEN DOMU SUPPORT

echo
echo Generate Xen DomU VM guest configuration file and boot script?
echo -n "(y/n): " ; read domu
if [ "$domu" = "y" ] ; then

echo ; echo Generating xen.cfg
cat << HERE > $work_dir/$version/xen.cfg
type = "hvm"
memory = 2048
vcpus = 2
name = "$version"
disk = [ '$work_dir/$version/$img,raw,hda,w' ]
boot = "c"
serial = 'pty'
on_poweroff = 'destroy'
on_reboot = 'restart'
on_crash = 'restart'
#vif = [ 'bridge=bridge0' ]
HERE

	echo "xl list | grep $version && xl destroy $version " \
		> $work_dir/$version/boot-xen.sh
	echo "xl create -c $work_dir/$version/xen.cfg" \
		>> $work_dir/$version/boot-xen.sh
	echo You can boot the VM with $work_dir/$version/boot-xen.sh

	echo "xl shutdown $version ; xl destroy $version ; xl list" > \
		$work_dir/$version/destroy-xen.sh
	echo Also note $work_dir/$version/destroy-xen.sh
fi


# OPTIONAL XEN DOM0 SUPPORT

# This will perform a second package installation but that is probably
# preferable to something like a $xen_packages string in the original

echo ; echo Configure system as a Xen Dom0?
echo -n "(y/n): " ; read dom0
if [ "$dom0" = "y" ] ; then

	if ! [ "$grow" = "y" ] ; then
		echo ; echo WARNING! It appers that you did not grow the image!
		echo Xen installation will likely fail. Continue?
		echo -n "(y/n): " ; read ungrown
		[ "$ungrown" = "y" ] || exit 1
	fi

	echo ; echo How much Dom0 RAM? i.e. 4096, 8g, 16g
	echo -n "(Dom0 RAM): " ; read dom0_mem

	echo ; echo How many Dom0 CPUs? i.e. 2, 4, 8
	echo -n "(Dom0 CPUs): " ; read dom0_cpus

# Parameter for lib_xenomorph
	if [ "$uefi" = "y" ] ; then
		uefi_flag="-e"
	fi

# Parameter for lib_xenomorph
	if [ "$serial" = "y" ] ; then
		serial_flag="-s"
	fi

	xenomorph -r /media -m $dom0_mem -c $dom0_cpus \
		$uefi_flag $serial_flag || \
			{ echo xenomorph failed ; exit 1 ; }
fi


# FINAL REVIEW

echo ; echo Reviewing boot.config loader.conf rc.conf resolv.conf

# Note that the boot.config serial entry does not have a line feed
echo ; [ -f /media/boot.config ] && cat /media/boot.config
echo ; [ -f /media/boot/loader.conf ] && cat /media/boot/loader.conf
echo ; [ -f /media/etc/sysctl.conf ] && cat /media/etc/sysctl.conf
echo ; cat /media/etc/rc.conf
echo ; [ -f /media/etc/resolv.conf ] && cat /media/etc/resolv.conf

echo ; echo About to unmount /media
echo  Last chance to make final changes to the mounted image at /media
echo ; echo Unmount /media ?
echo -n "(y/n): " ; read umount
if [ "$umount" = "y" ] ; then
	echo ; echo Unmounting /media
	umount /media || { echo umount failed ; exit 1 ; }

	echo ; echo Destroying $md_id
	mdconfig -du $md_id || \
		{ echo $md_id destroy failed ; mdconfig -lv ; exit 1 ; }
else
	You can manually run \'umount /media\' and \'mdconfig -du $md_id\'
	echo ; echo Exiting ; exit 0
fi


# HARDWARE DEVICE HANDLING

echo ; echo dd the configured VM image to a device?
echo -n "(y/n): " ; read dd
if [ "$dd" = "y" ] ; then

	echo ; echo The availble devices are:
	sysctl kern.disks

	echo ; echo What device would you like to dd the VM image to?
	echo -n "(Device): " ; read device

	echo ; echo diskinfo -v for $device reads
	diskinfo -v "$device"

	echo ; echo WARNING! About to write $work_dir/$version/$img to $device!
	echo ; echo Continue?
	echo -n "(y/n): " ; read warning
	if [ "$warning" = "y" ] ; then

		# Consider progress feedback
\time -h dd if=$work_dir/$version/$img of=/dev/$device bs=1m conv=sync || \
			{ echo dd operation failed ; exit 1 ; }

		echo ; echo Recovering $device partitioning
		gpart recover $device

		echo ; echo Resize device to fill the available space?
		echo -n "(y/n): " ; read hardware_resize
		if [ "$hardware_resize" = "y" ] ; then
			echo ; echo Resizing ${device}p4
			gpart resize -i 4 "$device"
			echo ; echo Growing /dev/${device}p4
			growfs -y "/dev/${device}p4"
		fi
	fi
fi


# OPTIONAL VMDK WRAPPER

echo ; echo Create a VMDK wrapper for the image?
echo -n "(y/n): " ; read vmdk
if [ "$vmdk" = "y" ] ; then

	# Assuming blocksize of 512
	size_bytes="$( stat -f %z "$work_dir/$version/$img" )"
	RW=$(( "$size_bytes" / 512 ))
	cylinders=$(( "$RW" / 255 / 63 ))

cat << EOF > "$work_dir/$version/${img_base}.vmdk"
# Disk DescriptorFile
version=1
CID=12345678
parentCID=ffffffff
createType="vmfs"

RW $(( "$size_bytes" / 512 )) VMFS ${img_base}-flat.vmdk

ddb.virtualHWVersion = "4"
ddb.geometry.cylinders = "$cylinders"
ddb.geometry.heads = "255"
ddb.geometry.sectors = "63"
ddb.adapterType = "lsilogic"
EOF
	echo ; echo The resulting "${img_base}.vmdk" wrapper reads: ; echo
	cat "$work_dir/$version/${img_base}.vmdk"
	echo ; echo Renaming "$img" to "${img_base}-flat.vmdk"

	mv "$img" "${img_base}-flat.vmdk"
fi


# OPTIONAL GZIP COMPRESSION

# gzip because it is more compatible and will not override the upstream image

echo ; echo gzip compress the configured image file?
echo Remember to uncompress the image before use!
echo -n "(y/n): " ; read gzip
if [ "$gzip" = "y" ] ; then
	if [ "$vmdk" = "y" ] ; then
		\time -h gzip "${img_base}-flat.vmdk" || \
			{ echo gzip failed ; exit 1 ; }
# Consider progress feedback
	else
		\time -h gzip "$img" || { echo gzip failed ; exit 1 ; }
	fi
fi

echo ; echo Have a nice day!
exit 0
