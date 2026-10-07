// Small progressive enhancements; every page works without them.

// Confirm before submitting forms marked data-confirm, and guard against
// double submits (a second "Restart" tap while the first is on its way).
document.addEventListener("submit", (event) => {
  const form = event.target
  const message = form.dataset.confirm
  if (message && !window.confirm(message)) {
    event.preventDefault()
    return
  }
  // Deferred: a button disabled during the submit event drops its own
  // name/value from the request (e.g. "Save and restart").
  if (form.target !== "_blank") {
    setTimeout(() => {
      form.querySelectorAll("[type=submit], button:not([type])").forEach((button) => { button.disabled = true })
    }, 0)
  }
})

// Restore buttons when the page comes back from the bfcache (Safari back button).
window.addEventListener("pageshow", () => {
  document.querySelectorAll("[type=submit]:disabled, button:disabled").forEach((button) => { button.disabled = false })
})

function nearBottom(element) {
  return element.scrollHeight - element.scrollTop - element.clientHeight < 40
}

function setText(element, text) {
  const follow = nearBottom(element)
  element.textContent = text
  if (follow) element.scrollTop = element.scrollHeight
}

document.addEventListener("DOMContentLoaded", () => {
  // The section nav scrolls sideways on phones; keep the current one visible.
  document.querySelector(".nav-link.current")?.scrollIntoView({ inline: "center", block: "nearest" })

  document.querySelectorAll("[data-autoscroll], [data-poll]").forEach((element) => {
    element.scrollTop = element.scrollHeight
  })

  // Live output of a running operation; reload once it finishes so the status
  // badge and buttons update.
  const output = document.querySelector("#operation-output[data-poll]")
  if (output) {
    const poll = async () => {
      try {
        const response = await fetch(output.dataset.poll, { headers: { Accept: "application/json" } })
        if (response.ok) {
          const operation = await response.json()
          if (operation.output) setText(output, operation.output)
          if (!operation.active) return window.location.reload()
        }
      } catch (_) { /* network blip; try again */ }
      setTimeout(poll, 1500)
    }
    setTimeout(poll, 1000)
  }

  // "Follow" on the logs page.
  const live = document.querySelector("#logs-live")
  const logs = document.querySelector("#logs-output")
  if (live && logs) {
    let timer = null
    const refresh = async () => {
      try {
        const response = await fetch(live.dataset.source, { headers: { Accept: "text/plain" } })
        if (response.ok) setText(logs, await response.text())
      } catch (_) { /* ignore */ }
    }
    live.addEventListener("change", () => {
      clearInterval(timer)
      if (live.checked) {
        refresh()
        timer = setInterval(refresh, 3000)
      }
    })
  }
})
