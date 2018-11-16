require 'fileutils'

module Zatsu
  ZATSU_DIR = "#{Dir.home}/.zatsu"

  def setup
    return if Dir.exist? ZATSU_DIR

    begin
      Dir.mkdir DATA_DIR, 0766
      open("#{ZATSU_DIR}/log.db", 'w+') {} # Create database file

      FileUtils.mkdir ["#{ZATSU_DIR}/generators", "#{ZATSU_DIR}/schedulers"]
      FileUtils.copy_entry './generators', "#{ZATSU_DIR}/generators"
      FileUtils.copy_entry './schedulers', "#{ZATSU_DIR}/schedulers"
    rescue Exception => ex
      p ex
    end

    ActiveRecord::Base.establish_connection adapter: :sqlite3, database: "#{Dir.home}/.zatsu/log.db"
    ActiveRecord::Migrator.migrate "#{Dir.home}/.zatsu/log.db", nil
  end

  def reset_scripts
    FileUtils.rm_rf ["#{ZATSU_DIR}/generators", "#{ZATSU_DIR}/schedulers"]
    FileUtils.copy_entry './generators', "#{ZATSU_DIR}/generators"
    FileUtils.copy_entry './schedulers', "#{ZATSU_DIR}/schedulers"

    puts "Copied original scripts!"
  end
end