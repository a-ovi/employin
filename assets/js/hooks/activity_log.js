// Chat-style activity log: newest events at the bottom.
//
// - Sticks to the bottom while the user is there, so live events stay visible.
// - Loads older events (`load-more`) when the user scrolls near the top. Only one
//   request is in flight at a time, and loading stops once the server reports
//   there are no more events.
// - Keeps the first visible event in place when older events are inserted above it.
// - Shows a "scroll to bottom" button while the user is reading older events.

const NEAR_TOP_RATIO = 0.4
const BOTTOM_THRESHOLD_PX = 10

export default {
  mounted() {
    this.loading = false
    this.hasMore = true
    this.stickToBottom = true
    this.anchor = null

    this.button = document.getElementById(this.el.dataset.scrollButton)
    this.onButtonClick = () => this.scrollToBottom()
    this.button?.addEventListener("click", this.onButtonClick)

    this.onScroll = () => {
      this.stickToBottom = this.isAtBottom()
      this.toggleButton()
      this.maybeLoadMore()
    }
    this.el.addEventListener("scroll", this.onScroll, {passive: true})

    this.scrollToBottom()
  },

  beforeUpdate() {
    this.anchor = this.stickToBottom ? null : this.findAnchor()
  },

  updated() {
    const anchorEl = this.anchor && document.getElementById(this.anchor.id)

    if (anchorEl) {
      this.el.scrollTop += anchorEl.getBoundingClientRect().top - this.anchor.top
    } else if (this.stickToBottom) {
      this.scrollToBottom()
    }

    this.anchor = null
    this.toggleButton()
    // A short list may not be scrollable yet, so fetch more without waiting for a scroll.
    if (this.el.scrollHeight <= this.el.clientHeight) this.maybeLoadMore()
  },

  destroyed() {
    this.el.removeEventListener("scroll", this.onScroll)
    this.button?.removeEventListener("click", this.onButtonClick)
  },

  maybeLoadMore() {
    if (this.loading || !this.hasMore || !this.isNearTop()) return
    if (!this.el.querySelector("[data-event]")) return

    this.loading = true
    this.pushEvent("load-more", {}, (reply) => {
      this.hasMore = reply.more
      this.loading = false
    })
  },

  // The first event that is at least partly visible in the scroll container.
  findAnchor() {
    const top = this.el.getBoundingClientRect().top

    for (const item of this.el.querySelectorAll("[data-event]")) {
      const rect = item.getBoundingClientRect()
      if (rect.bottom > top) return {id: item.id, top: rect.top}
    }
    return null
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
    this.stickToBottom = true
    this.toggleButton()
  },

  toggleButton() {
    this.button?.classList.toggle("hidden", this.stickToBottom)
  },

  isNearTop() {
    return this.el.scrollTop <= this.el.scrollHeight * NEAR_TOP_RATIO
  },

  isAtBottom() {
    const {scrollTop, scrollHeight, clientHeight} = this.el
    return scrollHeight - (scrollTop + clientHeight) < BOTTOM_THRESHOLD_PX
  },
}
