require 'active_record'

module Zatsu
  class MostImportant
    # FIXME: Using migrations to create/modify columns instead of having values in
    # the "custom_value" field will make this more efficient
    # class CreateFields < ActiveRecord::Migration[5.0]
    #   def change
    #     add_column :tasks, :importance, :integer, default: 0
    #   end
    # end

    def initialize tasks
      @tasks = tasks
    end

    # FIXME: CreateFieldsの内容を実行･revertできるようにする
    # def database_change
    # end

    def schedule
      estimate_duration

      busy = Array.new 30 * 60 # 30時間 * 60分 = 1800分を塗りつぶしていくイメージ
      scheduled_tasks   = @tasks.select { |n, t| t[:scheduled_start] }
      unscheduled_tasks = @tasks.select { |n, t| !t[:scheduled_start] }

      busy = schedule_tasks_with_start scheduled_tasks, busy

      # 最初と最後のタスクぐらいルーチン化されているはずなのでそれより外の領域は削る
      # FIXME: ↑ほんまか？, 思い切ってAM 2時ぐらいで固定して切ってもいいかもしれない
      busy.each_with_index do |val, i|
        break if val
        busy[i] = "No Task"
      end
      busy.each_with_index.reverse_each do |val, i|
        break if val
        busy[i] = "No Task"
      end

      busy = schedule_tasks_without_start unscheduled_tasks, busy

      buf_start = nil
      busy.each_with_index do |cur, i|
        if cur
          next unless buf_start

          st = Time.zone.now.change hour: buf_start / 60, min: buf_start % 60, sec: 0
          buf_len = i - buf_start
          Task.create(
            name: "(Buffer)",
            estimated_duration: buf_len,
            estimated_start: st
          )

          buf_start = nil
        else
          buf_start = i unless buf_start
        end
      end
    end

    def schedule_tasks_with_start tasks, busy
      tasks.each do |name, task|
        ss_h = task[:scheduled_start][:hour]
        ss_m = task[:scheduled_start][:min]

        st = Time.zone.now.change hour: ss_h, min: ss_m, sec: 0
        Task.create(
          name: name,
          estimated_duration: task[:estimated_duration],
          scheduled_start: st,
          estimated_start: st
        )

        (ss_h * 60 + ss_m).upto(ss_h * 60 + ss_m + task[:estimated_duration] - 1) do |i|
          raise "Conflict: #{name} and #{busy[i]}" if busy[i]
          busy[i] = name
        end
      end

      busy
    end

    def schedule_tasks_without_start tasks, busy
      tasks.each do |name, task|
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

      busy
    end

    def estimate_duration
      @tasks.each do |name, info|
        if !info[:estimated_duration] || info[:estimated_duration][0] == :auto
          logs = Task.where(name: info[:name]).where.not(actual_duration: nil).last(5)
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