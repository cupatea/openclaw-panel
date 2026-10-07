class OperationsController < ApplicationController
  # Kinds that can be started straight from a button. "cli" goes through the
  # console; "switch_version" needs a version.
  BUTTONS = %w[restart start stop recreate update repair fix_gateway_mode fix_permissions].freeze

  def index
    @operations = Operation.recent.limit(100)
  end

  def show
    @operation = Operation.find(params[:id])

    respond_to do |format|
      format.html
      format.json { render json: @operation.as_json(only: %i[id status output]).merge(active: @operation.active?) }
    end
  end

  def create
    kind = params.require(:kind)

    if kind == "switch_version" && Release::TAG.match?(params[:version].to_s)
      start_operation("switch_version", arguments: [ params[:version] ])
    elsif BUTTONS.include?(kind)
      start_operation(kind)
    else
      head :unprocessable_entity
    end
  end
end
