class Commit

  attr_accessor :author, :committer, :message, :parents, :update_ref

  def write
    self.parents = @repo.empty? ? [] : [@repo.head.target].compact if self.parents.nil?
    fail unless self.author.is_a?(Hash) && self.committer.is_a?(Hash) && \
      self.message.is_a?(String) && self.parents.is_a?(Array) && self.update_ref.is_a?(String)
    options = {
        :tree       => write_tree_hierarchy,
        :author     => self.author,
        :committer  => self.committer,
        :message    => self.message,
        :parents    => self.parents,
        :update_ref => self.update_ref
    }
    Rugged::Commit.create(@repo, options)
  end

  def initialize(repo)
    @repo = repo
    @empty = true
    tree = @repo.empty? ? nil : @repo.lookup(@repo.head.target).tree
    @rootbuilder = (tree.nil? ? Rugged::Tree::Builder.new : Rugged::Tree::Builder.new(tree))
    @treepairs = {'' => {:builder => @rootbuilder, :tree => tree, :fullpath => ''}}
    set_mutexes
  end

  def empty?
    @empty #TODO: possibly compare old/new commit hashes
  end

  def set_mutexes
    @mutex = {}
    @mutex[:add_treepair] = Mutex.new
  end

  def get_tree(name, tree = @treepairs[''])
    path = tree[:fullpath] + name
    tree = @treepairs[path]
    if tree.nil?
      parent = get_tree(path.rpartition('/').first)
      tree = create_tree(path.split('/').last, parent)
    end
    tree
  end

  def create_tree(name, tree)
    treepath = tree[:fullpath] + '/' + name
    @mutex[:add_treepair].synchronize {
      return @treepairs[treepath] unless @treepairs[treepath].nil?
      tree = @repo.lookup(tree[:tree][name][:oid]) rescue nil
      @treepairs[treepath] = {
        :builder => tree.nil? ? Rugged::Tree::Builder.new : Rugged::Tree::Builder.new(tree),
        :tree    => tree,
        :fullpath => treepath
      }
    } unless @treepairs[treepath]
    @treepairs[treepath]
  end

  def add_blob(path, data, filemode = 0100644, override_empty = false)
    return nil if data.empty?

    node = path.rpartition('/')
    tp = get_tree('/'+node[0])
    filename = node[2]

    unless override_empty || tp[:tree].nil?
      obj = tp[:tree][filename]
      return nil if !obj.nil? && obj[:oid] == Rugged::Repository.hash(data, :blob)
    end
    @empty = false
    tp[:builder] << {:name => filename, :oid => @repo.write(data, :blob), :filemode => filemode, :type => :blob}
  end

  def add_files(files, prepend = '')
    workers = []
    files.each do |file, data|
      workers << Thread.new { add_blob(prepend+file.to_s, data) }
    end
    workers.each {|w| w.join}
  end

  def iterate_element(hash, key, trees, mutex)
    key.split('/').each_index do |i|
      elem = key.split('/')[i]
      next if elem == '' && i == 0
      unless hash.has_key?(elem)
        mutex.synchronize {
          hash[elem] ||= { :builder => trees[key.split('/')[0..i].join('/')][:builder] }
        }
      end
      hash = hash[elem]
    end
  end

  def produce_hierarchy(trees)
    newhash = {:builder => trees.delete('')[:builder]}
    workers = []
    mutex = Mutex.new

    trees.each_pair do |key, val|
      hash = newhash
      workers << Thread.new {iterate_element(hash, key, trees, mutex)}
    end
    workers.each {|w| w.join}
    newhash
  end

  def write_tree_hierarchy
    repotree = produce_hierarchy(@treepairs)
    write_tree(repotree)
  end

  def write_tree(treehash)
    workers = []
    treehash.each_pair do |key, val|
      next if key == :builder
      return treehash[:builder].write(@repo) if treehash.size == 1
      workers << Thread.new {
        treehash[:builder] << { :name => key, :oid => write_tree(val), :filemode => 0040000, :type => :tree }
      }
    end
    workers.each {|w| w.join}
    treehash[:builder].write(@repo)
  end

end
