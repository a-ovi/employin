let ScrollToBottom = {
  mounted() {
    this.scrollToBottom();
    // Set up observer to detect when new events are added
    this.observer = new MutationObserver(() => {
      if (this.isAtBottom) {
        this.scrollToBottom();
      }
    });
    this.observer.observe(this.el, { childList: true, subtree: true });
    
    // Track if user is scrolled to bottom
    this.el.addEventListener('scroll', () => {
      this.isAtBottom = this.isScrolledToBottom();
    });
    
    // Initially set to true so first update auto-scrolls
    this.isAtBottom = true;
  },
  
  updated() {
    if (this.isAtBottom) {
      this.scrollToBottom();
    }
  },
  
  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
  },
  
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
  
  isScrolledToBottom() {
    // Consider "at bottom" if within 30px of the bottom
    const scrollBottom = this.el.scrollTop + this.el.clientHeight;
    return scrollBottom >= this.el.scrollHeight - 30;
  }
};

export default {
  ScrollToBottom
};