## imagine.sh: A script to configure FreeBSD VM images for lab and production use

This script downloads a FreeBSD official release or current "VM-IMAGE" and modifies it using in-base tools such as sysrc(8) for boot on virtual and hardware-machines. The official FreeBSD VM images have the advantages of being configured for DHCP by default, include growfs, and most importantly, their weekly snapshots can be retrieved from a consistent URL. FreeBSD VM images are UFS formatted which makes them desirable for benchmarking OpenZFS on separate storage devices.

Note that this requires use of the /media mount point, administrative privileges, and the work directory is set to /root, into which it will create imagine-work.

The default behavior is can be changed by modifying the variables under VARIABLES. Hopefully you want the same packages as the author. You can change this if you like but pay attention to the limited space on the default VM image.

## Motivations

Imagine easy, frequent, and aggressive FreeBSD weekly snapshot testing!

Imagine FreeBSD as a first class Xen Dom0 host!

Imagine relying on in-base tools rather than Ansible, Salt, Puppet, Vagrant, and friends!

The key motivation of this project is to quickly turn a weekly VM image from the FreeBSD Release Engineering team into a usable VM or hardware machine for regression and performance testing. A combination of a USB-to-SATA adapter and trayless SATA adapters on hardware machines reduces the process to a few minutes.

If you are in a strictly-FreeBSD environment, it should be obvious that these same steps are mostly what you would ask of an orchestration tool.

To that end, it makes use of sysrc(8) to achieve idempotence, and has comments where sysrc does not support the modification.

Note that FreeBSD 13 makes a reasonable Xen Dom0 host and 14-CURRENT has UEFI support that needs some attention. Hint: Configure SSH for a 14/Xen/UEFI host and use the latest CPU you can.

Installing /usr/src and Xen Dom0 configuration are currently only performed after imaging to a physical device for lack of space in the default VM image.

## Modifications Performed

* Host name is changed the requested version, as "release" or "current"
* SSH is enabled with PermitRootLogin yes
* A .ssh directory is copied in if found in imagine-bits
* NTPd is enabled
* dumpdev=AUTO is set
* rc_debug is enabled
* verbose_loading is enabled
* boot_verbose is enabled
* autoboot_delay is set to five seconds
* Install packages, even if configuring a current image on a release host
* Change networking from "DHCP on all interfaces" to fixed or WiFi

## Optional Modifications

* Resize and grow the image root file system
* Enable serial output
* Install /usr/src to a rezied and grown file system
* Enable image to be a Xen Dom0 host using xenomorph
* dd(1) the VM image to a hardware device
* Generate a VMDK wrapper

Add your modifications! It is simply a shell script!

Note that this entry in /root/.ssh/config will suppress various SSH security checks that might not be desired in a lab:

```
Host 10.*      # Narrow this further as appopriate
StrictHostKeyChecking no
UserKnownHostsFile /dev/null
```

## Layout

This is designed to be re-run, decompressing the compressed VM image each time it is run. It will ask to re-download an image if it finds one, with weekly snapshots in mind. Accordingly, separate "working" and "bits" directories are used, the working one for the VM images and the "bits" one, for preconfigured items such as a .ssh directory to be copied in:

```
/root/imagine-work/current|release	# Work Directory
/lab/imagine-bits			# Bits Directory
```

Consider sharing the "bits" directory over NFS and in the example case, the "labnfs.sh" script performs a workstation connection to that share.

## Status

This is tested with FreeBSD 13.0 and 14 VM images on a 13.0 host.

## TO DO and Ideas List

* Consider pulling in lib_xenomorph.sh with a git sub-module
* Design a better "is /media mounted" check
* Offer to truncate the VM image larger, particularly for packages and /usr/src
* Verify that the configured image will fit a requested hardware device
* Consider incorporating [ec2-scripts](https://github.com/cperciva/ec2-scripts) - [Article]( https://www.daemonology.net/blog/2013-12-09-FreeBSD-EC2-configinit.html) - [Package]( https://www.freshports.org/sysutils/firstboot-pkgs/)
* Consider dumping and restoring to a zpool
* OMG make it more clear in pkg(8) that it supports installing packages from a release host to a current directory/jail/mounted VM

## Trivia

The project name was vm-image-prep during development and briefly "imagination", but that is way too long and typo-prone.

sysrc(8) cannot (yet) handle the following files because of confilcts with shell variable syntax, but it will warn of failures:
```
/boot.config
/etc/resolv.conf
```
This project is not an endorsement of GitHub
