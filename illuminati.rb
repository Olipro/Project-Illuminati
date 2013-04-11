require "net/ssh"
require "rugged"

class Object
  def symbolize_keys
    return self unless ((self.is_a? Hash) || (self.is_a? Array))
    return self.map { |k| k.symbolize_keys } if self.is_a? Array
    return self.inject({}) { |m,(k,v)| m[(k.to_sym rescue k)] = v.symbolize_keys; m } if self.is_a? Hash
  end
  def symbolize_keys!
    self.replace(self.symbolize_keys)
  end
end

class Illuminati

  def git_open_repo(path, isbare = true)
    begin
      @repo = Rugged::Repository.new(path)
    rescue
      @repo = Rugged::Repository.init_at(path, false)
    end
    @tree = @repo.empty? ? nil : @repo.lookup(@repo.head.target).tree
    @treechanged = false
    @treebuilders = {}
    @add_mutex = Mutex.new
    @wri_mutex = Mutex.new
    @wri_cvmutex = Mutex.new
    @wri_cv = ConditionVariable.new
    @repo.refs(/tags/).each {|r| if @repo.lookup(r.target).target == @repo.lookup(@repo.head.target) ; @head_tag = r ; break end }
    return @repo
  end

  def git_find_tree(name, tree, treepath)
    uniqueid = ((name+'/'+treepath).to_sym rescue (name+'/'+treepath))
    ret = @treebuilders[uniqueid]
    return ret unless ret.nil?
    @add_mutex.synchronize {
      ret = @treebuilders[uniqueid]
      if ret.nil?
        tree = (!tree.nil? && !tree[name].nil? ? @repo.lookup(tree[name][:oid]) : nil)
        ret = @treebuilders[uniqueid] = {
          :builder => tree.nil? ? Rugged::Tree::Builder.new : Rugged::Tree::Builder.new(tree),
          :tree => tree
        }
      end
    }
    return ret
  end

  def git_add_to_repo(path, data, newtree, tree = @tree, filemode = 0100644, override_empty = false, parent = "")
    node = path.sub("\\", "/").split("/", 2)
    if node.count == 1
        return git_add_to_tree(node[0], data, newtree, tree, filemode, override_empty)
    else
      tb = git_find_tree(node[0], tree, parent)
      objtree = git_add_to_repo(node[1], data, tb[:builder], tb[:tree], filemode, override_empty, parent+'/'+node[0])
      return newtree if objtree.nil?
      Thread.current[:threadsrunning] = false
      @wri_mutex.synchronize {
        Thread.current.group.list.each do |thread|
          if thread.status != "run" && thread != Thread.current
            Thread.current[:threadsrunning] = true
            break
          end
        end
      }
      @wri_cvmutex.synchronize {
        if Thread.current[:threadsrunning]
          @wri_cv.wait(@wri_cvmutex)
        else
          @wrioid = objtree.write(@repo)
          @wri_cv.broadcast
        end
      }

        newtree << {:name => node[0], :oid => @wrioid, :filemode => 0040000, :type => :tree}
      return newtree
    end
  end

  def git_add_to_tree(name, data, newtree, tree = @tree, filemode = 0100644, override_empty = false)
    return nil if data.nil? || data.to_s.length == 0
    if !override_empty && !tree.nil? then
      obj = tree.get_entry_by_oid(Rugged::Repository.hash(data, :blob))
      return nil if !obj.nil? && obj[:name] == name
    end
    newtree << {:name => name, :oid => @repo.write(data, :blob), :filemode => filemode, :type => :blob}
    @treechanged = true
    return newtree
  end

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

  def git_commit(message, newtree, author = @author, committer = author, time = Time.now, parents = nil, updateref = 'HEAD')
    author[:time] = time
    committer[:time] = time
    parents = @repo.empty? ? [] : [ @repo.head.target].compact if parents == nil
    options = {
      :tree       => newtree,
      :author     => author,
      :committer  => committer,
      :message    => message,
      :parents    => parents,
      :update_ref => updateref
    }
    @tree = @repo.lookup(options[:tree])
    return Rugged::Commit.create(@repo, options)
    @treechanged = false
  end

  def git_tag(name, target, message=nil, tagger=@author.merge(:time => Time.now))
    data = { :name => name,  :target => target, :message => message, :tagger => tagger }
    Rugged::Tag.create(@repo, data)
  end

  def git_update_rev(format, target = @repo.head.target, message=Time.now.strftime("%Y-%m-%d %H:%M:%S"))
    rev = @head_tag.name.scanf("refs/tags/"+format)[0]+1 rescue 1
    name = sprintf(format, rev)
    git_tag(name, target, message)
  end

  def git_write_files(files, message, path, nocommit=false, author = @author, committer = author, time = Time.now, parents = nil, updateref = 'HEAD', override = false)
    oid = ''
    roottree = @tree.nil? ? Rugged::Tree::Builder.new : Rugged::Tree::Builder.new(@tree)
    workers = []
    tg = ThreadGroup.new
    files.each do |file, data|
      workers << Thread.new {
        tg.add(Thread.current)
        git_add_to_repo(
          path+"/"+file.to_s,
          data,
          roottree,
          @tree
        )
      }
    end
    workers.each { |worker| worker.join }
    return false if !override && !@treechanged
    @tree = @repo.lookup(roottree.write(@repo))
    git_commit(message, @tree.oid, author, committer, time, parents, updateref) unless nocommit
    idx = @repo.index
    idx.read_tree(@tree)
    idx.write
    return true
  end

  def channelexec(ssh, cmdarr, idx)
    cmd = cmdarr[idx][:cmd]
    channel = ssh.open_channel do |ch|
      ch.exec(cmd) do |ch, success|
        break unless success
        result = ""
      ch.on_data do |ch, data|
	        cmdarr[idx] =  "" unless result != ""
          result += data
	        cmdarr[idx] += data
      end
      ch.on_eof { cmdarr[idx] = result }
      end
    end
    channel.on_open_failed do |ch, code, desc|
      puts ssh.host + " Channel open failed!\n"
    end
  end

  def run_sshcmds(host, user, optargs={})
    Net::SSH.start(host, user, optargs[:sshargs]) do |ssh|
      channels = []
      retcmds = optargs[:cmds]
      retcmds.each_pair do |file, cmd|
        channels.push(channelexec(ssh, retcmds, file))
      end
      ssh.loop rescue puts ssh.host + " disconnected prematurely\n"
      return retcmds
    end
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
