# == Schema Information
#
# Table name: packages
#
#  id                         :integer          not null, primary key
#  name                       :string           not null
#  data_element_group_ext_ref :string           not null
#  frequency                  :string           not null
#  project_id                 :integer
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#

class Package < ApplicationRecord
  FREQUENCIES = %w(monthly quarterly).freeze
  belongs_to :project
  has_many :package_entity_groups
  has_many :package_states
  has_many :states, through: :package_states
  has_many :rules
  validates :name, presence: true, length: { maximum: 230 }
  # validates :states, presence: true
  validates :frequency, presence: true, inclusion: {
    in:      FREQUENCIES,
    message: "%{value} is not a valid see #{FREQUENCIES.join(',')}"
  }

  accepts_nested_attributes_for :states

  attr_accessor :invoice_details

  def apply_for(entity)
    package_entity_groups.any? { |group| entity.groups.include?(group.organisation_unit_group_ext_ref) }
  end

  def for_frequency(frequency_to_apply)
    frequency_to_apply == frequency
  end

  def package_rule
    rules.find { |r| r.kind == "package" }
  end

  def activity_rule
    rules.find { |r| r.kind == "activity" }
  end

  def create_data_element_group(data_element_ids)
    deg = [
      { name:          name,
        short_name:    name[0..49],
        code:          name[0..49],
        display_name:  name,
        data_elements: data_element_ids.map do |data_element_id|
          { id: data_element_id }
        end }
    ]
    dhis2 = project.dhis2_connection
    dhis2.data_element_groups.create(deg)
    dhis2.data_element_groups.find_by(name: name)
  end

  def create_package_entity_groups(entity_group_ids)
    dhis2 = project.dhis2_connection
    organisation_unit_groups = dhis2.organisation_unit_groups.find(entity_group_ids)

    organisation_unit_groups.map do |organisation_unit_group|
      {
        name:                            organisation_unit_group.display_name,
        organisation_unit_group_ext_ref: organisation_unit_group.id
      }
    end
  end
end
