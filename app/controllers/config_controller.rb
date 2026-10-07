class ConfigController < ApplicationController
  def show
    @content = ConfigFile.read
  end

  def update
    @content = params.require(:content)
    @validation = ConfigFile.write(@content, note: "Edited in the panel")

    if !@validation.valid?
      render :show, status: :unprocessable_entity
    elsif params[:restart].present?
      start_operation("restart")
    else
      redirect_to config_path, notice: "Saved. OpenClaw hot-reloads most settings; restart if a change doesn't take effect."
    end
  end
end
