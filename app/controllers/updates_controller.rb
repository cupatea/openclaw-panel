class UpdatesController < ApplicationController
  def show
    @container = Stack.gateway
    @pinning = Stack.version_pinning?
    @pinned_image = EnvFile.entries[Stack::IMAGE_VARIABLE]
    @releases = Release.recent
    @operations = Operation.where(kind: %w[update switch_version]).recent.limit(10)
  end
end
