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
      tasks = get_plan
      tasks = Task.where(actual_start: Time.zone.now.all_day) if tasks.empty?
      tasks.each do |t|
        puts "#{t&.estimated_start&.localtime&.strftime('%R')&.ljust(5) || '     '} #{t.actual_start&.localtime&.strftime('%R')&.ljust(5) || '     '} #{t&.estimated_duration&.to_s&.rjust(5) || '     '} #{t&.actual_duration&.to_s&.rjust(5) || '     '} #{t.name}"
      end
    end

    def schedule_tasks tasks
      FirstFit.new(tasks).schedule
    end

    def switch_task
      if get_plan.any?
        [nil, get_plan, nil].flatten.each_cons(2) do |prev, cur| # 汚い
          unless cur&.actual_start
            cur&.update actual_start: Time.zone.now
            prev&.update actual_duration: (Time.zone.now - prev.actual_start) / 60
            break
          end
        end
      else
        latest = Task.order(:actual_start).last
        latest.update actual_duration: (Time.zone.now - latest.actual_start) / 60
        Task.create actual_start: Time.zone.now
      end
    end

    def start_recording
      if get_plan.any?
        get_plan[0].update actual_start: Time.zone.now
      else
        Task.create actual_start: Time.zone.now
      end
    end

    def review_recording
      # do nothing yet
    end

    def recording?
      (get_plan.any? && get_plan[0].actual_start && !get_plan[-1].actual_duration) || # with plan
      (get_plan.empty? && Task.exists?(actual_start: Time.zone.now.all_day, actual_duration: nil)) # without plan
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

      Manager.get_plan.destroy_all
      Manager.create_plan hash
      Manager.show_status
    end

    desc "status", "show current status"
    def status
      Manager.show_status
    end

    desc "switch [task name] [--noplan]", "switch task"
    option :noplan, type: :boolean
    def switch task_name = nil
      if Manager.recording?
        Manager.switch_task
        Manager.show_status

        if !options[:noplan] && !Manager.recording? # if finished
          print "You have finished the plan for today. Want to review your record? (y/n) "
          Manager.review_recording if STDIN.gets.chomp == "y"
        end
      else
        if Manager.get_plan.any? && options[:noplan]
          print "Delete your plan and start without plan? (y/n) "
          STDIN.gets.chomp == "y" ? Manager.get_plan.destroy_all : return
        end
        if Manager.get_plan.empty? && !options[:noplan]
          print "No plans are created."
          return
        end

        Manager.start_recording
      end
    end

    desc "finish", "finish recording"
    def finish
      if Manager.get_plan.any?
        puts "You don't have to use finish command when you have a plan."
        return
      end

      latest = Task.order(:actual_start).last
      latest.update actual_duration: (Time.zone.now - latest.actual_start) / 60
    end
  end
end

Zatsu::Command.start ARGV