module Zatsu
  class DSL
    attr_reader :tasks

    def initialize options
      @task_name = nil
      @tasks = {}
      @options = options
    end

    def self.parse program, hash
      new(hash).tap do |obj|
        obj.instance_eval program
      end.tasks
    end

    def task name
      @task_name = name
      @tasks[@task_name] ||= {}
      yield if block_given?
      @task_name = nil
    end

    def start hour, minute
      @tasks[@task_name][:scheduled_start] = {hour: hour, min: minute}
    end

    def duration minutes
      @tasks[@task_name][:estimated_duration] = minutes
    end

    def auto
      logs = Task.where(name: @task_name).where.not(actual_duration: nil).last(5)
      logs.empty? ? nil : logs.map(&:actual_duration).inject(:+) / logs.size
    end
  end
end