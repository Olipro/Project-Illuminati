require './p2'
require 'trollop'

opts = Trollop::options do
  opt :cfgfile, "Specifies the YAML config file to use", :type => :string, :short => 'f'
  opt :cfgname, "Name of the section in the YAML config to use", :type => :string, :short => 'n'
  opt :quiet, "Run quietly, (no output)", :short => 'q'
  opt :no_rsync, "Do not perform rsync on hosts", :short => 'R'
  opt :no_ssh, "Do not perform SSH on hosts", :short => 'S'
end

Trollop::die :cfgfile, "You must specify a config file" if opts[:cfgfile].nil?
Trollop::die :cfgname, "You must specify a root config section" if opts[:cfgname].nil?

p2 = Propagandadue.new(opts)
p2.all_winux(opts)
