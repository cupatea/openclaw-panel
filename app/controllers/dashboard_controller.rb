class DashboardController < ApplicationController
  def show
    @container = Stack.gateway
    @diagnosis = Diagnosis.new(@container, Stack.logs(tail: 200).output)
    @active_operation = Operation.active.first
    @operations = Operation.recent.limit(5)
    @setting = Setting.instance
  end
end
