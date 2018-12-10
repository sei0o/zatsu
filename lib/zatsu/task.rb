require 'active_record'
require_relative './taskmodel'

module Zatsu
  class Task
    attr_accessor :name, :actual_start, :actual_duration, :estimated_start, :estimated_duration, :scheduled_start, :custom

    def initialize hash
      @name = hash[:name] || ""
      @actual_start = hash[:actual_start]
      @actual_duration = hash[:actual_duration]
      @estimated_start = hash[:estimated_start]
      @estimated_duration = hash[:estimated_duration]
      @scheduled_start = hash[:scheduled_start]
      @custom = hash[:custom] || {}
    end

    def to_model
      tm = TaskModel.new(
        name: @name,
        actual_start: @actual_start,
        actual_duration: @actual_duration,
        estimated_start: @estimated_start,
        estimated_duration: @estimated_duration
      )
      tm.set_custom_fields @custom
      
      tm
    end
  end
end