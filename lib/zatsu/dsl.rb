module Zatsu
  class DSL
    attr_reader :tasks

    def initialize options, group
      @group = group
      @task_name = nil
      @tasks = {}
      @options = options
    end

    def self.parse program, group, hash
      new(hash, group).tap do |obj|
        obj.instance_eval program
      end.tasks
    end

    def task name
      @task_name = name
      @tasks[@task_name] ||= {custom: {}}
      yield if block_given?
      @task_name = nil
    end

    def start hour, minute
      @tasks[@task_name][:scheduled_start] = {hour: hour, min: minute}
    end

    def duration *minutes
      @tasks[@task_name][:estimated_duration] = minutes
    end

    def method_missing name, *args, &block
      @tasks[@task_name][:custom][name.to_sym] = args.size == 1 ? args[0] : args
    end
  end
end