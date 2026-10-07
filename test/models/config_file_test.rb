require "test_helper"

class ConfigFileTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @previous = ENV["OPENCLAW_DIR"]
    ENV["OPENCLAW_DIR"] = @dir
    FileUtils.mkdir_p(File.join(@dir, "drive"))
    File.write(ConfigFile.path, %({"gateway":{"mode":"local"}}\n))
    File.chmod(0o640, ConfigFile.path)
  end

  teardown do
    ENV["OPENCLAW_DIR"] = @previous
    FileUtils.remove_entry(@dir)
  end

  def validator_says(json)
    stub_method(Stack, :cli_json) do |*args, **options|
      assert_equal %w[config validate --json], args
      assert_equal "/home/node/.openclaw/.openclaw.panel-candidate.json", options.dig(:env, "OPENCLAW_CONFIG_PATH")
      assert File.exist?(File.join(@dir, "drive", ConfigFile::CANDIDATE)), "candidate should exist while validating"
      [ json, Shell::Result.new(argv: args, output: json.to_json, exit_status: json["valid"] ? 0 : 1) ]
    end
  end

  test "an invalid config never reaches the live file" do
    validator_says("valid" => false, "issues" => [ { "path" => "gateway.port", "message" => "expected number" } ])

    validation = ConfigFile.write(%({"gateway":{"port":"abc"}}), note: "test")

    assert_not validation.valid?
    assert_equal [ "gateway.port: expected number" ], validation.issues
    assert_equal %({"gateway":{"mode":"local"}}\n), File.read(ConfigFile.path)
    assert_equal 0, ConfigRevision.count
    assert_equal [ "openclaw.json" ], Dir.children(File.join(@dir, "drive")), "no candidate or temp files left behind"
  end

  test "a valid config replaces the file, keeps its mode and saves the old version" do
    validator_says("valid" => true, "warnings" => [])

    assert ConfigFile.write(%({ gateway: { mode: "local", port: 18789 } } // json5), note: "test").valid?

    assert_equal %({ gateway: { mode: "local", port: 18789 } } // json5\n), File.read(ConfigFile.path)
    assert_equal 0o640, File.stat(ConfigFile.path).mode & 0o777
    assert_equal %({"gateway":{"mode":"local"}}\n), ConfigRevision.last.content
    assert_equal [ "openclaw.json" ], Dir.children(File.join(@dir, "drive"))
  end

  test "a validator that can't run counts as invalid" do
    stub_method(Stack, :cli_json) { |*args, **| [ nil, Shell::Result.new(argv: args, output: "no such service", exit_status: 1) ] }
    assert_not ConfigFile.write("{}", note: "test").valid?
  end
end
