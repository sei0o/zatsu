require 'yaml'
require_relative './manager'
require_relative './const'

module Zatsu
  module Util
    @@config = YAML.load_file(CONFIG_PATH)

    module_function

    def confirm str
      print "#{str} (y/n) "
      STDIN.gets.chomp == "y"
    end

    def config
      @@config
    end

    # Converts a string such as "9:10" to the appropriate Time instance
    def ct str
      Time.zone.now.change(hour: str.strip.split(':')[0].to_i, min: str.strip.split(':')[1].to_i, sec: 0)
    end

    def command_succeeded
      Manager.show_status if @@config["show_status_after_command"]
    end

  end
end