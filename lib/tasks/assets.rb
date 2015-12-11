# Builds a single application.css and application.js from all the assets to run:
# `bundle exec rake assets:precompile`
namespace :assets do
  desc 'Precompile assets'
  task :precompile => :app do
    assets = Sync::Routes::Base.assets
    target = Pathname(Sync::App.root) + 'public/assets'

    puts "Assets: #{assets}"
    puts "Target: #{target}"

    assets.each_logical_path do |logical_path|
      if asset = assets.find_asset(logical_path)
        filename = target.join(asset.digest_path)
        FileUtils.mkpath(filename.dirname)
        asset.write_to(filename)

        filename = target.join(logical_path)
        FileUtils.mkpath(filename.dirname)
        asset.write_to(filename)
      end
    end
  end
end