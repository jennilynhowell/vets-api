class AddHealthAccountBeta < ActiveRecord::Migration
  def change
    create_table :beta_registrations do |t|
      t.string :user_uuid, null: false
      t.string :feature, null: false
      t.timestamps null: false
    end

    add_index :beta_registrations, [:user_uuid, :feature], unique: true
  end
end
