require "test_helper"

class EnvFileTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @previous = ENV["OPENCLAW_DIR"]
    ENV["OPENCLAW_DIR"] = @dir
  end

  teardown do
    ENV["OPENCLAW_DIR"] = @previous
    FileUtils.remove_entry(@dir)
  end

  def env_path = File.join(@dir, ".env")

  test "reads plain, quoted and commented values" do
    File.write(env_path, "# tokens\nA=plain\nB='single $x'\nC=\"double \\\"q\\\"\"\nexport D=1 # note\n")
    assert_equal({ "A" => "plain", "B" => "single $x", "C" => "double \"q\"", "D" => "1" }, EnvFile.entries)
  end

  test "updates in place, keeps comments, appends new keys, removes nil" do
    File.write(env_path, "# keep me\nA=1\nB=2\n")
    EnvFile.update("A" => "10", "B" => nil, "C" => "3")
    assert_equal "# keep me\nA=10\nC=3\n", File.read(env_path)
  end

  test "quotes values so compose reads them back verbatim" do
    EnvFile.update("TOKEN" => "abc$def ghi", "OTHER" => "it's $x")
    assert_equal({ "TOKEN" => "abc$def ghi", "OTHER" => "it's $x" }, EnvFile.entries)
    assert_equal "TOKEN='abc$def ghi'", File.read(env_path).lines.first.chomp
    assert_equal %(OTHER="it's $$x"), File.read(env_path).lines.second.chomp
  end

  test "rejects invalid names" do
    assert_raises(ArgumentError) { EnvFile.update("BAD NAME" => "x") }
  end

  test "secret detection" do
    assert EnvFile.secret?("TELEGRAM_BOT_TOKEN")
    assert EnvFile.secret?("OPENAI_API_KEY")
    assert_not EnvFile.secret?("TZ")
  end

  test "required and referenced keys come from the compose file" do
    File.write(File.join(@dir, "docker-compose.yaml"), <<~YAML)
      x-env: &env
        OPENCLAW_GATEWAY_TOKEN:
        TZ: Europe/Kyiv
      x-image: &image ${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}
      services:
        gw:
          image: *image
          environment:
            <<: *env
            EXTRA: ${EXTRA_VALUE}
    YAML
    assert_equal %w[OPENCLAW_GATEWAY_TOKEN EXTRA_VALUE], EnvFile.required_keys
    assert_equal %w[OPENCLAW_GATEWAY_TOKEN EXTRA_VALUE OPENCLAW_IMAGE], EnvFile.referenced_keys
    assert Stack.version_pinning?
  end
end
