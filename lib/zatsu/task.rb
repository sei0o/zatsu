require 'json'

module Zatsu
  class Task < ActiveRecord::Base

    def custom_fields 
      JSON.parse(custom)
    end

    def set_custom_fields hash
      self.custom = hash.to_json
    end

    def custom_field sym
      JSON.parse(custom)[sym.to_s]
    end

    def set_custom_field sym, val
      x = custom_fields
      x[sym] = val
      set_custom_fields x
    end

  end
end