# The compose project's .env: tokens and other variables the compose file
# reads. Saving only writes the file; "Apply" recreates the gateway with them
# (`docker compose up -d` — a plain restart keeps the old environment).
class EnvironmentController < ApplicationController
  def show
    @entries = EnvFile.entries
    @missing = EnvFile.required_keys - @entries.keys
    @suggestions = EnvFile.referenced_keys - @entries.keys
  end

  def update
    changes = {}
    params.fetch(:env, {}).to_unsafe_h.each do |key, value|
      # Secret fields render empty; leaving one empty means "keep it".
      changes[key] = value.to_s.strip unless value.blank? && EnvFile.secret?(key)
    end
    Array(params[:remove]).each { |key| changes[key] = nil }
    changes[params[:new_key].to_s.strip] = params[:new_value].to_s.strip if params[:new_key].present?

    EnvFile.update(changes)
    redirect_to environment_path, notice: "Saved .env. Apply it to recreate the gateway with the new values."
  rescue ArgumentError => e
    redirect_to environment_path, alert: e.message
  end
end
