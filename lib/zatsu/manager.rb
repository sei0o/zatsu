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
      task.set_custom_fields task.custom_fields.merge opts["fields"] if opts["fields"]

      if opts["actual-start"] == "none"
        task.actual_start = nil
      elsif opts["actual-start"]
        task.actual_start = Util.ct opts["actual-start"]
      end
      if opts["estimated-start"] == "none"
        task.estimated_start = nil
      elsif opts["estimated-start"]
        task.estimated_start = Util.ct opts["estimated-start"]
      end
      if opts["actual-duration"] == "none"
        task.actual_duration = nil
      elsif opts["actual-duration"]
        task.actual_duration = opts["actual-duration"].to_i
      end
      if opts["estimated-duration"] == "none"
        task.estimated_duration = nil
      elsif opts["estimated-duration"]
        task.estimated_duration = opts["estimated-duration"].to_i
      end
      
      task.save

      show_status
    end

    def start_recording name = nil
      if get_plan.any? && !name
        get_plan[0].update actual_start: Time.zone.now, name: name
      else
        Task.create actual_start: Time.zone.now, name: name
      end
    end

    def review_recording
      export_to_csv "#{ZATSU_DIR}/record.csv"
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

    def export_to_csv filename
      File.write filename, generate_csv(get_plan.any? ? get_plan : get_record)
    end

    def parse_time prev_time, str
      if str =~ /\d\d:\d\d/
        return Time.zone.now.change(
          hour: str.strip.split(':')[0].to_i,
          min: str.strip.split(':')[1].to_i, 
          sec: 0)
      end
      
      if str =~ /d\d+/
        return prev_time + str.strip[1..-1].to_i * 60
      end

      nil
    end

    def update_from_csv filename
      records = CSV.table filename

      Task.today.destroy_all

      raise "The first task must not have relative time." if records[0][:est] =~ /\+\d+/ || records[0][:act] =~ /\+\d+/

      tasks = []
      records.each do |cur|
        last = tasks.last

        p cur
        p parse_time(last&.actual_start, cur[:act])
        est = parse_time(last&.estimated_start, cur[:est])
        act = parse_time(last&.actual_start, cur[:act])
        
        last.estimated_duration = (est - last.estimated_start) / 60 if est && last&.estimated_start
        last.actual_duration = (act - last.actual_start) / 60 if act && last&.actual_start
        last&.save
        
        break if cur[:name] == 'FINISH'
        tasks << Task.new(
          estimated_start: est,
          actual_start: act,
          name: cur[:name]&.strip
        )
      end

      tasks.last.save
    end

    def recording?
      Task.exists?(actual_start: Time.zone.now.all_day, actual_duration: nil)
    end
  end
end