#!/usr/bin/ruby
require 'thor'
require 'csv'
require 'active_record'
require 'active_support'
require_relative './dsl'
require_relative './task'
require_relative './schedulers/firstfit'

ActiveRecord::Base.establish_connection adapter: :sqlite3, database: './log.db'
Time.zone = 'Asia/Tokyo'

module Zatsu
  module Manager
    module_function

    def create_plan hash
      parsed = {}
      Dir.glob 'generators/*.rb' do |genf|
        parsed.merge! DSL.parse File.read(genf), hash
      end
      schedule_tasks parsed
    end

    def get_plan
      Task.where(estimated_start: Time.zone.now.all_day).order(:estimated_start)
    end

    def show_status
      puts "Est.  Act.  Est.  Act.  Name"
      get_plan.each do |t|
        puts "#{t.estimated_start.localtime.strftime('%R').ljust(5)} #{t.actual_start&.localtime&.strftime('%R')&.ljust(5) || '     '} #{t.estimated_duration.to_s.rjust(5)} #{t.actual_duration.to_s.rjust(5)} #{t.name}"
      end
    end

    def schedule_tasks tasks
      FirstFit.new(tasks).schedule
    end

    def switch_task
      [nil, get_plan, nil].flatten.each_cons(2) do |prev, cur| # 汚い
        unless cur&.actual_start
          cur&.update actual_start: Time.zone.now
          prev&.update actual_duration: (Time.zone.now - prev.actual_start) / 60
          break
        end
      end
    end

    def start_recording
      get_plan[0].update actual_start: Time.zone.now
    end

    def review_recording
      # do nothing yet
    end

    def recording?
      get_plan.any? && get_plan[0].actual_start && !get_plan[-1].actual_duration
    end
  end

  class Command < Thor
    package_name 'zatsu'
    default_command :switch

    desc "plan [arg1:val1, ...]", "plan your schedule for today"
    def plan *args
      if Manager.recording?
        print "A recording has already started. Want to stop and create a new plan? (y/n) "
        return if STDIN.gets.chomp != "y"
      end

      hash = {}
      args.each do |arg|
        hash[arg.split(":")[0]] = arg.split(":")[1]
      end

      Task.where(estimated_start: Time.zone.now.all_day).destroy_all
      Manager.create_plan hash
      Manager.show_status
    end

    desc "status", "show current status"
    def status
      Manager.show_status
    end

    desc "switch [task name]", "switch task"
    def switch task_name = nil
      if Manager.recording?
        Manager.switch_task
        Manager.show_status

        unless Manager.recording? # if finished
          print "You have finished the plan for today. Want to review your record? (y/n) "
          Manager.review_recording if STDIN.gets.chomp == "y"
        end
      else
        Manager.start_recording
      end
    end
  end
end

Zatsu::Command.start ARGV