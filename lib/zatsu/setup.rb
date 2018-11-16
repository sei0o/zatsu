require 'fileutils'
require 'active_record'
require_relative './const'

module Zatsu
  module_function

  def setup
    return if Dir.exist? ZATSU_DIR

    begin
      Dir.mkdir ZATSU_DIR, 0766
      open("#{ZATSU_DIR}/log.db", 'w+') {} # Create database file

      FileUtils.mkdir ["#{ZATSU_DIR}/generators", "#{ZATSU_DIR}/schedulers"]
      FileUtils.copy_entry "#{__dir__}/generators", "#{ZATSU_DIR}/generators"
      FileUtils.copy_entry "#{__dir__}/schedulers", "#{ZATSU_DIR}/schedulers"
    rescue Exception => ex
      p ex
    end

    migrate_db
  end

  def reset_scripts
    FileUtils.rm_rf ["#{ZATSU_DIR}/generators", "#{ZATSU_DIR}/schedulers"]
    FileUtils.copy_entry "#{__dir__}/generators", "#{ZATSU_DIR}/generators"
    FileUtils.copy_entry "#{__dir__}/schedulers", "#{ZATSU_DIR}/schedulers"

    puts "Copied original scripts!"
  end

  def migrate_db
    ActiveRecord::Base.establish_connection adapter: :sqlite3, database: "#{Dir.home}/.zatsu/log.db"
    # see: https://github.com/padrino/padrino-framework/pull/2182/commits/faf9becab40446346f405b9fda55538a7461a86a
    ActiveRecord::MigrationContext.new("#{__dir__}/db/migrate/").migrate
  end
end