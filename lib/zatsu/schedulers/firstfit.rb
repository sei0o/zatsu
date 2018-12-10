require_relative '../task'

module Zatsu
  class FirstFit

    def initialize task_objects
      @task_objects = task_objects
    end

    def schedule
      result = []
      estimate_duration

      busy = Array.new 30 * 60 # 30時間 * 60分 = 1800分を塗りつぶしていくイメージ
      scheduled_tasks   = @task_objects.select { |n, t| t[:scheduled_start] }
      unscheduled_tasks = @task_objects.select { |n, t| !t[:scheduled_start] }

      tasks, busy = schedule_tasks_with_start scheduled_tasks, busy
      result += tasks

      # 最初と最後のタスクぐらいルーチン化されているはずなのでそれより外の領域は削る
      # FIXME: ↑ほんまか？
      busy.each_with_index do |val, i|
        break if val
        busy[i] = "No Task"
      end
      busy.each_with_index.reverse_each do |val, i|
        break if val
        busy[i] = "No Task"
      end

      tasks, busy = schedule_tasks_without_start unscheduled_tasks, busy
      result += tasks

      buf_start = nil
      busy.each_with_index do |cur, i|
        if cur
          next unless buf_start

          st = Time.zone.now.change hour: buf_start / 60, min: buf_start % 60, sec: 0
          buf_len = i - buf_start
          result << Task.new(
            name: "(Buffer)",
            estimated_duration: buf_len,
            estimated_start: st
          )

          buf_start = nil
        else
          buf_start = i unless buf_start
        end
      end

      result
    end

    def schedule_tasks_with_start task_objects, busy
      tasks = []
      task_objects.each do |name, obj|
        ss_h = obj[:scheduled_start][:hour]
        ss_m = obj[:scheduled_start][:min]

        st = Time.zone.now.change hour: ss_h, min: ss_m, sec: 0
        
        tasks << Task.new(
          name: name,
          estimated_duration: obj[:estimated_duration],
          scheduled_start: st,
          estimated_start: st
        )

        (ss_h * 60 + ss_m).upto(ss_h * 60 + ss_m + obj[:estimated_duration] - 1) do |i|
          raise "Conflict: #{name} and #{busy[i]}" if busy[i]
          busy[i] = name
        end
      end

      [tasks, busy]
    end

    def schedule_tasks_without_start task_objects, busy
      tasks = []
      task_objects.each do |name, obj|
        len = 0
        busy.each_cons(2).with_index do |(prev, cur), i|
          next if cur
          if prev
            len = 0
            next
          end

          len += 1
          if len == obj[:estimated_duration] # enough free time
            st = Time.zone.now.change hour: (i-len+1) / 60, min: (i-len+1) % 60, sec: 0
            tasks << Task.new(
              name: name,
              estimated_duration: obj[:estimated_duration],
              estimated_start: st
            )

            (i-len+1).upto(i) do |n|
              raise "Auto Scheduling Conflict: #{name} and #{busy[n]}" if busy[n]
              busy[n] = name
            end
          end
        end
      end

      [tasks, busy]
    end

    def estimate_duration
      @task_objects.each do |name, info|
        if !info[:estimated_duration] || info[:estimated_duration][0] == :auto
          logs = TaskModel.where(name: info[:name]).where.not(actual_duration: nil).last(5)
          if logs.empty?
            info[:estimated_duration] = info[:estimated_duration] ? info[:estimated_duration][1] : 10
          else
            # Use average duration
            info[:estimated_duration] = logs.map(&:actual_duration).inject(:+) / logs.size
          end
        end
      end
    end

  end
end