require "test_helper"

class DiagnosisTest < ActiveSupport::TestCase
  def log(message, at: Time.current)
    "#{at.utc.iso8601(9)} #{message}\n"
  end

  test "missing gateway.mode offers the one-click fix" do
    logs = log("Gateway start blocked: existing config is missing gateway.mode. Treat this as suspicious.")
    finding = Diagnosis.new(container(state: "restarting", restarts: 7), logs).findings.first
    assert_equal "fix_gateway_mode", finding.fix
  end

  test "untrusted reverse proxy points at the access page" do
    logs = log("[gateway] observed unattributable proxy-shaped traffic from 172.18.0.1; add it to gateway.trustedProxies")
    finding = Diagnosis.new(container, logs).findings.first
    assert_match "172.18.0.1", finding.title
    assert_equal :access, finding.link
  end

  test "known NAS filesystem bug points at updates" do
    logs = log("pre-migration snapshot failed: staging file changed during transfer")
    assert_equal :updates, Diagnosis.new(container(state: "restarting", restarts: 3), logs).findings.first.link
  end

  test "old problems are ignored while the gateway is healthy" do
    logs = log("disconnected (1008): pairing required", at: 2.hours.ago)
    assert_empty Diagnosis.new(container, logs).findings
  end

  test "recent problems count even while healthy" do
    logs = log("disconnected (1008): pairing required", at: 1.minute.ago)
    assert_equal :devices, Diagnosis.new(container, logs).findings.first.link
  end

  test "unhealthy gateway suggests a restart" do
    assert_equal "restart", Diagnosis.new(container(health: "unhealthy"), "").findings.first.fix
  end

  test "exit 78 explains the downgrade" do
    findings = Diagnosis.new(container(state: "exited", health: nil, exit_code: 78), "").findings
    assert_equal :updates, findings.first.link
  end

  test "an edit OpenClaw reverted on startup points at the config page" do
    logs = log("Config auto-restored from backup: /home/node/.openclaw/openclaw.json (gateway-mode-missing-vs-last-good)")
    finding = Diagnosis.new(container, logs).findings.first
    assert_equal :config, finding.link
    assert_match "gateway-mode-missing-vs-last-good", finding.detail
  end

  test "a missing model credential points at the models page with its id" do
    logs = log(%(embedded agent failed: Selected auth profile "anthropic:default" is unavailable.))
    finding = Diagnosis.new(container, logs).findings.first
    assert_equal :models, finding.link
    assert_match "anthropic:default", finding.title
  end

  test "no container suggests starting it" do
    assert_equal "start", Diagnosis.new(nil, "").findings.first.fix
  end
end
