require "shellwords"

# Something the panel does to the stack in the background — restart, update,
# repair, a CLI command — with its output kept for the UI and as a history.
# One at a time: two compose commands racing on the same container is how
# stacks end up half-recreated.
class Operation < ApplicationRecord
  include Operation::Recipes

  class Busy < StandardError; end

  ACTIVE = %w[queued running].freeze
  MAX_OUTPUT = 200_000
  FLUSH_EVERY = 0.5 # seconds

  scope :active, -> { where(status: ACTIVE) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  validates :kind, inclusion: { in: ->(_) { RECIPES.keys } }
  validates :trigger, inclusion: { in: %w[manual watchdog] }

  def self.start!(kind, arguments: [], trigger: "manual")
    operation = transaction do
      raise Busy, "#{active.first.title} is still running." if active.exists?

      create!(kind: kind, arguments: arguments, trigger: trigger)
    end
    OperationJob.perform_later(operation)
    operation
  end

  # A server restart kills the job thread mid-run; don't leave it "running" forever.
  def self.interrupt_orphans!
    active.find_each do |operation|
      operation.update!(status: "interrupted", finished_at: Time.current,
                        output: operation.output + "\nInterrupted: the panel restarted while this was running.\n")
    end
  end

  def title
    kind == "cli" ? "openclaw #{command_line}" : RECIPES.fetch(kind)[:title]
  end

  def command_line = Shellwords.join(arguments)

  def active? = ACTIVE.include?(status)
  def succeeded? = status == "succeeded"

  def duration
    return unless started_at

    (finished_at || Time.current) - started_at
  end

  def perform
    update!(status: "running", started_at: Time.current)
    succeeded = public_send(RECIPES.fetch(kind)[:run])
    finish!(succeeded ? "succeeded" : "failed")
  rescue StandardError => e
    log "\n#{e.class}: #{e.message}\n"
    finish!("failed")
  end

  def log(text)
    self.output = output + text
    self.output = "…(earlier output trimmed)\n" + output.last(MAX_OUTPUT) if output.size > MAX_OUTPUT

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return if @flushed_at && now - @flushed_at < FLUSH_EVERY

    @flushed_at = now
    update_column(:output, output)
  end

  private

  def finish!(status)
    update!(status: status, finished_at: Time.current, output: output)
  end
end
