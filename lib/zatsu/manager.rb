require 'csv'
require 'active_record'
require 'active_support'
require_relative './dsl'
require_relative './task'
require_relative './schedulers/firstfit'
require_relative './schedulers/most_important'
require_relative './setup'
require_relative './const'
require_relative './util'

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
      puts "     E/Sta E/Dur A/Sta A/Dur Name"
      # tasks = get_plan
      # tasks = get_record if tasks.empty?
      tasks = Task.today
      tasks.each_with_index do |t, i|
        custom = t[:custom].empty? ? '' : t.custom_fields.map { |k,v| "#{k[0..1]}:#{v}" }.join("/")
        custom = "<#{custom}> " unless custom.empty?
        acdr = t&.actual_duration&.to_s&.rjust(5) || '     '
        acdr = "#{((Time.zone.now - t.actual_start) / 60).floor}+".rjust(5) if t.actual_start && !t.actual_duration
        puts "[#{i.to_s.rjust(2)}] #{t&.estimated_start&.localtime&.strftime('%R')&.ljust(5) || '     '} #{t&.estimated_duration&.to_s&.rjust(5) || '     '} #{t.actual_start&.localtime&.strftime('%R')&.ljust(5) || '     '} #{acdr} #{custom}#{t.name}"
      end
    end

    def schedule_tasks tasks
      # FirstFit.new(tasks).schedule
      MostImportant.new(tasks).schedule
    end

    def switch_task name
      Task.today.each do |t|
        if t.actual_start && !t.actual_duration # doing the task
          t.update actual_duration: (Time.zone.now - t.actual_start) / 60

          # The next task is the one which has not been done yet and has the earliest start
          t_next = Task.where(actual_duration: nil).order(:estimated_start).first
          if t_next && !name
            t_next.update actual_start: Time.zone.now
          else
            # Start the task with the given name immediately
            Task.create actual_start: Time.zone.now, name: name
          end
        end
      end
    end

    def edit_task idx, opts
      task = Task.today[idx.to_i]

      task.name = opts["name"] if opts["name"]
      task.actual_start = Util.ct opts["actual-start"] if opts["actual-start"]
      task.actual_duration = opts["actual-duration"].to_i if opts["actual-duration"]
      task.estimated_start = Util.ct opts["estimated-start"] if opts["estimated-start"]
      task.estimated_duration = opts["estimated-duration"].to_i if opts["estimated-duration"]

      task.set_custom_fields task.custom_fields.merge opts["fields"] if opts["fields"]
      
      task.save

      show_status
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
      update_from_csv "#{ZATSU_DIeR}/record.csv"

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
      Task.exists?(actual_start: Time.zone.now.all_day, actual_duration: nil)
    end
  end
end