let ScrollToBottom = {
  mounted() {
    this.scrollToBottom();
    this.isInBufferZone = false; // Track if user is in buffer zone
    
    // Set up observer for new events
    this.observer = new MutationObserver(() => {
      if (this.isAtBottom) {
        this.scrollToBottom();
      }
    });
    this.observer.observe(this.el, { childList: true, subtree: true });
    
    // Track scrolling
    this.el.addEventListener('scroll', () => {
      this.isAtBottom = this.isScrolledToBottom();
      
      // Check if near top for buffer zone loading
      const currentlyInBufferZone = this.isNearTop();
      
      // Special case: if at absolute top, always trigger load-more
      const atAbsoluteTop = this.el.scrollTop === 0;
      
      // Trigger when entering buffer zone OR when at absolute top
      if ((currentlyInBufferZone && !this.isInBufferZone) || atAbsoluteTop) {
        this.pushEvent("load-more");
      }
      
      // Update buffer zone state
      this.isInBufferZone = currentlyInBufferZone;
    });
    
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
  
  isNearTop() {
    // Consider "near top" if within 40% of the top
    const bufferZone = this.el.scrollHeight * 0.4;
    return this.el.scrollTop <= bufferZone;
  },
  
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
  
  isScrolledToBottom() {
    const scrollTop = this.el.scrollTop;
    const scrollHeight = this.el.scrollHeight;
    const clientHeight = this.el.clientHeight;
    
    // Consider "at bottom" if within 10 pixels of the bottom
    return scrollHeight - (scrollTop + clientHeight) < 10;
  }
};

export default {
  ScrollToBottom
};