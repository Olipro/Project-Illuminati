class Illuminati

  def git_write_blob(path, childobj)
    f = File.open(path, 'w')
    f.write(childobj.read_raw.data)
    f.close
  end

  def git_checkout_tree(path, tree = @tree)
    workers = []
    tree.each do |child|
      childobj = @repo.lookup(child[:oid])
      case child[:type]
        when :tree
          Dir.mkdir(path+File::Separator+child[:name]) unless Dir.exists?(path+File::Separator+child[:name])
          workers << Thread.new { git_checkout_tree(path+File::Separator+child[:name], childobj) }
        when :blob
          workers << Thread.new { git_write_blob(path+File::Separator+child[:name], childobj) }
      end
    end
    workers.each { |worker| worker.join }
  end

  def git_update_rev(format, repo, message = Time.now.strftime('%Y-%m-%d %H:%M:%S'))
    rev = @head_tag.name.scanf('refs/tags/'+format)[0]+1 rescue 1
    Rugged::Tag.create(repo, {
        :name => sprintf(format, rev),
        :target => repo.head.target,
        :message => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        :tagger => @p2_cfg[:git_author].merge(:time => Time.now) })
  end

  def channelexec(ssh, cmdarr, idx, depth = 0)
    cmd = cmdarr[idx][:cmd]
    channel = ssh.open_channel do |ch|
      ch.exec(cmd) do |ch, success|
        break unless success
        result = ''
      ch.on_data do |ch, data|
	        cmdarr[idx] = '' unless result != ''
          result += data
	        cmdarr[idx] += data
      end
      ch.on_eof { cmdarr[idx] = result }
      end
    end
    channel.on_open_failed do |ch, code, desc|
      sleep(0.1) ; channelexec(
                               ssh,
			       cmdarr,
			       idx,
			       depth+1
			      ) if code == 1 && depth < 20
      puts ssh.host + " #{code} #{desc} - Channel open failed!\n" unless code == 1 && depth < 20
    end
  end

  def run_sshcmds(host, user, optargs={})
    Net::SSH.start(host, user, optargs[:sshargs]) do |ssh|
      channels = []
      retcmds = optargs[:cmds]
      retcmds.each_pair {|file, _| channels.push(channelexec(ssh, retcmds, file)) }
      ssh.loop rescue puts ssh.host + " disconnected prematurely\n"
      return retcmds
    end rescue puts host + " - connection failure\n"
    return nil
  end

  def run_rsync(host, user, cmds, tmpdir, cygwin=false)
    tmpdir = tmpdir[0].downcase + tmpdir[2..-1] if tmpdir[1] == ":"
    tmpdir = '/cygdrive/' + tmpdir if cygwin
    rsync_commands = []
    rsync_results = []
    cmds.each_pair do |to, data|
      rsync_cmd = "rsync -vaz --delete"
      data[:exclude].each do |e|
        rsync_cmd += " --exclude " + e
      end
      if host[0] == '[' && host[-1] == ']' then host = host[1..-1] ; user = "[" + user end
      rsync_cmd += " " + user + "@" + host + ":" + data[:dir] + " " + tmpdir
      rsync_commands << Thread.new { rsync_results << `#{rsync_cmd} 2>&1` }
    end
    rsync_commands.each { |thread| thread.join }
  end

  def filesys_tree_hash(wdir, ignore=[], tree='')
    data = {}
    workers = []
    ignored = ignore + ['.', '..']
    Dir.foreach(wdir) do |entry|
      next if ignored.include? entry
      full_path = File.join(wdir, entry)
      if File.directory?(full_path)
        workers << Thread.new {
          data.merge!(filesys_tree_hash(full_path, ignore, File.join(tree, entry)))
        }
      else
        elem = File.join(tree, entry)[1..-1]
        data.merge!({ (elem.to_sym rescue elem) => File.read(full_path) })
      end
    end
    workers.each { |worker| worker.join}
    return data
  end

end
