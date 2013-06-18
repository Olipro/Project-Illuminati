module Rugged
  class Tree

    class Builder
      attr_accessor :treepairs

      def iterate_element(hash, key, mutex)
        key.split('/').each_index do |i|
          elem = key.split('/')[i]
          unless hash.has_key?(elem)
            mutex.synchronize {
              hash[elem] = {
                  :builder => trees[key.split('/')[0..i].join('/')][:builder]
              } unless hash.has_key?(elem)
            }
          end
          hash = hash[elem]
        end
      end

      def produce_hierarchy(trees)
        newhash = {}
        workers = []
        mutex = Mutex.new

        trees.each_pair do |key, val|
          hash = newhash
          workers << Thread.new {iterate_element(key, hash, mutex)}
          workers.each {|w| w.join}
        end
        newhash
      end

    end

  end
end