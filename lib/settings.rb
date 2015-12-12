class Hash
  # Converts all the keys to symbols from strings
  def deep_symbolize
    target = dup
    target.inject({}) do |memo, (key, value)|
      value = value.deep_symbolize if value.is_a?(Hash)
      memo[(key.to_sym rescue key) || key] = value
      memo
    end
  end
end

module Sync
  module Settings
    extend self

    @_settings = {}
    attr_reader :_settings

    # This is the main point of entry - we call Settings.load! and provide
    # a name of the file to read as it's argument. We can also pass in some
    # options, but at the moment it's being used to allow per-environment
    # overrides in Rails
    def load!(filename, options = {})
      newsets = YAML::load_file(filename).deep_symbolize
      if options[:env] && newsets[options[:env].to_sym]
        newsets = newsets[options[:env].to_sym]
      end
      deep_merge!(@_settings, newsets)
    end

    # Deep merging of hashes
    def deep_merge!(target, data)
      merger = proc{|key, v1, v2|
        Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
      target.merge! data, &merger
    end

    def method_missing(name, *args, &block)
      @_settings[name.to_sym] ||
      fail(NoMethodError, "unknown configuration root #{name}", caller)
    end
  end
end