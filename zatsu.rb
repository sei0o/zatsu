#!/usr/bin/ruby
require 'thor'
require 'csv'
require 'active_record'
require 'active_support'
require_relative './dsl'
require_relative './task'

ActiveRecord::Base.establish_connection adapter: :sqlite3, database: './log.db'
Time.zone = 'Asia/Tokyo'

module Zatsu
  PLAN_MAX_MINUTES = 30 * 60

  module Manager
    module_function

    def create_plan hash
      tasks = DSL.parse File.read("generate.rb"), hash
      schedule_tasks tasks
    end

    def get_plan
      Task.where(estimated_start: Time.zone.now.all_day).order(:estimated_start)
    end

    def show_status
      puts "Est.  Act.  Est.  Act.  Name"
      Manager.get_plan.each do |t|
        puts "#{t.estimated_start.localtime.strftime('%R').ljust(5)} #{t.actual_start&.localtime&.strftime('%R')&.ljust(5) || '     '} #{t.estimated_duration.to_s.rjust(5)} #{t.actual_duration.to_s.rjust(5)} #{t.name}"
      end
    end

    def schedule_tasks tasks
      busy = Array.new PLAN_MAX_MINUTES
      scheduled_tasks   = tasks.select { |n, t| t[:scheduled_start] }
      unscheduled_tasks = tasks.select { |n, t| !t[:scheduled_start] }

      scheduled_tasks.each do |name, task|
        st = Time.zone.now.change hour: task[:scheduled_start][:hour], min: task[:scheduled_start][:min], sec: 0
        Task.create(
          name: name,
          estimated_duration: task[:estimated_duration],
          scheduled_start: st,
          estimated_start: st
        )

        (task[:scheduled_start][:hour] * 60).step(task[:scheduled_start][:min]) do |i|
          raise "Conflict: #{name} and #{busy[i]}" if busy[i]
          busy[i] = name
        end
      end
      # 最初と最後のタスクぐらいルーチン化されているはずなのでそれより外の領域は削る
      busy.each_with_index do |val, i|
        break if val
        busy[i] = "No Task"
      end
      busy.reverse_each.with_index do |val, i|
        break if val
        busy[i] = "No Task"
      end

      unscheduled_tasks.each do |name, task|
        # とりあえず愚直にfirst-fit
        len = 1
        busy.each_cons(2).with_index do |prev, cur, i|
          if !prev && cur
            len = 1
          elsif prev && !cur
            len = 1
          else
            len += 1
            if !cur && len == task[:estimated_duration] # enough free time
              st = Time.zone.now.change hour: (i-len+1) / 60, min: (i-len+1) % 60, sec: 0
              Task.create(
                name: name,
                estimated_duration: task[:estimated_duration],
                estimated_start: st
              )
              (i-len+1).step(i) do |n|
                raise "Auto Scheduling Conflict: #{name} and #{busy[n]}" if busy[n]
                busy[n] = name
              end
            end
          end
        end
      end
    end

    def start_recording
    end

    def finish_recording
    end
  end

  class Command < Thor
    package_name 'zatsu'
    default_command :switch

    desc "plan [arg1:val1, ...]", "plan your schedule for today"
    def plan *args
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
      # show rest task
    end
  end
end

Zatsu::Command.start ARGV