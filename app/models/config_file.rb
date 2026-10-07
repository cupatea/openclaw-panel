# openclaw.json, edited through the panel's bind mount of the OpenClaw folder.
#
# Nothing reaches the live file without passing OpenClaw's own validator: the
# new content is written next to it as a candidate, `openclaw config validate`
# checks the candidate inside the gateway image (schema, JSON5 and all), and
# only then does it atomically replace openclaw.json. The previous version is
# kept as a ConfigRevision.
class ConfigFile
  # Where the gateway sees the folder holding openclaw.json (OPENCLAW_STATE_DIR
  # in the compose file — ./drive is mounted there).
  CONTAINER_DIR = ENV.fetch("OPENCLAW_CONTAINER_CONFIG_DIR", "/home/node/.openclaw")
  CANDIDATE = ".openclaw.panel-candidate.json"
  PATCH = ".openclaw.panel-patch.json"
  GATEWAY_UID = 1000 # `node` in the OpenClaw image

  Validation = Data.define(:valid, :issues, :output) do
    def valid? = valid
  end

  class << self
    def path
      ENV.fetch("OPENCLAW_CONFIG_FILE") { File.join(Stack.dir, "drive", "openclaw.json") }
    end

    def read
      File.read(path) if File.exist?(path)
    end

    def validate(content)
      candidate = File.join(File.dirname(path), CANDIDATE)
      write_file(candidate, content, like: path)

      data, result = with_retries do
        Stack.cli_json("config", "validate", "--json", env: { "OPENCLAW_CONFIG_PATH" => File.join(CONTAINER_DIR, CANDIDATE) })
      end

      if data.is_a?(Hash) && data.key?("valid")
        issues = Array(data["issues"]).map { |issue| [ issue["path"], issue["message"] ].compact.join(": ") }
        Validation.new(valid: data["valid"] == true, issues: issues, output: result.output)
      else
        Validation.new(valid: false, issues: [ "Couldn't run the OpenClaw validator." ], output: result.output)
      end
    ensure
      File.delete(candidate) if candidate && File.exist?(candidate)
    end

    # Returns the Validation; the file is only replaced when it's valid.
    def write(content, note:)
      content = content.to_s.gsub("\r\n", "\n")
      content += "\n" unless content.end_with?("\n")

      validation = validate(content)
      return validation unless validation.valid?

      current = read
      ConfigRevision.create!(content: current, note: note) if current && current != content
      write_file(path, content)
      validation
    end

    # An authored value from openclaw.json (secrets come back redacted), or nil
    # when it's unset and OpenClaw's default applies.
    def get(key)
      data, result = with_retries { Stack.cli_json("config", "get", key, "--json") }
      result.success? ? data : nil
    end

    # Merges `changes` into openclaw.json via `openclaw config patch`: objects
    # merge, arrays and scalars replace, nil deletes. OpenClaw validates and
    # writes it; most gateway.* access settings apply without a restart.
    def patch(changes, note:)
      before = read
      patch_file = File.join(File.dirname(path), PATCH)
      write_file(patch_file, JSON.pretty_generate(changes), like: path)

      result = with_retries { [ nil, Stack.cli("config", "patch", "--file", File.join(CONTAINER_DIR, PATCH)) ] }.last
      ConfigRevision.create!(content: before, note: note) if result.success? && before && before != read
      result
    ensure
      File.delete(patch_file) if patch_file && File.exist?(patch_file)
    end

    private

    # Right after the gateway starts, its state database is briefly locked for
    # maintenance and every CLI call fails with "retry when it finishes".
    def with_retries(attempts: 5)
      attempts.times do |attempt|
        data, result = yield
        return [ data, result ] unless result.output.include?("retry when it finishes") && attempt < attempts - 1

        sleep 3
      end
    end

    # Atomic replace that keeps the original owner and mode: the panel runs as
    # root, but the gateway (uid 1000) has to keep reading the file.
    def write_file(target, content, like: target)
      stat = File.exist?(like) ? File.stat(like) : nil
      temp = "#{target}.panel-#{SecureRandom.hex(4)}"

      File.write(temp, content)
      File.chmod(stat ? stat.mode & 0o7777 : 0o600, temp)
      begin
        File.chown(stat&.uid || GATEWAY_UID, stat&.gid || GATEWAY_UID, temp)
      rescue Errno::EPERM
        # Not root (development on a laptop): the file keeps our own owner.
      end
      File.rename(temp, target)
    ensure
      File.delete(temp) if temp && File.exist?(temp)
    end
  end
end
