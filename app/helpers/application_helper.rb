module ApplicationHelper
  def nav_link(label, path, also: [])
    current = [ path, *also ].any? { |candidate| path == root_path ? request.path == candidate : request.path.start_with?(candidate) }
    link_to label, path, class: [ "nav-link", ("current" if current) ], aria: { current: (current ? "page" : nil) }
  end

  def condition_badge(container)
    condition = container&.condition || "missing"
    label = { "healthy" => "Healthy", "starting" => "Starting", "unhealthy" => "Unhealthy",
              "crashing" => "Crash-looping", "stopped" => "Stopped", "missing" => "Not created" }.fetch(condition)
    tag.span(label, class: [ "badge", condition ])
  end

  def status_badge(operation)
    tag.span(operation.status.humanize, class: [ "badge", operation.status ])
  end

  def short_duration(seconds)
    return "—" unless seconds

    seconds = seconds.to_i
    if seconds < 60 then "#{seconds}s"
    elsif seconds < 3600 then "#{seconds / 60}m #{seconds % 60}s"
    elsif seconds < 86_400 then "#{seconds / 3600}h #{(seconds % 3600) / 60}m"
    else "#{seconds / 86_400}d #{(seconds % 86_400) / 3600}h"
    end
  end

  def older_version?(tag, than)
    than.present? && Gem::Version.new(tag) < Gem::Version.new(than)
  rescue ArgumentError
    false
  end

  # A button that starts an Operation, optionally asking first.
  def operation_button(label, kind, confirm: nil, style: nil, params: {})
    button_to label, operations_path, params: { kind: kind, **params },
              class: [ "button", style ], form: { data: { confirm: confirm } }
  end

  def finding_action(finding)
    if finding.fix
      operation_button Operation::RECIPES.fetch(finding.fix)[:title], finding.fix,
                       confirm: "#{Operation::RECIPES.fetch(finding.fix)[:title]}?"
    elsif finding.link
      link_to "Open #{finding.link.to_s.humanize.downcase} →", public_send("#{finding.link}_path"), class: "button secondary"
    end
  end
end
