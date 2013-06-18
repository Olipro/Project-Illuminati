module Rugged
  class Repository

    def changed?
      @changed
    end

    def open(path, isbare = true)
      new(path) rescue init_at(path, false)
    end

    def create_commit
      Commit(self)
    end

  end
end