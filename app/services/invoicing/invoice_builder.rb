module Invoicing
  class InvoiceBuilder
    attr_reader :solver, :project_finder, :tarification_service

    def initialize(project_finder, tarification_service = Tarification::MockTarificationService.new)
      @solver = Rules::Solver.new
      @project_finder = project_finder
      @tarification_service = tarification_service
    end

    def generate_yearly_entity_invoice(entity, analytics_service, date)
      year = Periods.year_month(date).to_year
      project = project_finder.find_project(year.end_date)
      activity_results = calculate_activity_results(
        analytics_service,
        project,
        entity,
        year.end_date,
        "yearly"
      )

      package_results = calculate_package_results(activity_results)

      payment_result = nil
      if package_results.any?
        payment_result = calculate_payments(project, entity, package_results)
      end
      invoice = Invoicing::Invoice.new(date, entity, project, activity_results, package_results, payment_result)
      invoice.dump_invoice
      invoice
    end

    def generate_quarterly_entity_invoice(entity, analytics_service, date)
      year_quarter = Periods.year_month(date.to_date.end_of_month).to_quarter

      quarter_details_results = {}
      quarterly_package_results = {}
      year_quarter.months.each do |year_month|
        project = project_finder.find_project(year_month.end_date)
        begin
          activity_monthly_results = calculate_activity_results(
            analytics_service,
            project,
            entity,
            year_month.end_date,
            "monthly"
          )
          quarter_details_results[year_month.end_date] = activity_monthly_results
          quarterly_package_results[year_month.end_date] = calculate_package_results(activity_monthly_results)
        rescue => e
          Rails.logger.info "WARN : generate_monthly_entity_invoice : #{e.class } : #{e.message} : \n#{e.backtrace.join("\n").to_s}"
        end
      end

      quarter_entity_results = calculate_package_results(quarter_details_results.values.flatten)
      quarter_entity_results.each { |r| r.frequency = "quarterly" }

      project = project_finder.find_project(year_quarter.end_date)
      activity_results = calculate_activity_results(
        analytics_service,
        project,
        entity,
        year_quarter.end_date,
        "quarterly"
      )

      package_results = calculate_package_results(activity_results)
      package_results.concat(quarter_entity_results)
      payment_result = nil
      if package_results.any?
        payment_result = calculate_quarterly_payments(project, entity, package_results)
      end
      invoice = Invoicing::Invoice.new(date, entity, project, activity_results, package_results, payment_result)
      invoice.dump_invoice
      invoice
    end

    def generate_monthly_entity_invoice(entity, analytics_service, date)
      date = date.to_date.end_of_month
      project = project_finder.find_project(date)

      begin
        activity_results = calculate_activity_results(
          analytics_service,
          project,
          entity,
          date,
          "monthly"
        )
        raise InvoicingError, "should have at least one activity_results" if activity_results.empty?
        package_results = calculate_package_results(activity_results)
        raise InvoicingError, "should have at least one package_results" if package_results.empty?
        return Invoicing::Invoice.new(date, entity, project, activity_results, package_results, nil)
      rescue => e
        Invoicing::Invoice.new(date, entity, project, activity_results, package_results, nil).dump_invoice
        raise e
      end
    end

    def generate_monthly_payments(project, entity, invoices, invoicing_request)
      monthly_payments_invoices = []
      invoicing_request.quarter_dates.each_with_index do |month, index|
        monthly_invoices = invoices.flatten.select { |invoice| invoice.date == month }
        monthly_rules = project.payment_rules.select(&:monthly?).select { |p| p.apply_for?(entity) }

        monthly_rules.map do |payment_rule|

          all_package_results = monthly_invoices.empty? ? [] : monthly_invoices.flat_map(&:package_results).select { |pr|
            pr.frequency.nil?
          }

          package_results = all_package_results.select do |pr|
            payment_rule.packages.map(&:name).include?(pr.package.name)
          end

          variables = payment_variables(payment_rule, invoices, month)
          variables = variables.merge(payment_previous_variables(payment_rule, monthly_payments_invoices))

          extra_facts = { month_in_quarter: index + 1 }

          package_facts_and_rules = {}
          package_results.each do |package_result|
            Rails.logger.info "results for #{package_result.package.name}"
            package_facts_and_rules = package_facts_and_rules.merge(package_result.solution)
          end


          payment_rule.packages.each do |package|
            package.package_rule.formulas.each do |formula|
              Rails.logger.info " #{package.name} #{formula.code} default to 0" unless package_facts_and_rules[formula.code]
              package_facts_and_rules[formula.code] ||= 0
            end
          end
          payment_facts = payment_rule.rule.formulas.each_with_object({}) do |formula, hash|
            hash[formula.code.to_sym] = string_template(formula, variables)
          end
          package_facts_and_rules = package_facts_and_rules.merge(payment_facts)
          package_facts_and_rules = package_facts_and_rules.merge(extra_facts)
          payment_result = PaymentResult.new(
            payment_rule,
            solver.solve!("payment rule", package_facts_and_rules, true),
            package_facts_and_rules
          )

          monthly_payments_invoices.push(
            Invoice.new(
              monthly_invoices.first.date,
              entity,
              monthly_invoices.first.project,
              [],
              [],
              payment_result
            )
          )
        end
      end
      monthly_payments_invoices
    end

    private

    def calculate_quarterly_payments(project, entity, all_package_results)
      project.payment_rules.select(&:quarterly?).each do |payment_rule|
        package_results = all_package_results.select do |pr|
          payment_rule.packages.map(&:name).include?(pr.package.name)
        end
        # Rails.logger.info "********* calculate_payments : #{package_results} #{payment_rule.apply_for?(entity)} #{package_results.size} #{payment_rule.packages.size}"

        next unless payment_rule.apply_for?(entity)
        next unless package_results.size >= payment_rule.packages.size

        package_facts_and_rules = {}
        package_results.each do |package_result|
          package_facts_and_rules = package_facts_and_rules.merge(package_result.solution)
        end
        package_facts_and_rules = package_facts_and_rules.merge(payment_rule.rule.to_facts)

        return PaymentResult.new(
          payment_rule,
          solver.solve!("payment rule", package_facts_and_rules, false),
          package_facts_and_rules
        )
      end
      nil
    end

    def payment_previous_variables(payment_rule, monthly_payments_invoices)
      payment_rule.rule.formulas.each_with_object({}) do |formula, variables|
        vals = solution_to_array(monthly_payments_invoices.select { |i| i.payment_result.payment_rule == payment_rule }.map(&:payment_result), formula.code)
        vals = vals.reject(&:nil?).reject(&:empty?)
        variables["#{formula.code}_previous_values".to_sym] = vals.any? ? vals.join(" , ") : "0"
      end
    end

    def payment_variables(payment_rule, invoices, month)
      payment_rule.packages.each_with_object({}) do |package, variables|
        previous_monthly_invoices = invoices.flatten.select { |invoice| invoice.date <= month }
        previous_months_values = previous_monthly_invoices.flat_map(&:package_results)

        package.package_rule.formulas.each do |formula|
          previous_months_values_for_package = previous_months_values.select { |pr| pr.package == formula.rule.package }.select { |pr| pr.frequency.nil? }
          vals = solution_to_array(previous_months_values_for_package, formula.code).reject(&:nil?).reject(&:empty?)
          variables["#{formula.code}_values".to_sym] = vals.join(" , ") || "0"
        end
      end
    end

    def calculate_activity_results_monthly(entity, date, package, activity, values)
      activity_tarification_facts = tarification_service.tarif(entity, date, activity, values)
      year_month = Periods.year_month(date)
      entity_facts_and_decision_tables = package.activity_rule.extra_facts(activity, entity.facts)

      facts_and_rules = {}
                        .merge(entity_facts_and_decision_tables)
                        .merge(package.activity_rule.to_facts)
                        .merge(activity_tarification_facts)
                        .merge(values.to_facts)
                        .merge(
                          quarter_of_year: year_month.to_quarter.quarter,
                          month_of_year:   year_month.month
                        )
                        .merge("activity_name" => "'#{activity.name.tr("'", ' ')}'")

      package.activity_rule.formulas.each do |formula|
        template_values = values.variables.each_with_object({}) { |(k, v), h| h[k.to_sym] = to_string(v) }
        facts_and_rules[formula.code] = string_template(formula, template_values)
      end

      solution = solver.solve!(activity.name.to_s, facts_and_rules)

      ActivityResult.new(package, activity, solution, date, facts_and_rules)
    end

    def calculate_package_results(activity_results)
      activity_results.group_by(&:package).map do |package, results|
        variables = results.first.solution.each_with_object({}) do |(k,_), hash|
          hash["#{k}_values".to_sym] = solution_to_array(results, k).join(" , ")
        end

        facts_and_rules = package.package_rule.formulas.each_with_object({ remoteness_bonus: 0 }) do |formula, hash|
          hash[formula.code] = string_template(formula, variables)
        end
        solution_package = solver.solve!("sum activities for #{package.name}", facts_and_rules)

        PackageResult.new(package, solution_package, facts_and_rules)
      end
    end

    def calculate_activity_results(analytics_service, project, entity, date, frequency)
      selected_packages = project.packages.select do |package|
        package.for_frequency(frequency) && package.apply_for(entity)
      end
      Rails.logger.info "No package for #{entity.name} #{entity.groups} #{frequency} vs supported groups #{project.packages.flat_map(&:package_entity_groups).map(&:organisation_unit_group_ext_ref).uniq}" if selected_packages.empty?
      selected_packages.each_with_object([]) do |package, array|
        analytics_service.activity_and_values(package, date).each do |activity, values|
          array.push(calculate_activity_results_monthly(entity, date, package, activity, values))
        end
      end
    end

    def solution_to_array(results, k)
      results.map do |r|
        begin
          BigDecimal.new(r.solution[k])
          format("%.10f", r.solution[k])
        rescue
          nil
        end
      end
    end

    def to_string(array)
      array.map do |r|
        format("%.10f", r)
      end.join(" , ")
    end

    def string_template(formula, variables)
      return formula.expression % variables
    rescue KeyError => e
      Rails.logger.info "problem with expression #{e.message} : #{formula.code} : #{formula.expression} #{JSON.pretty_generate(variables)}"
      raise e
    end
  end
end
