class AddCustomFieldsToTasks < ActiveRecord::Migration[5.0]
  def change
    add_column :tasks, :custom, :string, default: ""
  end
end