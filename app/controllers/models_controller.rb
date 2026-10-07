# Model provider credentials — `openclaw models auth …` without a terminal. Keys
# go to the CLI on stdin (paste-api-key / paste-token read it there), so they
# never land in argv, logs or the operation history.
class ModelsController < ApplicationController
  PROVIDER = /\A[a-z0-9][a-z0-9_.-]*\z/
  PROFILE = /\A[A-Za-z0-9][\w.-]*:[\w.@+-]+\z/
  MISSING_PROFILE = /Selected auth profile "([^"]+)" is unavailable/
  PROVIDERS = %w[anthropic openai openrouter google xai deepseek mistral groq ollama].freeze

  def show
    @container = Stack.gateway
    return unless @container&.running?

    status = Thread.new { Stack.cli_json("models", "status", "--json", running: true) }
    @saved, @saved_result = Stack.cli_json("models", "auth", "list", "--json", running: true)
    @status, @status_result = status.value
    @missing = Stack.logs(tail: 3000).output.scan(MISSING_PROFILE).flatten.uniq - saved_ids
  end

  def create
    provider = params[:provider].to_s.strip.downcase
    profile_id = params[:profile_id].to_s.strip
    secret = params[:secret].to_s.strip

    if !PROVIDER.match?(provider) || (profile_id.present? && !PROFILE.match?(profile_id)) || secret.blank?
      return redirect_to models_path(profile_id: profile_id.presence), alert: "Enter a provider, a valid profile id (provider:name) or none, and the key."
    end

    command = params[:kind] == "token" ? "paste-token" : "paste-api-key"
    args = [ "models", "auth", command, "--provider", provider ]
    args += [ "--profile-id", profile_id ] if profile_id.present?

    result = Stack.cli(*args, input: "#{secret}\n")
    if result.success?
      # The running gateway only picks up new provider settings on restart.
      start_operation("restart")
    else
      redirect_to models_path(profile_id: profile_id.presence), alert: failure(result)
    end
  end

  def destroy
    profile_id = params[:profile_id].to_s
    return head :unprocessable_entity unless PROFILE.match?(profile_id)

    result = Stack.cli("models", "auth", "logout", profile_id, "--yes")
    if result.success?
      redirect_to models_path, notice: "Removed #{profile_id}."
    else
      redirect_to models_path, alert: failure(result)
    end
  end

  private

  def saved_ids
    Array(@saved.is_a?(Hash) ? @saved["profiles"] : nil).filter_map { |profile| profile["id"] }
  end

  def failure(result)
    result.output.lines.grep_v(/^\[openclaw\] (Debug|Try|Help):/).last(3).join.strip.presence || "Failed."
  end
end
