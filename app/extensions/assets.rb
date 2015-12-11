require 'sprockets'
require_relative '../../lib/sprockets/cache/memcache_store'

module Sync
  module Extensions
    module Assets extend self
    class UnknownAsset < StandardError; end

    module Helpers
      def asset_path(name)
        asset = settings.assets[name]
        raise UnknownAsset, "Unknown asset: #{name}" unless asset
        "#{settings.asset_host}/assets/#{asset.digest_path}"
      end
    end

    # Extensions can define options, routes, before filters, and error handlers by defining a
    # registered method on the extension module. Module.registered method is called immediately
    # after the extension module is added to the Sinatra::Base subclass and is passed the
    # class that the module was registered with.
    def registered(app)
      # Assets
      app.set :assets, assets = Sprockets::Environment.new(app.settings.root)

      assets.append_path('app/assets/javascripts')
      assets.append_path('app/assets/stylesheets')
      assets.append_path('app/assets/images')
      assets.append_path('app/assets/data')
      assets.append_path('vendor/assets/javascripts')
      assets.append_path('vendor/assets/stylesheets')

      app.set :asset_host, ''

      app.configure :development do
        assets.cache = Sprockets::Cache::FileStore.new('./tmp')
      end

      app.configure :production do
        assets.cache          = Sprockets::Cache::MemcacheStore.new
        assets.js_compressor  = Closure::Compiler.new
        # default JVM stack size is causing StackOverflow exception while running:
        # `RACK_ENV=production rake assets:precompile` task.
        assets.css_compressor = YUI::CssCompressor.new(java_opts: "-Xss64m")
      end

      app.helpers Helpers
    end
    end
  end
end