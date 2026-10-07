# A copy of openclaw.json taken before the panel overwrote it, so any edit can
# be undone from the UI.
class ConfigRevision < ApplicationRecord
  KEEP = 50

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  after_create_commit :prune

  private

  def prune
    ConfigRevision.where.not(id: ConfigRevision.recent.limit(KEEP).select(:id)).delete_all
  end
end
