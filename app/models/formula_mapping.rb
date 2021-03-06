# == Schema Information
#
# Table name: formula_mappings
#
#  id                 :integer          not null, primary key
#  formula_id         :integer          not null
#  activity_id        :integer
#  external_reference :string           not null
#  kind               :string           not null
#

class FormulaMapping < ApplicationRecord
  include PaperTrailed

  delegate :project_id, to: :formula
  delegate :program_id, to: :formula

  validates :kind, presence: true, inclusion: {
    in:      Rule::RULE_TYPES,
    message: "%{value} is not a valid see #{Rule::RULE_TYPES.join(',')}"
  }

  validates :external_reference, presence: true
  belongs_to :formula, inverse_of: :formula_mappings
  belongs_to :activity

  def names
    if activity
      naming_patterns = activity.project.naming_patterns
      substitutions = substitutions_for(activity)
      dhis2_name = {
        long:  format(naming_patterns[:long], substitutions).strip,
        short: format(naming_patterns[:short], substitutions).strip,
        code:  format(naming_patterns[:code], substitutions).strip
      }
    else
      dhis2_name = {
        long:  formula.code.humanize.strip,
        short: formula.code.humanize.strip,
        code:  formula.code.humanize.strip
      }
    end
    Dhis2Name.new(dhis2_name)
  end

  def substitutions_for(activity)
    {
      state_short_name:    formula.code.humanize,
      raw_activity_code:   activity.code,
      activity_code:       activity.code.humanize,
      activity_name:       activity.name,
      activity_short_name: activity.short_name || activity.name,
      state_code:          formula.code
    }
  end
end
