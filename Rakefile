require 'active_record'
require 'yaml'

task :default => :migrate

desc "Migrate DB"
task :migrate => :environment do
  ActiveRecord::Migrator.migrate 'db/migrate', ENV["VERSION"] ? ENV["VERSION"].to_i : nil
end

task :environment do
  ActiveRecord::Base.establish_connection adapter: :sqlite3, database: './log.db'
end