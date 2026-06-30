# frozen_string_literal: true

require "shellwords"
require "socket"
require "tempfile"
require "net/http"
require "json"
require "json_schemer"
require "pathname"
require "puma"

module IntegrationServer
  TEST_TOKEN = "puma-enhanced-stats-test-token"
  RACKUP_PATH = File.expand_path("rails_app/config.ru", __dir__)

  module_function

  def find_free_port
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    port
  end

  def write_puma_config app_port:, control_port:, token: TEST_TOKEN, workers: nil, worker_check_interval: 2
    file = Tempfile.new(["puma-enhanced-stats", ".rb"])
    cluster_lines = if workers
                      <<~RUBY
                        workers #{workers}
                        threads 1, 1
                        worker_check_interval #{worker_check_interval}
                      RUBY
                    else
                      ""
                    end

    file.write(<<~RUBY)
      port #{app_port}
      environment "test"
      pidfile "/dev/null"
      #{cluster_lines}
      rackup "#{RACKUP_PATH.gsub('"', '\\"')}"
      activate_control_app "tcp://127.0.0.1:#{control_port}", { auth_token: "#{token}", data_only: true }
    RUBY
    file.close
    file.path
  end

  def wait_for_tcp host, port, timeout: 15
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      begin
        socket = TCPSocket.new(host, port)
        socket.close
        return true
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
        raise "Timed out waiting for #{host}:#{port}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.1
      end
    end
  end

  def start_puma_server workers: nil, worker_check_interval: 2, token: TEST_TOKEN, slow_sleep: 3
    RailsTestApp.slow_sleep = slow_sleep

    app_port = find_free_port
    control_port = find_free_port
    control_port = find_free_port while control_port == app_port
    config_path = write_puma_config(
      app_port: app_port,
      control_port: control_port,
      token: token,
      workers: workers,
      worker_check_interval: worker_check_interval
    )

    config = Puma::Configuration.new do |user|
      user.load config_path
    end
    launcher = Puma::Launcher.new(config)
    thread = Thread.new { launcher.run }

    wait_for_tcp("127.0.0.1", app_port)
    wait_for_tcp("127.0.0.1", control_port)
    sleep(workers ? 3 : 0)

    {
      launcher: launcher,
      thread: thread,
      app_port: app_port,
      control_port: control_port,
      token: token,
      config_path: config_path,
      worker_check_interval: worker_check_interval
    }
  end

  def stop_puma_server server
    return unless server

    server[:launcher].stop(true)
    server[:thread].join(10)
  rescue StandardError
    server[:thread].kill
  ensure
    File.delete(server[:config_path]) if server&.dig(:config_path) && File.exist?(server[:config_path])
  end

  def fetch_enhanced_stats control_port:, token: TEST_TOKEN
    uri = URI("http://127.0.0.1:#{control_port}/enhanced-stats?token=#{token}")
    response = Net::HTTP.get_response(uri)
    raise "enhanced-stats failed: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def fetch_puma_stats control_port:, token: TEST_TOKEN
    uri = URI("http://127.0.0.1:#{control_port}/stats?token=#{token}")
    response = Net::HTTP.get_response(uri)
    raise "stats failed: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def trigger_slow_request app_port, path: "/slow"
    Thread.new do
      Net::HTTP.get(URI("http://127.0.0.1:#{app_port}#{path}"))
    rescue StandardError
      nil
    end
  end

  def validate_against_schema payload
    schema = JSONSchemer.schema(Pathname.new("schema/enhanced-stats-v1.json"))
    errors = schema.validate(payload).to_a
    raise "schema errors: #{errors.inspect}" unless errors.empty?
  end

  def run_pumactl control_url:, token:, command:
    env_boot = File.expand_path("rails_app/config/environment.rb", __dir__)
    cmd = [
      "bundle", "exec", "ruby",
      "-r", env_boot,
      Gem.bin_path("puma", "pumactl"),
      "-C", control_url,
      "-T", token,
      command
    ]
    [`#{Shellwords.shelljoin(cmd)} 2>&1`, $?.success?]
  end

  def reset_gem_state!
    Thread.current[Puma::Enhanced::Stats::Middleware::KEY] = nil
    RailsTestApp.slow_sleep = 3
  end
end
