# Project Illuminati v0.4.3 - Welcome to the New World Order

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
Currently, there is a potential race condition with SSH hosts that rudely close the channel, resulting in only a partial capture of data. this typically only applies to older Cisco devices and the like, fortunately.
