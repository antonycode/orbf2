# == Schema Information
#
# Table name: dhis2_snapshots
#
#  id                :integer          not null, primary key
#  kind              :string           not null
#  content           :jsonb            not null
#  project_anchor_id :integer
#  dhis2_version     :string           not null
#  year              :integer          not null
#  month             :integer          not null
#  job_id            :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#

class Dhis2Snapshot < ApplicationRecord
  belongs_to :project_anchor

  KINDS = %i[data_elements
             data_element_groups
             organisation_unit_group_sets
             organisation_unit_groups
             organisation_units
             indicators].freeze

  def kind_organisation_units?
    kind.to_sym == :organisation_units
  end

  def kind_organisation_unit_groups?
    kind.to_sym == :organisation_unit_groups
  end

  def kind_organisation_unit_group_sets?
    kind.to_sym == :organisation_unit_group_sets
  end

  def kind_data_elements?
    kind.to_sym == :data_elements
  end

  def kind_data_element_groups?
    kind.to_sym == :data_element_groups
  end

  def kind_indicators?
    kind.to_sym == :indicators
  end

  def snapshoted_at
    Date.parse("#{year}-#{month}-01").end_of_month
  end

  def content_for_id(id)
    item = content.detect { |row| row["table"]["id"] == id }
    item ? item["table"] : nil
  end
end
