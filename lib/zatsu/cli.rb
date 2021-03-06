require 'thor'
require 'yaml'
require 'rainbow'
require_relative './manager'
require_relative './util'

module Zatsu
  class CLI < Thor
    package_name 'zatsu'
    default_command :switch

    desc "genedit group_name", "edit generator"
    def genedit group_name
      system "code #{ZATSU_DIR}/generators/#{group_name}.rb"
    end
    
    desc "plan [arg1:val1, ...] [--ignore group...]", "plan your schedule for today"
    option :ignore, type: :array, aliases: :i
    def plan *args
      return if Manager.get_plan.any? &&
        !Util::confirm('A recording based on a plan has already started. Would you like to delete the current plan and create new one?')

      return if Manager.recording? &&
        !Util::confirm("A recording has already started. Still would you like to create a new plan (it will be appended to your record) ?")

      hash = {}
      args.each do |arg|
        hash[arg.split(":")[0]] = arg.split(":")[1]
      end

      Manager.get_plan.destroy_all
      start_time = Manager.recording? ? Time.zone.now : nil
      plan = Manager.create_plan hash, options["ignore"] || [], start_time

      Manager.show_plan plan

      return unless confirm "Start recording with this plan?"
      Manager.save_plan plan
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
        Manager.switch_task task_name

        if !options[:noplan] && !Manager.recording? && Util::confirm("You have finished the plan for today. Want to review your record?")
          Manager.review_recording
        end
      else
        if Manager.get_plan.any? && options[:noplan]
          Util::confirm("Delete your plan and start without plan?") ? Manager.get_plan.destroy_all : return
        end
        if Manager.get_plan.empty? && !options[:noplan]
          print "No plans are created."
          return
        end

        puts Rainbow(Util::config["start_message"].sample).yellow

        Manager.start_recording task_name
      end

      Util::command_succeeded
    end

    desc "finish", "finish recording"
    def finish
      latest = TaskModel.order(:actual_start).last
      latest.update actual_duration: (Time.zone.now - latest.actual_start) / 60
    end

    desc "review", "review your day"
    def review
      if Manager.recording? || (Manager.get_plan.empty? && Manager.get_record.empty?)
        puts "You haven't finished your recording."
        return
      end

      Manager.review_recording
    end

    desc "edit (task #) [--name (name)] [--actual-start 9:39] [--actual-duration 40] [--estimated-start 10:10] [--estimated-duration 30] [-f importance:3 tags:dev,zatsu ...]", "edit your task"
    option :name, aliases: :n
    option :"estimated-start", aliases: :a
    option :"estimated-duration", aliases: :b
    option :"actual-start", aliases: :c # FIXME: bad shorthand options
    option :"actual-duration", aliases: :d
    option :fields, aliases: :f, type: :hash
    def edit idx
      Manager.edit_task idx, options
    end

    desc "bulkedit", "edit your tasks using external editor"
    def bulkedit
      if TaskModel.today.empty?
        puts "You currently have no tasks"
        return
      end

      Manager.export_to_csv "#{ZATSU_DIR}/record.csv"
      system "vim #{ZATSU_DIR}/record.csv"
      Manager.update_from_csv "#{ZATSU_DIR}/record.csv"
    end

    desc "rename (task #) (name)", "rename your task"
    def rename idx, name
      tasks = TaskModel.today
      tasks[idx.to_i][:name] = name
      tasks[idx.to_i].save

      Util::command_succeeded
    end

    desc "combine [task #] [task #] (name)", "combine tasks between the two tasks to a single task"
    def combine idx_from, idx_to, name = nil
      tasks = TaskModel.today
      t_from = tasks[idx_from.to_i]
      tt = tasks[(idx_from.to_i)..(idx_to.to_i)]

      # For now simply sum up the durations of the tasks
      # FIXME: 間に空き時間があればそれも足すべきなのだろうか
      new_task = TaskModel.create(
        name: name,
        estimated_start: t_from.estimated_start,
        estimated_duration: tt.inject(0) {|m, x| m + (x.estimated_duration || 0)},
        actual_start: t_from.actual_start,
        actual_duration: tt.inject(0) {|m, x| m + (x.actual_duration || 0)}
      )
      
      tt.each do |x|
        TaskModel.destroy x.id
      end

      Util::command_succeeded
    end

    desc "split [task #] [length] [--tail or --head]", "split a task into two subsequent tasks"
    option :tail, aliases: :t
    option :head, aliases: :h
    def split idx, len
      Manager.split_task idx.to_i, !!options["head"], len.to_i
      Util::command_succeeded
    end

    desc "migrate", "migrate db files"
    def migrate
      Zatsu.migrate_db
    end
  end
end