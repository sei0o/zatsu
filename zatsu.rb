#!/usr/bin/ruby
require 'thor'
require 'csv'
require 'active_record'
require 'active_support'
require_relative './dsl'
require_relative './task'

ActiveRecord::Base.establish_connection adapter: :sqlite3, database: './log.db'

module Zatsu
  class Command < Thor
    package_name 'zatsu'
    default_command :switch

    desc "plan [arg1:val1, ...]", "plan your schedule for today"
    def plan *args
      hash = {}
      args.each do |arg|
        hash[arg.split(":")[0]] = arg.split(":")[1]
      end

      tasks = DSL.parse File.read("generate.rb"), hash
      tasks.each do |name, task|
        puts "#{task[:estimated_duration]}(#{task[:start]}) #{name}"
      end
      # CSV.open "plan.csv", "w" do |f|
      #   f << ["推定(min)", "開始時刻", "名前"]
      #   tasks.each do |name, task|
      #     f << [task[:estimated_duration], task[:start], name]
      #   end
      # end
      # system "vim plan.csv"

      tasks.each do |name, task|
        st = nil
        if task[:start]
          hour, min = task[:start].split(":")
          st = Time.now.change hour: hour, min: min
        end
        Task.create(
          name: name,
          estimated_duration: task[:estimated_duration],
          start: st
        )
      end

      puts "Good luck!"
    end

    desc "switch [task name]", "switch task"
    def switch task_name = nil
      # show rest task
    end
  end
end

Zatsu::Command.start ARGV