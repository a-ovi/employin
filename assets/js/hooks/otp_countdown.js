// Counts down `data-seconds` and tells the server when the OTP can be resent.
// The server enforces the same cooldown, so this only drives the UI.
// The element must use phx-update="ignore" so LiveView doesn't reset the text.

export default {
  mounted() {
    const seconds = parseInt(this.el.dataset.seconds, 10) || 0
    this.deadline = Date.now() + seconds * 1000
    this.tick()
  },

  destroyed() {
    clearTimeout(this.timer)
  },

  tick() {
    const remaining = Math.max(0, Math.ceil((this.deadline - Date.now()) / 1000))
    const minutes = String(Math.floor(remaining / 60)).padStart(2, "0")
    const seconds = String(remaining % 60).padStart(2, "0")
    this.el.textContent = `Resend OTP in ${minutes}:${seconds}`

    if (remaining === 0) {
      this.pushEvent("countdown-finished", {})
    } else {
      this.timer = setTimeout(() => this.tick(), 1000)
    }
  },
}
