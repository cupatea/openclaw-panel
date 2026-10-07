class LogsController < ApplicationController
  TAILS = [ 100, 300, 1000, 3000 ].freeze

  def show
    @tail = TAILS.include?(params[:tail].to_i) ? params[:tail].to_i : 300
    @logs = Stack.logs(tail: @tail).output

    respond_to do |format|
      format.html
      format.text { render plain: @logs }
    end
  end
end
