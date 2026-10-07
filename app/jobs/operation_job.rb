class OperationJob < ApplicationJob
  def perform(operation)
    operation.perform
  end
end
