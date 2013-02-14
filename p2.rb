require 'yaml'
require 'tmpdir'
require 'scanf'
require './illuminati'

class Propagandadue < Illuminati

  def initialize(opts)
    @p2_cfg = YAML.load_file(opts[:cfgfile])[opts[:cfgname]].symbolize_keys
    @opts = opts
    git_open_repo(@p2_cfg[:repo_path])
    @author = { :name => @p2_cfg[:git_author][:name], :email => @p2_cfg[:git_author][:email] }
    @tree_mutex = Mutex.new
    @hosts_tree = []
  end

  def ssh_worker(host, hostid)
    host[:user] = @p2_cfg[:defuser] if host[:user].nil?
    data = run_sshcmds( host[:hostname], host[:user],
                        {
                            :sshargs => { :keys => @p2_cfg[:ssh_keys] },
                            :cmds => host[:ssh]
                        })
    host[:dir] = host[(@p2_cfg[:defdirkey].to_sym rescue @p2_cfg[:defdirkey])] if host[:dir].nil?
    @hosts_tree[hostid][:files].merge!(data)
  end

  def rsync_worker(host, hostid)
    checkout = git_find_tree(host, @tree)
    workerfiles = {}
    Dir.mktmpdir { |dir|
      git_checkout_tree(dir, checkout[:tree]) if checkout[:tree]
      host[:user] = @p2_cfg[:defuser] if host[:user].nil?
      run_rsync(host[:hostname], host[:user], host[:rsync], dir, @p2_cfg[:cygwin])
      workerfiles.merge!(filesys_tree_hash(dir))
    }
    @hosts_tree[hostid][:files].merge!(workerfiles)
  end

  def all_winux(*dostuff)
    workers = []
    cmds = @p2_cfg[:hosts].each do |host|
      @hosts_tree << host.merge({ :files => {} })
      len = @hosts_tree.length-1
      workers << Thread.new {ssh_worker(host, len)} unless dostuff.include?(:no_ssh)
      workers << Thread.new {rsync_worker(host, len)} unless dostuff.include?(:no_rsync)
    end
    workers.each { |worker| worker.join }
    changed = false
    @hosts_tree.each do |host|
      host[:filter].each { |key, val|
        val.each { |arr| host[:files][key] = host[:files][key].send(*arr) } unless host[:files][key].nil?
      } if host[:filter].is_a? Hash
      changed |= git_write_files(host[:files], host[:hostname] + " " + Time.now.strftime("%Y-%m-%d %H:%M:%S"), host[:dir].nil? ? host[:hostname] : host[:dir], false, @p2_cfg[:git_author])
    end
    git_update_rev(@p2_cfg[:revfmt]) if changed
    puts "Nothing to do." unless changed && !@opts[:quiet]
  end

end
