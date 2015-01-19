class Propagandadue < Illuminati

  def initialize(opts)
    @p2_cfg = YAML.load_file(opts[:cfgfile])[opts[:cfgname]].symbolize_keys
    @author = { :name => @p2_cfg[:git_author][:name], :email => @p2_cfg[:git_author][:email] }
    @opts = opts
    @hosts_tree = []
  end

  def ssh_worker(host, hostid)
    host[:user] = @p2_cfg[:defuser] if host[:user].nil?
    host[:bindto] = @p2_cfg[:bindto] if (host[:bindto].nil? && !@p2_cfg[:bindto].nil?)
    sshargs = {:keys => @p2_cfg[:ssh_keys]}
    host.each { |key, val|
      case key
        when :bindto ; sshargs[:bind_address] = val
        else sshargs[key] = val if Net::SSH::VALID_OPTIONS.include? key
      end
    }
    data = run_sshcmds(host[:hostname], host[:user], {:sshargs => sshargs, :cmds => host[:ssh]} )
    host[:dir] = host[(@p2_cfg[:defdirkey].to_sym rescue @p2_cfg[:defdirkey])] if host[:dir].nil?
    @hosts_tree[hostid][:files].merge!(data) unless data.nil?
  end

  def rsync_worker(host, hostid)
    #TODO: implement git_recurse_tree to checkout existing repo files
    #checkout = git_find_tree(, @tree, '/'+host[:hostname])
    checkout = {:tree => false} #DELETEME
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
      workers << Thread.new {ssh_worker(host, len)} unless (dostuff.include?(:no_ssh) || !host.has_key?(:ssh))
      workers << Thread.new {rsync_worker(host, len)} unless (dostuff.include?(:no_rsync) || !host.has_key?(:rsync))
    end
    workers.each { |worker| worker.join }

    changed = false

    repo = Rugged::Repository.new(@p2_cfg[:repo_path]) rescue Rugged::Repository.init_at(@p2_cfg[:repo_path], false)
    tag = repo.lookup(repo.head.target) rescue nil

    @hosts_tree.each do |host|
      commit = Commit.new(repo)

      host[:filter].each { |key, val|
        val.each { |arr| host[:files][key] = host[:files][key].send(*arr) } unless host[:files][key].nil?
      } if host[:filter].is_a? Hash

      commit.add_files(host[:files], (host[:dir].nil? ? host[:hostname] : host[:dir]) + '/')
      commit.message = host[:hostname] + ' ' + Time.now.strftime("%Y-%m-%d %H:%M:%S")
      commit.author = commit.committer = @p2_cfg[:git_author].merge( { :time => Time.now } )
      commit.parents = nil
      commit.update_ref = 'HEAD'
      commit.write unless commit.empty?

      changed |= !commit.empty?
    end
    git_update_rev(@p2_cfg[:revfmt], repo, tag) if changed
    puts 'Nothing to do.' unless changed && !@opts[:quiet]
  end

end
