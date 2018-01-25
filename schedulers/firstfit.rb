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

        (task[:scheduled_start][:hour] * 60 + task[:scheduled_start][:min]).upto(task[:scheduled_start][:hour] * 60 + task[:scheduled_start][:min] + task[:estimated_duration] - 1) do |i|
          raise "Conflict: #{name} and #{busy[i]}" if busy[i]
          busy[i] = name
        end
      end
      # 最初と最後のタスクぐらいルーチン化されているはずなのでそれより外の領域は削る
      busy.each_with_index do |val, i|
        break if val
        busy[i] = "No Task"
      end
      busy.each_with_index.reverse_each do |val, i|
        break if val
        busy[i] = "No Task"
      end

      unscheduled_tasks.each do |name, task|
        len = 0
        busy.each_cons(2).with_index do |(prev, cur), i|
          next if cur
          if prev
            len = 0
            next
          end

          len += 1
          if len == task[:estimated_duration] # enough free time
            st = Time.zone.now.change hour: (i-len+1) / 60, min: (i-len+1) % 60, sec: 0
            Task.create(
              name: name,
              estimated_duration: task[:estimated_duration],
              estimated_start: st
            )

            (i-len+1).upto(i) do |n|
              raise "Auto Scheduling Conflict: #{name} and #{busy[n]}" if busy[n]
              busy[n] = name
            end
          end
        end
      end

      len = 1
      busy.each_cons(2).with_index do |(prev, cur), i|
        if prev && !cur # start of buffer
          len = 1
        elsif !prev && cur # end of buffer
          st = Time.zone.now.change hour: (i-len+1) / 60, min: (i-len+1) % 60, sec: 0
          Task.create(
            name: "(Buffer)",
            estimated_duration: len,
            estimated_start: st
          )
        else
          len += 1
        end
      end
    end

  end
end