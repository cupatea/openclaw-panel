require "net/http"

# OpenClaw release tags published on GHCR, for the version picker. `latest`
# is rebuilt weekly; a pinned release tag only changes when you choose to.
module Release
  TAG = /\A(?:latest|\d{4}\.\d{1,2}\.\d{1,2}(?:-[0-9A-Za-z.]+)?)\z/
  STABLE = /\A\d{4}\.\d{1,2}\.\d{1,2}\z/
  MAX_PAGES = 10

  module_function

  # Newest first. Empty when GHCR can't be reached — the page still works.
  def recent(limit: 12)
    Array(Rails.cache.fetch("openclaw-releases", expires_in: 1.hour, skip_nil: true) { fetch }).first(limit)
  end

  def fetch
    repository = Stack::IMAGE_REPOSITORY.delete_prefix("ghcr.io/")
    token = get("https://ghcr.io/token?scope=repository:#{repository}:pull").then { |response| JSON.parse(response.body)["token"] }

    tags = []
    path = "/v2/#{repository}/tags/list?n=1000"
    MAX_PAGES.times do
      response = get("https://ghcr.io#{path}", token: token)
      tags.concat(JSON.parse(response.body)["tags"].to_a)
      path = response["link"].to_s[/<([^>]+)>;\s*rel="next"/, 1] or break
    end

    tags.grep(STABLE).uniq.sort_by { |tag| Gem::Version.new(tag) }.reverse
  rescue StandardError => e
    Rails.logger.warn("[Release] couldn't list tags: #{e.class}: #{e.message}")
    nil
  end

  def get(url, token: nil)
    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}" if token

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.request(request).tap(&:value)
    end
  end
end
