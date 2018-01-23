class CreateTasks < ActiveRecord::Migration[5.0]
  def change
    create_table :tasks do |t|
      t.string :name, null: false, unique: true
      t.integer :estimated_duration, null: false, default: 0
      t.integer :actual_duration
      t.datetime :scheduled_start
      t.datetime :estimated_start
      t.datetime :actual_start

      t.timestamps
    end
  end
end