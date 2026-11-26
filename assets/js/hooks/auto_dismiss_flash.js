// Dismisses info flashes after a few seconds by triggering their own phx-click
// (clear the flash on the server, then hide it). Errors stay until closed.
const DISMISS_AFTER_MS = 5000

export default {
  mounted() {
    this.schedule()
  },

  updated() {
    this.schedule()
  },

  destroyed() {
    clearTimeout(this.timer)
  },

  schedule() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.el.click(), DISMISS_AFTER_MS)
  },
}
