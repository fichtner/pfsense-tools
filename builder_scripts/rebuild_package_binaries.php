#!/usr/local/bin/php -q
<?php
/* 
 *  rebuild_package_binaries.sh
 *  Copyright (C) 2010 Scott Ullrich
 *  All rights reserved.
 *  
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are met:
 *  
 *  1. Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *  
 *  2. Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *  
 *  THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 *  INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 *  AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 *  AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 *  OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 *  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 *  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 *  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 *  POSSIBILITY OF SUCH DAMAGE.
 */

if(file_exists("/etc/inc/")) {
	include("/etc/inc/functions.inc");
	include("/etc/inc/util.inc");
	include("/etc/inc/xmlparse.inc");
}

if(file_exists("/usr/home/pfsense/pfSenseGITREPO/pfSenseGITREPO")) {
	include("/usr/home/pfsense/pfSenseGITREPO/pfSenseGITREPO/etc/inc/functions.inc");
	include("/usr/home/pfsense/pfSenseGITREPO/pfSenseGITREPO/etc/inc/util.inc");
	include("/usr/home/pfsense/pfSenseGITREPO/pfSenseGITREPO/etc/inc/xmlparse.inc");
}

function usage() {
	echo "Usage: {$argv[0]} -x <path to pkg xml> [-p <package name>] [-d]\n";
	echo "  Flags:";
	echo "    -x XML file containing package data.";
	echo "    -p Package name to build a single package and its dependencies.";
	echo "    -d Use DESTDIR when building.";
	echo "  Examples:";
	echo "     {$argv[0]} -x /home/pfsense/packages/pkg_info.8.xml";
	echo "     {$argv[0]} -x /home/pfsense/packages/pkg_info.8.xml -p squid";
	exit;
}

$options = getopt("x:p:d");

if(!isset($options['x']))
	usage();

// Set the XML filename that we are processing
$xml_filename = $argv[1];

$pkg = parse_xml_config_pkg($xml_filename, "pfsensepkgs");
if(!$pkg) {
	echo "An error occurred while trying to process {$xml_filename}.  Exiting.";
	exit;
}

exec("clear");

echo ">>> pfSense package binary builder is starting.\n";

if(!is_dir("/usr/ports")) {
	echo "!!! /usr/ports/ not found.   Please run portsnap fetch extract\n";
	exit;
}

if(!is_dir("/usr/ports/packages/All")) 
	exec("mkdir -p /usr/ports/packages/All");

if($pkg['copy_packages_to_host_ssh_port'] && 
	$pkg['copy_packages_to_host_ssh'] &&
	$pkg['copy_packages_to_folder_ssh']) {
	$copy_packages_to_folder_ssh = $pkg['copy_packages_to_folder_ssh'];
	$copy_packages_to_host_ssh = $pkg['copy_packages_to_host_ssh'];
	$copy_packages_to_host_ssh_port = $pkg['copy_packages_to_host_ssh_port'];
	echo ">>> Setting the following RSYNC/SSH parameters: \n";
	echo "    copy_packages_to_folder_ssh:    $copy_packages_to_folder_ssh\n";
	echo "    copy_packages_to_host_ssh:      $copy_packages_to_host_ssh\n";
	echo "    copy_packages_to_host_ssh_port: $copy_packages_to_host_ssh_port\n";
}

foreach($pkg['packages']['package'] as $pkg) {
	if (isset($options['p']) && ($options['p'] != $pkg['name']))
		continue;
	if($pkg['build_port_path']) {
		foreach($pkg['build_port_path'] as $build) {
			if(isset($options['d'])) {
				$DESTDIR="DESTDIR=/usr/pkg/{$build['name']}";
				echo ">>> Using $DESTDIR \n";
			} else 
				$DESTDIR="";
			$build_options="";
			if($pkg['build_options']) 
				$build_options = $pkg['build_options'];
			if(file_exists("/var/db/ports/{$build['name']}/options")) {
				echo ">>> Using /var/db/ports/{$build['name']}/options";
				$build_options .= str_replace("\n", " ", file_get_contents("/var/db/ports/{$build['name']}/options"));
			}
			echo ">>> Processing {$build}";
			if($build_options) 
				echo " BUILD_OPTIONS: {$build_options}\n";
			else 
				echo "\n";
			`cd {$build} && make clean depends package-recursive {$DESTDIR} BATCH=yes WITHOUT_X11=yes {$build_options} FORCE_PKG_REGISTER=yes clean </dev/null 2>&1`;
		}
	}
}

echo ">>> /usr/ports/packages/All now contains:\n";
system("ls /usr/ports/packages/All");

if($copy_packages_to_folder_ssh) {
	echo ">>> Copying packages to {$copy_packages_to_host_ssh}\n";
	system("/usr/local/bin/rsync -ave ssh --timeout=60 --rsh='ssh -p{$copy_packages_to_host_ssh_port}' /usr/ports/packages/All/* {$copy_packages_to_host_ssh}:{$copy_packages_to_folder_ssh}/");
}

echo ">>> Package binary build run ended.\n";

?>