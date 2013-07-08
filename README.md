# Project Illuminati v0.4.1 - Welcome to the New World Order

Project Illuminati is an absurdly multithreaded application designed for fast and flexible versioning of on-disk and live system configurations.

Backed by a Git repository, it provides a fast and easy means of comparing and maintaining configuration changes.

We highly recommend uploading your configuration files into a GitLab repository for beautiful web-based diffs. RANCID is Rancid.

## Requirements
* Ruby 1.9.3+
* Ruby Bundler
* Devkit (Only applicable to Windows)

### Optional Extras
* rsync (command-line executable - Cygwin recommended for Windows)
* ssh (command-line executable - required for rsync over SSH)

## Configuration
Open `p2.sample.yml` in your favorite YAML editor (that's Notepad++, right?) for documentation on the configuration file. 

## Running Illuminati
    bundle install
    bundle exec ruby p2.rb -f [configuration file] -n [YAML root section name]
	
## Caveats
Illuminati should be considered something of a beta - currently it will tolerate most ssh issues and wait if too many channel are open, however, this
is currently implemented using a sleep; most people won't need to worry about this unless executing hundreds to thousands of SSH commands on a single
host. See the roadmap for more information.

