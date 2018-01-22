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

  def start *time
    @tasks[@task_name][:start] = time
  end

  def duration minutes
    @tasks[@task_name][:duration] = minutes
  end
end