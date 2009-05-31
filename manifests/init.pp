# apt.pp - common components and defaults for handling apt
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.
#
# Include the apt class to get a default mirror, regular updates of the apt
# cache, the backports gpg key, regular updates to the debian archive keys,
# testing and unstable pinned to manual, and a configurable sources.list.
#
# Depend on File[apt_config] for a configured apt; on Exec[apt_updated] for
# fresh apt caches;
#
# $custom_sources_list can be set to override the default sources
#
#
# With hints from
#  Micah Anderson <micah@riseup.net>
#  * backports key

class apt {

	# See README
	$real_apt_clean = $apt_clean ? {
		'' => 'auto',
		default => $apt_clean,
	}

	module_dir { 'apt': }

	package {
		[ 'apt', 'dselect' ]: ensure => installed,
	}

	# a few templates need lsbdistcodename
	include assert_lsbdistcodename

	case $custom_sources_list {
		'': {
			include default_sources_list
		}
		default: {
			config_file { "/etc/apt/sources.list":
				content => $custom_sources_list
			}
		}
	}

	class default_sources_list {
		config_file {
			# include main, security and backports
			# additional sources could be included via an array
			"/etc/apt/sources.list":
				content => template("apt/sources.list.erb"),
				require => Exec[assert_lsbdistcodename];
		}
	}

	config_file {
		# this just pins unstable and testing to very low values
		"/etc/apt/preferences":
			content => template("apt/preferences.erb"),
			# use File[apt_config] to reference a completed configuration
			alias => apt_config,
			# only update together
			require => File["/etc/apt/sources.list"];
		# little default settings which keep the system sane
		"/etc/apt/apt.conf.d/from_puppet":
			content => "APT::Get::Show-Upgraded true;\nDSelect::Clean $real_apt_clean;\n",
			before => File[apt_config];
	}

	# watch apt.conf.d
	file { "/etc/apt/apt.conf.d": ensure => directory, checksum => mtime; }

	# suppress annoying help texts of dselect
	line { dselect_expert:
		file => "/etc/dpkg/dselect.cfg",
		line => "expert",
		ensure => present,
	}

	exec {
		# "&& sleep 1" is workaround for older(?) clients
		"/usr/bin/dselect update && sleep 1 #on refresh":
			refreshonly => true,
			subscribe => [ File["/etc/apt/sources.list"],
				File["/etc/apt/preferences"], File["/etc/apt/apt.conf.d"],
				File[apt_config] ];
		"/usr/bin/dselect update && /usr/bin/apt-get autoclean #hourly":
			require => [ File["/etc/apt/sources.list"],
				File["/etc/apt/preferences"], File[apt_config] ],
			# Another Semaphor for all packages to reference
			alias => apt_updated;
	}

	## This package should really always be current
	package {
		[ "debian-archive-keyring", "debian-backports-keyring" ]:
			ensure => latest,
	}

	# This key was downloaded from
	# http://backports.org/debian/archive.key
	# and is needed to bootstrap the backports trustpath
	exec { "/usr/bin/apt-key add ${module_dir_path}/apt/backports.org.key && dselect update":
		alias => "backports_key",
		refreshonly => true,
		subscribe => File["${module_dir_path}/apt"],
		before => [ File[apt_config], Package["debian-backports-keyring"] ]
	}
}
