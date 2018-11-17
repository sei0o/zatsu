require 'thor'
require 'csv'
require 'active_record'
require 'active_support'
require_relative './zatsu/dsl'
require_relative './zatsu/task'
require_relative './zatsu/schedulers/firstfit'
require_relative './zatsu/schedulers/most_important'
require_relative './zatsu/setup'
require_relative './zatsu/const'

module Zatsu
  module Manager
    module_function

    def create_plan hash
      parsed = {}
      Dir.glob "#{ZATSU_DIR}/generators/*.rb" do |genf|
        groupname = genf[0..-4].to_sym # the filename without extension ".rb"
        parsed.merge! DSL.parse File.read(genf), groupname, hash
      end
      schedule_tasks parsed
    end

    def get_plan
      Task.where(estimated_start: Time.zone.now.all_day).order(:estimated_start)
    end

    def get_record
      Task.where(actual_start: Time.zone.now.all_day).order(:actual_start)
    end

    def show_status
      puts "     E/Sta A/Sta E/Dur A/Dur Name"
      tasks = get_plan
      tasks = get_record if tasks.empty?
      tasks.each_with_index do |t, i|
        custom = t[:custom].empty? ? '' : t.custom_fields.map { |k,v| "#{k[0..1]}:#{v}" }.join("/")
        custom = "<#{custom}> " unless custom.empty?
        acdr = t&.actual_duration&.to_s&.rjust(5) || '     '
        acdr = "#{((Time.zone.now - t.actual_start) / 60).floor}+".rjust(5) if t == tasks.last && !t.actual_duration
        puts "[#{i.to_s.rjust(2)}] #{t&.estimated_start&.localtime&.strftime('%R')&.ljust(5) || '     '} #{t.actual_start&.localtime&.strftime('%R')&.ljust(5) || '     '} #{t&.estimated_duration&.to_s&.rjust(5) || '     '} #{acdr} #{custom}#{t.name}"
      end
    end

    def schedule_tasks tasks
      # FirstFit.new(tasks).schedule
      MostImportant.new(tasks).schedule
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
      if get_plan.any?
        File.write "#{ZATSU_DIR}/record.csv", generate_csv(get_plan)
      else
        File.write "#{ZATSU_DIR}/record.csv", generate_csv(get_record)
      end
      system "vim #{ZATSU_DIR}/record.csv"
      update_from_csv "#{ZATSU_DIR}/record.csv"

      # suggest add new tasks to routine
      new_tasks = []
      get_record.each do |t|
        new_tasks << t.name if Task.where(name: t.name).count == 1
      end
      new_tasks.each do |t|
        print "Save '#{t}' as a routine task? (y/n)"
        if STDIN.gets.chomp == 'y'
          File.open "#{ZATSU_DIR}/generators/routine.rb", 'a' do |f|
            f.puts "task '#{t}'"
          end
        end
      end
    end

    def generate_csv tasks
      csv = ['est,act,name']
      tasks.each do |t|
        csv << "#{t&.estimated_start&.localtime&.strftime('%R')&.ljust(5) || '    '},#{t.actual_start&.localtime&.strftime('%R')&.ljust(5) || '    '},#{t.name}"
      end
      # add FINISH task　(to adjust actual_duration of the last task)
      csv << "-----,#{(tasks[-1].actual_start + tasks[-1].actual_duration * 60).localtime.strftime('%R')},FINISH" if tasks[-1].actual_duration
      csv.join "\n"
    end

    def update_from_csv filename
      records = CSV.table filename

      get_plan.destroy_all
      get_record.destroy_all

      tasks = records.map do |r|
        {
          est: r[:est] =~ /\d\d:\d\d/ ? Time.zone.now.change(hour: r[:est].strip.split(':')[0].to_i, min: r[:est].strip.split(':')[1].to_i, sec: 0) : nil,
          act: Time.zone.now.change(hour: r[:act].strip.split(':')[0].to_i, min: r[:act].strip.split(':')[1].to_i, sec: 0),
          name: r[:name].strip,
        }
      end

      tasks.each_cons(2) do |cur, nx|
        break if cur[:name] == 'FINISH'
        Task.create(
          estimated_start: cur[:est],
          actual_start: cur[:act],
          estimated_duration: nx[:est] && cur[:est] ? (nx[:est] - cur[:est]) / 60 : nil,
          actual_duration: (nx[:act] - cur[:act]) / 60,
          name: cur[:name]
        )
      end
    end

    def recording?
      (get_plan.any? && get_plan[0].actual_start && !get_plan[-1].actual_duration) || # with plan
      (get_plan.empty? && Task.exists?(actual_start: Time.zone.now.all_day, actual_duration: nil)) # without plan
    end
  end

  class Command < Thor
    package_name 'zatsu'
    default_command :switch

    desc "genedit group_name", "edit generator"
    def genedit group_name
      system "code #{ZATSU_DIR}/generators/#{group_name}.rb"
    end

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

    desc "review", "review your day"
    def review
      if Manager.recording? || (Manager.get_plan.empty? && Manager.get_record.empty?)
        puts "You haven't finished your recording."
        return
      end

      Manager.review_recording
    end

    desc "rename (task #) (name)", "rename your task"
    def rename idx, name
      tasks = Manager.get_plan
      tasks = Manager.get_record if tasks.empty?
      tasks[idx.to_i][:name] = name
      tasks[idx.to_i].save

      Manager.show_status
    end

    desc "migrate", "migrate db files"
    def migrate
      Zatsu.migrate_db
    end
  end
end