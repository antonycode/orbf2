# frozen_string_literal: true

# == Schema Information
#
# Table name: rules
#
#  id              :integer          not null, primary key
#  name            :string           not null
#  kind            :string           not null
#  package_id      :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  payment_rule_id :integer
#  stable_id       :uuid             not null
#

class Rule < ApplicationRecord
  include PaperTrailed
  RULE_TYPE_MULTI_ENTITIES = "multi-entities"
  RULE_TYPE_ACTIVITY = "activity"
  RULE_TYPE_PACKAGE = "package"
  RULE_TYPE_PAYMENT = "payment"
  RULE_TYPE_ZONE = "zone"


  RULE_TYPES = [
    RULE_TYPE_PAYMENT, RULE_TYPE_ACTIVITY,
    RULE_TYPE_PACKAGE, RULE_TYPE_MULTI_ENTITIES,
    RULE_TYPE_ZONE
  ].freeze

  belongs_to :package, optional: true, inverse_of: :rules
  belongs_to :payment_rule, optional: true, inverse_of: :rule

  has_many :formulas, dependent: :destroy, inverse_of: :rule
  has_many :decision_tables, dependent: :destroy, inverse_of: :rule

  accepts_nested_attributes_for :formulas, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :decision_tables, reject_if: :all_blank, allow_destroy: true

  validates :kind, presence: true, inclusion: {
    in:      RULE_TYPES,
    message: "%{value} is not a valid see #{RULE_TYPES.join(',')}"
  }
  validates :name, presence: true
  validates :formulas, length: { minimum: 1 }, unless: :multi_entities_kind?
  validate :formulas, :formulas_are_coherent

  validate :formulas, :package_formula_uniqness

  def activity_kind?
    kind == RULE_TYPE_ACTIVITY
  end

  def package_kind?
    kind == RULE_TYPE_PACKAGE
  end

  def payment_kind?
    kind == RULE_TYPE_PAYMENT
  end

  def multi_entities_kind?
    kind == RULE_TYPE_MULTI_ENTITIES
  end

  def zone_kind?
    kind == RULE_TYPE_ZONE
  end

  def rule_type
    @rule_type ||= RuleTypes.from_rule(self)
  end

  def kind=(new_kind)
    @rule_type = nil
    super
  end

  def to_facts
    facts = {}
    formulas.each { |formula| facts[formula.code] = formula.expression }
    facts
  end

  def formulas_are_coherent
    @solver ||= Rules::Solver.new
    @solver.validate_formulas(self) if name
  end

  def formula(code)
    formulas.find { |f| f.code == code }
  end

  # see PaperTrailed
  delegate :project_id, to: :project
  delegate :program_id, to: :project

  def project
    rule_type.project
  end

  def package_formula_uniqness
    rule_type.package_formula_uniqness
  end

  def available_variables
    rule_type.available_variables
  end

  def used_available_variables
    used_variables_for_values
  end

  def used_variables_for_values
    formulas.map(&:values_dependencies).flatten
  end

  def dependencies
    formulas.map(&:dependencies).uniq.flatten
  end

  def available_variables_for_values
    rule_type.available_variables_for_values
  end

  def fake_facts
    rule_type.fake_facts
  end

  def to_unified_h
    { stable_id: stable_id,
      name:      name,
      kind:      kind,
      formulas:  Hash[formulas.map do |formula|
        [formula.code, { description: formula.description, expression: formula.expression }]
      end] }
  end

  def to_s
    "Rule##{id}-#{kind}-#{name}"
  end

  def extra_facts(activity, entity_facts)
    return {} if decision_tables.empty?
    entity_and_activity_facts = entity_facts.merge(activity_code: activity.code)
    extra_facts = decision_tables.map { |decision_table| decision_table.extra_facts(entity_and_activity_facts) }.compact
    extra_facts ||= [{}]
    final_facts = extra_facts.reduce({}, :merge)
    raise "#{name} : no value found for #{entity_and_activity_facts} in decision table #{decision_tables.map(&:decision_table).map(&:to_s).join("\n")}" if final_facts.empty?
    final_facts
  end


end
