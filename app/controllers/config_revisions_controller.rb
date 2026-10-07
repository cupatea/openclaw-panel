class ConfigRevisionsController < ApplicationController
  def index
    @revisions = ConfigRevision.recent
  end

  def show
    @revision = ConfigRevision.find(params[:id])
  end

  def restore
    revision = ConfigRevision.find(params[:id])
    validation = ConfigFile.write(revision.content, note: "Replaced by restoring the version from #{revision.created_at.to_fs(:short)}")

    if validation.valid?
      redirect_to config_path, notice: "Restored the version from #{revision.created_at.to_fs(:short)}."
    else
      redirect_to config_revision_path(revision), alert: "That version doesn't validate anymore: #{validation.issues.join("; ")}"
    end
  end
end
