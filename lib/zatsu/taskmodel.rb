require 'json'

module Zatsu
  class TaskModel < ActiveRecord::Base
    self.table_name = "tasks"

    def self.today
      self.where(actual_start: Time.zone.now.all_day)
          .or(where(estimated_start: Time.zone.now.all_day))
          .order(:actual_start)
          .order(Arel.sql('actual_start IS NULL')) # actualを優先
          .order(Arel.sql('actual_duration IS NULL'))
          .order(Arel.sql('estimated_start IS NOT NULL ASC'))
    end

    def custom_fields
      JSON.parse(custom.empty? ? "{}" : custom)
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

    # TODO: taskmodel to task instance?

  end
end