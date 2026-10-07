# The .env next to the compose file. Compose fills both `${VAR}` references and
# bare `VAR:` environment keys from it, so tokens can live here instead of in
# docker-compose.yaml. Edits keep comments, order and unrelated lines intact.
class EnvFile
  LINE = /\A\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)\z/
  SECRET = /TOKEN|KEY|SECRET|PASSWORD|PASS\z/i
  NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/

  class << self
    def path = Stack.env_file

    def entries
      lines.filter_map do |line|
        next unless (match = LINE.match(line))

        [ match[1], unquote(match[2].strip) ]
      end.to_h
    end

    def secret?(key) = SECRET.match?(key)

    # Variables the compose file reads from the environment: `${VAR}` / `$VAR`
    # references, and environment keys left without a value (`VAR:`).
    def referenced_keys
      (required_keys + compose_text.scan(/\$\{([A-Za-z_][A-Za-z0-9_]*):?-/).flatten).uniq
    end

    # The ones without a `${VAR:-default}` fallback.
    def required_keys
      text = compose_text
      bare = text.scan(/^\s+([A-Z][A-Z0-9_]*):\s*$/).flatten
      interpolated = text.scan(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)/).flatten.compact
      (bare + interpolated).uniq
    end

    # changes: { "KEY" => "value" } sets, { "KEY" => nil } removes.
    def update(changes)
      return if changes.empty?

      invalid = changes.keys.reject { |key| NAME.match?(key) }
      raise ArgumentError, "Invalid variable name: #{invalid.join(", ")}" if invalid.any?

      pending = changes.dup
      updated = lines.filter_map do |line|
        key = LINE.match(line)&.[](1)
        next line unless key && pending.key?(key)

        value = pending.delete(key)
        "#{key}=#{quote(value)}" unless value.nil?
      end
      pending.each { |key, value| updated << "#{key}=#{quote(value)}" unless value.nil? }

      File.write(path, updated.join("\n").strip + "\n")
    end

    private

    def compose_text
      File.exist?(Stack.compose_file) ? File.read(Stack.compose_file) : ""
    end

    def lines
      File.exist?(path) ? File.read(path).split("\n") : []
    end

    def unquote(value)
      if value.start_with?("'") && value.end_with?("'") && value.size > 1
        value[1..-2]
      elsif value.start_with?('"') && value.end_with?('"') && value.size > 1
        value[1..-2].gsub('\\"', '"').gsub("\\\\", "\\").gsub("$$", "$")
      else
        value.sub(/\s+#.*\z/, "")
      end
    end

    # Single quotes stop compose from interpolating `$` inside tokens.
    def quote(value)
      value = value.to_s
      return value if value.match?(%r{\A[A-Za-z0-9_./:@+,=-]*\z})
      return "'#{value}'" unless value.include?("'")

      %("#{value.gsub("\\", "\\\\\\\\").gsub('"', '\\"').gsub("$", "$$")}")
    end
  end
end
