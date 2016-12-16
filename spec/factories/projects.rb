# == Schema Information
#
# Table name: projects
#
#  id         :integer          not null, primary key
#  name       :string           not null
#  dhis2_url  :string           not null
#  user       :string
#  password   :string
#  bypass_ssl :boolean          default(FALSE)
#  boolean    :boolean          default(FALSE)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :project do
    name Faker::Address.country
    dhis2_url Faker::Internet.url
    user Faker::Internet.user_name
    password Faker::Internet.password(8)
    bypass_ssl false
  end
end