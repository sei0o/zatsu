#!/usr/bin/ruby
require 'thor'
# require 'yaml'
require 'csv'
require_relative './dsl'

class Zatsu < Thor
  package_name 'zatsu'
  default_command :switch

  desc "plan [arg1:val1, ...]", "plan your schedule for today"
  def plan *args
    hash = {}
    args.each do |arg|
      hash[arg.split(":")[0]] = arg.split(":")[1]
    end
    tasks = DSL.parse File.read("generate.rb"), hash
    CSV.open "plan.csv", "w" do |f|
      f << ["推定(min)", "名前"]
      tasks.each do |name, task|
        f << [task[:duration], name]
      end
    end
    # File.write "plan.yml", result.to_yaml
    # system "vim plan.yml"
    system "vim plan.csv"

    puts "Good luck!"
  end

  desc "switch [task name]", "switch task"
  def switch task_name = nil
    # show rest task
  end
end

Zatsu.start ARGV