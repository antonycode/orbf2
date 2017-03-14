module Invoicing
  class InvoiceBuilder
    attr_reader :solver, :project_finder, :tarification_service

    def initialize(project_finder, tarification_service = Tarification::MockTarificationService.new)
      @solver = Rules::Solver.new
      @project_finder = project_finder
      @tarification_service = tarification_service
    end

    def calculate_activity_results(analytics_service, project, entity, date, frequency)
      selected_packages = project.packages.select do |package|
        package.apply_for(entity) && package.for_frequency(frequency)
      end
      raise "No package for #{entity.name} #{entity.groups} vs supported groups #{project.packages.flat_map(&:entity_groups).uniq}" if selected_packages.empty?
      selected_packages.map do |package|
        analytics_service.activity_and_values(package, date).map do |activity, values|
          calculate_activity_results_monthly(entity, date, frequency, package, activity, values)
        end
      end
    end

    def calculate_activity_results_monthly(entity, date, _frequency, package, activity, values)
      activity_tarification_facts = tarification_service.tarif(entity, date, activity, values)

      facts_and_rules = {}
                        .merge(package.activity_rule.to_facts)
                        .merge("activity_name" => "'#{activity.name.tr("'", ' ')}'")
                        .merge(activity_tarification_facts)
                        .merge(values.to_facts)

      solution = solver.solve!(activity.name.to_s, facts_and_rules)

      ActivityResult.new(package, activity, solution, date)
    end

    def calculate_package_results(activity_results)
      activity_results.flatten.group_by(&:package).map do |package, results|
        variables = {
        }
        results.first.solution.keys.each do |k|
          variables["#{k}_values".to_sym] = solution_to_array(results, k).join(" , ")
        end

        facts_and_rules = {}
        package.package_rule.formulas.each do |formula|
          facts_and_rules[formula.code] = string_template(formula, variables)
        end
        solution_package = solver.solve!("sum activities for #{package.name}", facts_and_rules)

        PackageResult.new(package, solution_package)
      end
    end

    def solution_to_array(results, k)
      results.map do |r|
        begin
          BigDecimal.new(r.solution[k])
          "%.10f" % r.solution[k]
        rescue
          nil
        end
      end
    end

    def string_template(formula, variables)
      return formula.expression % variables
    rescue KeyError => e
      puts "problem with expression #{e.message} : #{formula.code} : #{formula.expression} #{JSON.pretty_generate(variables)}"
      raise e
    end

    def calculate_payments(project, entity, all_package_results)

      project.payment_rules.each do |payment_rule|
        package_results = all_package_results.select {|pr|
          payment_rule.packages.map(&:name).include?(pr.package.name)
        }
        puts "********* calculate_payments : #{package_results} #{payment_rule.apply_for?(entity)} #{package_results.size} #{payment_rule.packages.size}"

        next unless payment_rule.apply_for?(entity)
        next unless package_results.size >= payment_rule.packages.size


        package_facts_and_rules = {}
        package_results.each do |package_result|
          package_facts_and_rules = package_facts_and_rules.merge(package_result.solution)
        end
        package_facts_and_rules = package_facts_and_rules.merge(payment_rule.rule.to_facts)

        return solver.solve!("payment rule", package_facts_and_rules, false)
      end
      return {}
    end

    def generate_monthly_entity_invoice(current_project, entity, analytics_service, date)

      date = date.to_date.end_of_month
      project = project_finder.find_project(current_project, date)

      begin
        activity_results = calculate_activity_results(
          analytics_service,
          project,
          entity,
          date,
          "monthly"
        )
        raise "should have at least one activity_results" if activity_results.empty?
        package_results = calculate_package_results(activity_results)
        raise "should have at least one package_results" if package_results.empty?
        # No payments in monthly ?
        return Invoicing::MonthlyInvoice.new(date, entity, project, activity_results, package_results, {})
      rescue => e
        Invoicing::MonthlyInvoice.new(date, entity, project, activity_results, package_results, {}).dump_invoice
        raise e
      end
    end

    def generate_quarterly_entity_invoice(current_project, entity, analytics_service, date)
      current_quarter_end = date.to_date.end_of_month
      quarter_dates = [current_quarter_end - 2.months, current_quarter_end - 1.month, current_quarter_end].map(&:end_of_month)

      quarter_details_results = {}
      quarterly_package_results = {}
      quarter_dates.each do |month|
        project = project_finder.find_project(current_project, month)
        activity_monthly_results = calculate_activity_results(
          analytics_service,
          project,
          entity,
          month,
          "monthly"
        )
        quarter_details_results[month] = activity_monthly_results
        quarterly_package_results[month] = calculate_package_results(activity_monthly_results)
      end

      quarter_entity_results = calculate_package_results(quarter_details_results.values.flatten)

      begin
        project = project_finder.find_project(current_project, current_quarter_end)
        activity_results = calculate_activity_results(
          analytics_service,
          project,
          entity,
          current_quarter_end,
          "quarterly"
        )

        package_results = calculate_package_results(activity_results)
        package_results.concat(quarter_entity_results)

        raise "should have at least one package_results" if package_results.empty?
        payments = calculate_payments(project, entity, package_results)
        MonthlyInvoice.new(date, entity, project, activity_results, package_results, payments).dump_invoice
      rescue => e
        raise e
      end
    end

    def d_to_s(decimal)
      return "%.2f" % decimal if decimal.is_a? Numeric
      decimal
    end
  end
end
