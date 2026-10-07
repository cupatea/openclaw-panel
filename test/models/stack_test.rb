require "test_helper"

class StackTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "docker-compose.yaml"), "services: {}\n")
    @previous = ENV.to_h.slice("OPENCLAW_DIR", "OPENCLAW_HOST_DIR")
    ENV["OPENCLAW_DIR"] = @dir
    ENV["OPENCLAW_HOST_DIR"] = "/volume1/docker/openclaw"
    Stack.instance_variable_set(:@host_dir, nil)
  end

  teardown do
    %w[OPENCLAW_DIR OPENCLAW_HOST_DIR].each { |key| ENV[key] = @previous[key] }
    Stack.instance_variable_set(:@host_dir, nil)
    FileUtils.remove_entry(@dir)
  end

  test "compose runs against the host path so bind mounts resolve on the host" do
    assert_equal [ "docker", "compose", "--project-directory", "/volume1/docker/openclaw",
                   "--file", File.join(@dir, "docker-compose.yaml"), "ps" ], Stack.compose("ps")
  end

  test "compose passes the .env explicitly, since the project directory isn't readable here" do
    File.write(File.join(@dir, ".env"), "A=1\n")
    assert_includes Stack.compose("ps").each_cons(2).to_a, [ "--env-file", File.join(@dir, ".env") ]
  end

  test "cli execs into a running gateway and uses a throwaway container otherwise" do
    assert_equal %w[exec -T openclaw-gateway node dist/index.js status], Stack.cli_argv("status", running: true).last(6)
    assert_equal %w[run --rm --no-deps -T openclaw-gateway node dist/index.js status], Stack.cli_argv("status", running: false).last(8)
    assert_includes Stack.cli_argv("x", running: true, env: { "A" => "b" }).each_cons(2).to_a, [ "--env", "A=b" ]
  end

  test "extract_json finds single-line JSON among other output" do
    assert_equal({ "valid" => true }, Stack.extract_json("Container x Creating\n{\"valid\":true}\n"))
  end

  test "extract_json finds pretty JSON followed by CLI error lines" do
    text = "{\n  \"ok\": false,\n  \"error\": {\n    \"message\": \"nope\"\n  }\n}\n[openclaw] The CLI command failed.\n"
    assert_equal "nope", Stack.extract_json(text).dig("error", "message")
  end

  test "extract_json returns nil without JSON" do
    assert_nil Stack.extract_json("command not found\n")
  end
end
