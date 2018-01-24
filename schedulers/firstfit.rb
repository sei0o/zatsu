module Zatsu
  class FirstFit

    def initialize tasks
      @tasks = tasks
    end

    def schedule
      busy = Array.new 30 * 60
      scheduled_tasks   = @tasks.select { |n, t| t[:scheduled_start] }
      unscheduled_tasks = @tasks.select { |n, t| !t[:scheduled_start] }

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

  end
end