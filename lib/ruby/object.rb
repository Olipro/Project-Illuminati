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