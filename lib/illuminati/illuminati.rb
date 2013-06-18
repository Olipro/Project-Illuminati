class Illuminati

  def git_write_blob(path, blob)
    File.open(path, 'w+') {|f| f.write(blob.read_raw.data) }
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

  def git_find_tag(target, repo)
    workers = []
    tag = nil
    repo.refs('refs/tags/*').each do |t|
      break if tag
      workers << Thread.new { tag = t if repo.lookup(t.target).target == target }
    end
    workers.each { |w| w.join } unless tag
    tag
  end

  def git_update_rev(format, repo, tag, message = Time.now.strftime('%Y-%m-%d %H:%M:%S'))
    rev = git_find_tag(tag, repo).name.scanf('refs/tags/'+format)[0]+1 rescue 1
    Rugged::Tag.create(repo, {
        :name => sprintf(format, rev),
        :target => repo.head.target,
        :message => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        :tagger => @p2_cfg[:git_author].merge(:time => Time.now) })
  end

  def channelexec(ssh, cmdarr, idx, q)
    cmd = cmdarr[idx][:cmd]

    channel = ssh.open_channel do |ch|
      ch.exec(cmd) do |ch, success|
        break unless success
        cmdarr[idx] = ''
        ch.on_data { |ch, data| cmdarr[idx] += data }
      end
    end

    channel.on_open_failed do |ch, code, desc|
      q << [ssh, cmdarr, idx] if code == 1
      puts ssh.host + " #{code} #{desc} - Channel open failed!\n" unless code == 1
    end
    channel

  end

  def run_sshcmds(host, user, optargs={})
    Net::SSH.start(host, user, optargs[:sshargs]) do |ssh|
      retcmds = optargs[:cmds]
      q = []
      retcmds.each {|file, _| q << [ssh, retcmds, file] }
      ssh.loop { ssh.busy? || q.empty? ? ssh.busy? : q.count.times { channelexec(*q.pop, q) } }
      return retcmds
    end rescue puts host + " - connection failure\n"
    nil
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
