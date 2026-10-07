require "open3"

# Runs external commands (docker, docker compose) as argv arrays — never through
# a shell, so user-supplied arguments can't inject anything.
module Shell
  Result = Data.define(:argv, :output, :exit_status) do
    def success? = exit_status == 0
    def command = argv.join(" ")
  end

  class Timeout < StandardError; end

  ANSI = /\e\[[0-9;?]*[A-Za-z]|\e\][^\a]*\a/

  module_function

  # Runs to completion; stdout and stderr interleaved, ANSI-stripped. A timeout
  # becomes a failed result (exit 124) rather than an exception, so pages that
  # call this synchronously can just render the output. `input` goes to stdin —
  # how secrets reach the CLI without ever appearing in argv.
  def capture(*argv, timeout: 30, input: nil)
    output = +""
    status = begin
      stream(*argv, timeout: timeout, input: input) { |text| output << text }
    rescue Timeout => e
      output << "\n#{e.message}\n"
      124
    end
    Result.new(argv: argv, output: output, exit_status: status)
  end

  # Yields whole lines of output as they arrive and returns the exit status.
  # Kills the process group and raises Shell::Timeout past `timeout` seconds.
  def stream(*argv, timeout: 600, input: nil)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    buffer = +"".b

    Open3.popen2e(*argv.map(&:to_s), pgroup: true) do |stdin, out, wait|
      stdin.write(input) if input
      stdin.close

      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if remaining <= 0
          Process.kill("KILL", -wait.pid) rescue nil
          raise Timeout, "Timed out after #{timeout}s: #{argv.join(" ")}"
        end

        next unless out.wait_readable([ remaining, 1 ].min)

        chunk = out.read_nonblock(16_384, exception: false)
        break if chunk.nil?
        next if chunk == :wait_readable

        buffer << chunk
        if (cut = buffer.rindex("\n"))
          yield clean(buffer.slice!(0..cut))
        end
      end

      yield clean(buffer) unless buffer.empty?
      wait.value.exitstatus || 1
    end
  rescue Errno::ENOENT => e
    yield "#{e.message}\n"
    127
  end

  def clean(text)
    text.dup.force_encoding(Encoding::UTF_8).scrub.gsub(ANSI, "").delete("\r")
  end
end
