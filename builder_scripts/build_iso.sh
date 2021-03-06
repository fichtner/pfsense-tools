#!/bin/sh
#
# Common functions to be used by build scripts
#
#  build_iso.sh
#  Copyright (C) 2004-2009 Scott Ullrich
#  All rights reserved.
#  
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#  
#  1. Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#  
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#  
#  THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
#  INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
#  AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
#  AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
#  OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.
#
# Crank up error reporting, debugging.
#  set -e 
#  set -x

# Suck in local vars
. ./pfsense_local.sh

# Suck in script helper functions
. ./builder_common.sh

# If a embedded build has been performed we need to nuke
# /usr/obj.$dir/ since full uses a different
# src.conf
if [ -f ${MAKEOBJDIRPREFIX}/pfSense_wrap.$FREEBSD_VERSION.world.done ]; then
	echo -n "Removing $MAKEOBJDIRPREFIX/* since embedded build performed prior..."
	rm -rf ${MAKEOBJDIRPREFIX}/*
	echo "done."
fi

# Define src.conf
if [ -z "${SRC_CONF:-}" ]; then
	export SRC_CONF="${BUILDER_SCRIPTS}/conf/src/src.conf.$FREEBSD_VERSION"
	export SRC_CONF_INSTALL="${BUILDER_SCRIPTS}/conf/src/src.conf.$FREEBSD_VERSION.install"
fi

# Add etcmfs and rootmfs to the EXTRAPLUGINS plugins used by freesbie2
export EXTRAPLUGINS="${EXTRAPLUGINS:-} rootmfs varmfs etcmfs"

if [ ! -z "${CUSTOM_REMOVE_LIST:-}" ]; then
	echo ">>> Using ${CUSTOM_REMOVE_LIST:-} ..."
	export PRUNE_LIST="${CUSTOM_REMOVE_LIST:-}"
else
	echo ">>> Using ${BUILDER_SCRIPTS}/conf/rmlist/remove.list.iso.$FREEBSD_VERSION ..."
	export PRUNE_LIST="${BUILDER_SCRIPTS}/conf/rmlist/remove.list.iso.$FREEBSD_VERSION"
fi

export DEFAULT_KERNEL=${DEFAULT_KERNEL:-pfSense_SMP.${FREEBSD_VERSION}}

# This should be run first
launch

# Make sure source directories are present.
ensure_source_directories_present

# Ensure binaries are present that builder system requires
install_required_builder_system_ports

# Ensure pbi tools are installed
install_pbi_tools

# Check if we need to force a ports rebuild
check_for_forced_pfPorts_build

# Clean up items that should be cleaned each run
freesbie_clean_each_run

# Allow old CVS_CO_DIR to be deleted later
if [ -d $CVS_CO_DIR ]; then 
	chflags -R noschg $CVS_CO_DIR
fi 

# Output build flags
print_flags

# Install BSDInstaller
rebuild_and_install_bsdinstaller

# Update FreeBSD sources and install custom patches
if [ "$BUILDER_AUTO_UPDATE_APPLY_PATCHES" = "YES" ]; then
	update_freebsd_sources_and_apply_patches
else
	echo ">>> BUILDER_AUTO_UPDATE_APPLY_PATCHES is set to no.  Skipping builder update and patches."
fi

# Checkout a fresh copy from pfsense cvs depot
echo ">>> Updating pfSense GIT repo..."
update_cvs_depot

# Calculate versions
export version_kernel=`cat $CVS_CO_DIR/etc/version_kernel`
export version_base=`cat $CVS_CO_DIR/etc/version_base`
export version=`cat $CVS_CO_DIR/etc/version`

# Prepare object directry
echo ">>> Preparing object directory..."
freesbie_make obj

# Build world, kernel and install
echo ">>> Building world for ISO... $FREEBSD_VERSION  $FREEBSD_BRANCH ..."
make_world

# Build kernels
echo ">>> Building kernel configs: $BUILD_KERNELS for FreeBSD: $FREEBSD_BRANCH ..."
build_all_kernels

# Check for freesbie builder issues
if [ -f ${BUILDER_LOGS}/freesbie2/.tmp_kernelbuild ]; then
	echo "Something has gone wrong!  Press ENTER to view log file."
	read ans
	more ${BUILDER_LOGS}/freesbie2/.tmp_kernelbuild 
	exit
fi

# Add extra pfSense packages
echo ">>> Phase install_custom_packages"
install_custom_packages
echo ">>> Phase set_image_as_cdrom"
set_image_as_cdrom

echo ">>> Searching for packages..."
set +e # grep could fail
if [ "$PFSPKGFILE" = "" ]; then
	echo "PFSPKGFILE is not defined.  Setting."
	PFSPKGFILE=/tmp/pfspackages
fi
rm -f $PFSPKGFILE
(${PKG_INFO} | grep bsdinstaller) > $PFSPKGFILE
(${PKG_INFO} | grep lua) >> $PFSPKGFILE
set -e

# Install packages needed for livecd
install_pkg_install_ports

echo ">>> Installing packages: " 
cat $PFSPKGFILE

# Add installer bits
cust_populate_installer_bits

export PKGFILE=${PFSPKGFILE}
if [ ${FREEBSD_VERSION} -ge 10 ]; then
	freesbie_make pkgnginstall
else
	freesbie_make pkginstall
fi
unset PKGFILE

# Add extra files such as buildtime of version, bsnmpd, etc.
echo ">>> Phase populate_extra..."
cust_populate_extra

# Overlay pfsense checkout on top of FreeSBIE image
# using the customroot plugin
echo ">>> Merging extra items..."
freesbie_make extra

# Overlay host binaries
cust_overlay_host_binaries
check_for_zero_size_files

# Check for custom config.xml
cust_install_config_xml

# Install custom pfSense-XML packages from a chroot
pfsense_install_custom_packages_exec

# See if php configuration script is available
if [ -f $PFSENSEBASEDIR/etc/rc.php_ini_setup ]; then
	echo ">>> chroot'ing and running /etc/rc.php_ini_setup"
	chroot $PFSENSEBASEDIR /etc/rc.php_ini_setup
fi

# Overlay final files
install_custom_overlay_final

# LiveCD specifics
setup_livecd_specifics

# Ensure config.xml exists
copy_config_xml_from_conf_default

# Test PHP installation
test_php_install

# Check to see if we have a healthy installer
ensure_healthy_installer

# Overlay any loader.conf customziations
install_extra_loader_conf_options

# Create md5 summary file listing checksums
create_md5_summary_file

# Create mtree summary file listing owner/permissions/sha256 and similar
create_mtree_summary_file

# Setup custom tcshrc prompt
setup_tcshrc_prompt

# Setup serial port helper hints
if [ "$FBSD_VERSION" -gt "7" ]; then
	setup_serial_hints
fi

# Allow a custom function to be called from pfsense-build.conf
# example: disable_lan_disable_dhcpd_enable_sshd
if [ "$CUSTOM_CALL_SHELL_FUNCTION" != "" ]; then
	eval $CUSTOM_CALL_SHELL_FUNCTION
fi

# Prepare /usr/local/pfsense-clonefs
echo ">>> Cloning filesystem..."
freesbie_make clonefs

# Ensure /home and /etc exists
mkdir -p $CLONEDIR/home $CLONEDIR/etc

# Finalize iso
echo ">>> Finalizing iso..."
(freesbie_make iso) >/dev/null 2>&1
echo ">>> Creating memstick..."
(create_memstick_image) >/dev/null 2>&1
echo ">>> Creating serial memstick..."
(create_memstick_serial_image) >/dev/null 2>&1

# Check for zero sized files.  loader.conf is one of the culprits.
check_for_zero_size_files
report_zero_sized_files

# Email that the operation has completed
email_operation_completed

echo ">>> $MAKEOBJDIRPREFIXFINAL now contains:"
ls -lah $MAKEOBJDIRPREFIXFINAL

# Run final finish routines
finish
