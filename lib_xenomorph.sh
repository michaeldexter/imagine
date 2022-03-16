#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2021, 2022 Michael Dexter. All rights reserved

# Version v.0.8

# USAGE

# Source the file:
# ./lib_xenomorph.sh
# Use the function:
# xenomorph -r <Dom0 root> -c <Dom0 CPUs> -m <Dom0 RAM>
# -e for EFI boot
# -s without an argument to enable serial output
# Consider -u Undo xenomorphography - just add -x for the sysrc changes
#	boot.config, enable_tap may want to stay
# Consider -S serial speed, but it would need to coordinate with other tools

# If no path is provided, it will assume the root directory of the host: /

# Note the official xen-kernel message:
# https://svnweb.freebsd.org/ports/head/emulators/xen-kernel/pkg-message?view=markup

xenomorph() {
	dom0_root="/"
	dom0_cpus=2
	dom0_mem="4096"
	console_string="console=vga"
	uefi=""

	while getopts r:c:m:es opts ; do
		case $opts in
		r)
			dom0_root="$OPTARG"
			[ -d "$dom0_root/etc" ] || \
			{ echo $dom0_root appears to be invalid ; return 1 ; }
			;;
		c)
			dom0_cpus="$OPTARG"
			[ "$dom0_cpus" -gt 0 ] || \
			{ echo Dom0 CPU count $dom0_cpus invalid ; return 1 ; }
			# Simple math test to verify that it is an integer
			[ $(( "$dom0_cpus" * 1 )) ] || \
			{ echo Dom0 CPU count $dom0_cpus invalid ; return 1 ; }
			;;
		m)
			dom0_mem="$OPTARG"
			# Simple math test to verify that it is an integer
			# Removing for a better test given that the input
			# is likely 8g or something
			#[ $(( "$dom0_mem" * 1 )) ] || \
			#{ echo Dom0 RAM allocation invalid ; return 1 ; }
			;;
		e)
			uefi="yes"
	sysrc -f $dom0_root/boot/loader.conf efi_max_resolution="640x480"
			;;
		s)
			console_string="console=com1=115200,8n1 console=com1,vga sync_console"
			# sysrc does not support this and attempting idempotence
			if [ -f $dom0_root/boot.config ] ; then
				grep S115200 $dom0_root/boot.config || \
				printf "%s" "-D -h -S115200 -v" >> $dom0_root/boot.config
			else
				printf "%s" "-D -h -S115200 -v" > $dom0_root/boot.config
			fi

		sysrc -f $dom0_root/boot/loader.conf boot_multicons="YES"
		sysrc -f $dom0_root/boot/loader.conf boot_serial="YES"
		sysrc -f $dom0_root/boot/loader.conf comconsole_speed="115200"

# Make sure this is included if the argument order changes
		if [ "$uefi" = "yes" ] ; then
			sysrc -f $dom0_root/boot/loader.conf console="comconsole,efi"
		else
			sysrc -f $dom0_root/boot/loader.conf console="comconsole,vidconsole"
		fi
			;;
		esac
	done

#	[ $(sysctl -n machdep.bootmethod) = UEFI ] || \
#		{ echo ; echo Warning! UEFI boot is experimental }
	[ "$uefi" = "yes" ] && \
		{ echo ; echo Experimental UEFI boot has been requested ; sleep 3 ; }

	pkg -r $dom0_root install -y xen-tools xen-kernel || \
		{ echo Package installation failed ; return 1 ; }

	# sysrc does not support this and attempting idempotence
	grep max_user_wired $dom0_root/etc/sysctl.conf || \
		echo "vm.max_user_wired=-1" >> $dom0_root/etc/sysctl.conf

# The xc0 console appears to be included in FreeBSD 14
	grep "xc0" $dom0_root/etc/ttys || \
		echo "xc0     \"/usr/libexec/getty Pc\"         xterm   onifconsole  secure" >> $dom0_root/etc/ttys
	grep "xc0" $dom0_root/etc/ttys || \
		{ echo $dom0_root/etc/ttys configuration failed ; return 1 ; }

	sysrc -f $dom0_root/boot/loader.conf xen_kernel="/boot/xen"
	sysrc -f $dom0_root/boot/loader.conf xen_cmdline="dom0=pvh dom0_mem=${dom0_mem} dom0_max_vcpus=${dom0_cpus} $console_string guest_loglvl=all loglvl=all"

# Decide if this is one to remove upon request as it is not Xen-specific
	sysrc -f $dom0_root/boot/loader.conf if_tap_load="YES"

	sysrc -R $dom0_root xencommons_enable=YES

	return 0
}
