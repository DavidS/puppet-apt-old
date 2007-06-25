# apt.pp - common components and defaults for handling apt
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.
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

	# a few templates need lsbdistcodename
	include assert_lsbdistcodename

	config_file {
		# include main, security and backports
		# additional sources could be included via an array
		"/etc/apt/sources.list":
			content => template("apt/sources.list.erb"),
			require => Exec[assert_lsbdistcodename];
		# this just pins unstable and testing to very low values
		"/etc/apt/preferences":
			content => template("apt/preferences.erb"),
			# use File[apt_config] to reference a completed configuration
			# See "The Puppet Semaphor" 2007-06-25 on the puppet-users ML
			alias => apt_config,
			# only update together
			require => File["/etc/apt/sources.list"];
		# little default settings which keep the system sane
		"/etc/apt/apt.conf.d/from_puppet":
			content => "APT::Get::Show-Upgraded true;\nDSelect::Clean $real_apt_clean;\n",
			before => File[apt_config];
	}

	$base_dir = "/var/lib/puppet/modules/apt"
	file {
		# remove my legacy files
		[ "/etc/apt/backports.key", "/etc/apt/apt.conf.d/local-conf" ]:
			ensure => removed;
		# create new modules dir
		$base_dir: ensure => directory;
		# watch apt.conf.d
		"/etc/apt/apt.conf.d": ensure => directory, checksum => mtime;
	}

	# suppress annoying help texts of dselect
	line { dselect_expert:
		file => "/etc/dpkg/dselect.cfg",
		line => "expert",
		ensure => present,
	}

	exec {
		# "&& sleep 1" is workaround for older(?) clients
		"/usr/bin/apt-get -y update && sleep 1 #on refresh":
			refreshonly => true,
			subscribe => [ File["/etc/apt/sources.list"],
				File["/etc/apt/preferences"], File["/etc/apt/apt.conf.d"],
				File[apt_config] ];
		"/usr/bin/apt-get -y update && /usr/bin/apt-get autoclean #hourly":
			require => [ File["/etc/apt/sources.list"],
				File["/etc/apt/preferences"], File[apt_config] ],
			# Another Semaphor for all packages to reference
			alias => apt_updated;
	}

	case $lsbdistcodename {
		etch: {
			## This package should really always be current
			package { "debian-archive-keyring": ensure => latest, }

			# This key was downloaded from
			# http://backports.org/debian/archive.key
			# and is needed to verify the backports
			file { "${base_dir}/backports.org.key":
				source => "puppet://$servername/apt/backports.org.key",
				mode => 0444, owner => root, group => root,
				before => File[apt_config],
			}
			exec { "/usr/bin/apt-key add ${base_dir}/backports.org.key":
				refreshonly => true,
				subscribe => File["${base_dir}/backports.org.key"],
				before => File[apt_config],
			}
		}
	}
}