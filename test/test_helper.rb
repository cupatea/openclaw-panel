ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module AdminAuthenticationTestHelper
  ADMIN_PASSWORD = "correct horse battery staple"

  def sign_in_as_admin
    Setting.instance.change_admin_password!(ADMIN_PASSWORD)
    post admin_login_path, params: { password: ADMIN_PASSWORD }
    assert_response :redirect
  end
end

# Minitest 6 dropped minitest/mock; this is the bit of it the tests need.
# Replaced singleton methods are put back after each test.
module StubHelper
  def stub_method(object, name, value = nil, &block)
    original = object.method(name)
    implementation = block || ->(*, **) { value }
    # Called through, so the block keeps the test as self (assertions work).
    object.define_singleton_method(name) { |*args, **options, &inner| implementation.call(*args, **options, &inner) }
    stubs << [ object, name, original ]
  end

  def stubs = (@stubs ||= [])

  def after_teardown
    stubs.reverse_each { |object, name, original| object.define_singleton_method(name, original) }
    stubs.clear
    super
  end
end

# A docker-inspect-shaped hash for Stack::Container.
module ContainerFixtures
  def container(state: "running", health: "healthy", restarts: 0, exit_code: 0, started: 10.minutes.ago, oom: false, version: "2026.9.8")
    Stack::Container.new(
      "Id" => "abc123def4567890",
      "Name" => "/openclaw-openclaw-gateway-1",
      "RestartCount" => restarts,
      "Image" => "sha256:#{"1" * 64}",
      "State" => { "Status" => state, "ExitCode" => exit_code, "OOMKilled" => oom, "StartedAt" => started.utc.iso8601,
                   "Health" => health && { "Status" => health, "Log" => [ { "Output" => "probe output" } ] } }.compact,
      "Config" => { "Image" => "ghcr.io/openclaw/openclaw:latest", "Labels" => { "org.opencontainers.image.version" => version } }
    )
  end
end

class ActiveSupport::TestCase
  include StubHelper
  include ContainerFixtures

  parallelize(workers: 1)

  setup do
    Rails.cache.clear
  end
end

class ActionDispatch::IntegrationTest
  include AdminAuthenticationTestHelper
end
