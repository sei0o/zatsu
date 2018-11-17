module Zatsu
  module Util
    module_function

    # Converts a string such as "9:10" to the appropriate Time instance
    def ct str
      Time.zone.now.change(hour: str.strip.split(':')[0].to_i, min: str.strip.split(':')[1].to_i, sec: 0)
    end

  end
end