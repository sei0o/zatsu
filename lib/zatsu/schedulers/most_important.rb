require 'active_record'
require_relative './firstfit'

module Zatsu
  class MostImportant < FirstFit
    # FIXME: Using migrations to create/modify columns instead of having values in
    # the "custom_value" field will make this more efficient
    # class CreateFields < ActiveRecord::Migration[5.0]
    #   def change
    #     add_column :tasks, :importance, :integer, default: 0
    #   end
    # end

    # FIXME: CreateFieldsの内容を実行･revertできるようにする
    # def database_change
    # end

    def schedule_tasks_without_start tasks, busy
      # put Most Important Tasks (MITs) at first
      sorted_tasks = Hash[ tasks.sort_by { |k, v| v[:custom][:importance] ? -v[:custom][:importance] : 0 } ]

      sorted_tasks.each do |name, task|
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
            tm = Task.new(
              name: name,
              estimated_duration: task[:estimated_duration],
              estimated_start: st,
            )
            tm.set_custom_fields task[:custom]
            tm.save!

            (i-len+1).upto(i) do |n|
              raise "Auto Scheduling Conflict: #{name} and #{busy[n]}" if busy[n]
              busy[n] = name
            end

            break
          end
        end
      end

      busy
    end

  end
end