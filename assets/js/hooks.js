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
  
  beforeUpdate() {
    // Find the first visible event (use this as anchor)
    const eventsList = this.el.querySelector("#events-list");
    if (eventsList) {
      // Store info about the first visible event
      const events = Array.from(eventsList.querySelectorAll('li'));
      
      for (const event of events) {
        const rect = event.getBoundingClientRect();
        // If event is visible (at least partially)
        if (rect.top >= 0 && rect.bottom <= window.innerHeight) {
          this.anchorEvent = {
            id: event.id,
            topPosition: rect.top,
            item: event
          };
          break;
        }
      }
    }
  },
  
  updated() {
    // If we had an anchor event, restore scroll position
    if (this.anchorEvent) {
      const eventElement = document.getElementById(this.anchorEvent.id);
      if (eventElement) {
        const newPosition = eventElement.getBoundingClientRect().top;
        const diff = newPosition - this.anchorEvent.topPosition;
        
          this.el.scrollTop += diff;
          this.anchorEvent = null;
      }
    } 
    // Otherwise auto-scroll to bottom if user was at bottom
    else if (this.isAtBottom) {
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