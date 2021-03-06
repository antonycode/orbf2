module RuleTypes
  class BaseRuleType
    def initialize(rule)
      @rule = rule
    end

    attr_reader :rule
    delegate :package, to: :rule
    delegate :formulas, to: :rule
    delegate :activity_kind?, to: :rule
    delegate :package_kind?, to: :rule
    delegate :multi_entities_kind?, to: :rule
    delegate :payment_kind?, to: :rule
    delegate :decision_tables, to: :rule
    delegate :payment_rule, to: :rule

    def to_fake_facts(states)
      facts = states.map { |state| [state.code.to_sym, "10"] }.to_h
      facts[:quarter_of_year] = 3
      org_unit_facts = decision_tables.flat_map(&:out_headers)
                                      .map { |header| [header.to_sym, "10"] }
                                      .to_h
      facts.merge org_unit_facts
    end

    def package_formula_uniqness
      formula_by_codes = formulas.group_by(&:code)

      formula_by_codes.each do |code, formulas|
        next unless formulas.size > 1
        rule.errors[:formulas] << "Formula's code must be unique,"\
          " you have #{formulas.size} formulas with '#{code}'"
      end
    end
  end
end
