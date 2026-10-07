class DiagnosticsController < ApplicationController
  def show
    @container = Stack.gateway
    @diagnosis = Diagnosis.new(@container, Stack.logs(tail: 300).output)
    @lint, @lint_result = Stack.cli_json("doctor", "--lint", "--json", timeout: 120)
    @health, @health_result = Stack.cli_json("health", "--json") if @container&.running?
  end
end
