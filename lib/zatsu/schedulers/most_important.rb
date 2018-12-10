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

    def schedule_tasks_without_start task_objects, busy
      result = []
      # put Most Important TaskModels (MITs) at first
      sorted_objs = Hash[ task_objects.sort_by { |k, v| v[:custom][:importance] ? -v[:custom][:importance] : 0 } ]

      sorted_objs.each do |name, obj|
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
            result << Task.new(
              name: name,
              estimated_duration: obj[:estimated_duration],
              estimated_start: st,
            )
            # tm.set_custom_fields task[:custom]

            (i-len+1).upto(i) do |n|
              raise "Auto Scheduling Conflict: #{name} and #{busy[n]}" if busy[n]
              busy[n] = name
            end

            break
          end
        end
      end

      [result, busy]
    end

  end
end