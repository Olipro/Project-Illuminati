# Project Illuminati v0.1 - Welcome to the New World Order

Project Illuminati is an absurdly multithreaded application designed for fast and flexible versioning of on-disk and live system configurations.

Backed by a Git repository, it provides a fast and easy means of comparing and maintaining configuration changes.

We highly recommend uploading your configuration files into a GitLab repository for beautiful web-based diffs. RANCID is Rancid.

## Requirements
* Ruby 1.9.3+
* Ruby Bundler
* Devkit (Windows only)

### Optional Extras
* rsync (command-line executable - Cygwin recommended for Windows)
* ssh (command-line executable - required for rsync over SSH)

## Configuration
Open `p2.sample.yml` in your favorite YAML editor (that's Notepad++, right?) for documentation on the configuration file. 

## Running Illuminati
    bundle install
    bundle exec ruby p2.rb -f [configuration file] -n [YAML root section name]
	
## Caveats
Illuminati should be considered something of a beta due to the fact that it is rather intolerant of errors currently; timed-out hosts will make it
unhappy, as will things such as incorrect configuration items. This will be ironed out, but please bear this in mind if you wish to use Project
Illuminati - be careful about your configuration and READ THE EXCEPTIONS if you hit a problem.