// DOM manipulation and widget rendering functions

import { formatVoteAmount, formatStatusForDisplay } from "../utils/formatting";

/**
 * Get or create the widgets container for column layout
 */
export function getOrCreateWidgetsContainer() {
  // Don't create container on mobile - widgets should be inline
  const isMobile = window.innerWidth <= 1024;
  if (isMobile) {
    console.log("🔵 [CONTAINER] Mobile detected - skipping container creation");
    return null;
  }
  
  let container = document.getElementById('governance-widgets-wrapper');
  if (!container) {
    container = document.createElement('div');
    container.id = 'governance-widgets-wrapper';
    container.className = 'governance-widgets-wrapper';
    container.style.display = 'flex';
    container.style.flexDirection = 'column';
    container.style.gap = '16px';
    container.style.position = 'fixed';
    container.style.zIndex = '500';
    container.style.width = '320px';
    container.style.maxWidth = '320px';
    container.style.maxHeight = 'calc(100vh - 100px)';
    container.style.overflowY = 'auto';
    
    // Position container like tally widget - fixed on right side
    updateContainerPosition(container);
    
    document.body.appendChild(container);
    console.log("✅ [CONTAINER] Created widgets container for column layout");
    
    // Update position on resize only (not scroll) to keep widgets fixed
    let updateTimeout;
    const updatePosition = () => {
      clearTimeout(updateTimeout);
      updateTimeout = setTimeout(() => {
        if (container && container.parentNode) {
          // Re-check if mobile after resize
          const stillMobile = window.innerWidth <= 1024;
          if (!stillMobile) {
            updateContainerPosition(container);
          }
        }
      }, 100);
    };
    
    // Only update on resize, not scroll - keeps widgets fixed during scroll
    window.addEventListener('resize', updatePosition);
    
    // Initial position update after a short delay to ensure DOM is ready
    setTimeout(() => updateContainerPosition(container), 100);
  }
  return container;
}

/**
 * Update container position - keep fixed on right side like tally widget
 */
export function updateContainerPosition(container) {
  // Position like tally widget - fixed on right side, same position
  container.style.right = '50px';
  container.style.left = 'auto';
  container.style.top = '180px';
  // Ensure container is always visible
  container.style.display = 'flex';
  container.style.visibility = 'visible';
  
  // Log position data for debugging
  const rect = container.getBoundingClientRect();
  console.log("📍 [POSITION DATA] Container position:", {
    right: '50px',
    top: '180px',
    actualLeft: `${rect.left}px`,
    actualTop: `${rect.top}px`,
    actualRight: `${rect.right}px`,
    actualBottom: `${rect.bottom}px`,
    width: `${rect.width}px`,
    height: `${rect.height}px`,
    windowWidth: window.innerWidth,
    windowHeight: window.innerHeight
  });
}

/**
 * Format time display for proposals
 */
export function formatTimeDisplay(daysLeft, hoursLeft) {
  if (daysLeft === null || daysLeft === undefined) {
    return 'Date unknown';
  }
  if (daysLeft < 0) {
    const daysAgo = Math.abs(daysLeft);
    // Show years if more than 365 days ago
    if (daysAgo >= 365) {
      const yearsAgo = Math.floor(daysAgo / 365);
      const remainingDays = daysAgo % 365;
      const monthsAgo = Math.floor(remainingDays / 30);
      if (monthsAgo > 0) {
        return `Ended ${yearsAgo} ${yearsAgo === 1 ? 'year' : 'years'}, ${monthsAgo} ${monthsAgo === 1 ? 'month' : 'months'} ago`;
      }
      return `Ended ${yearsAgo} ${yearsAgo === 1 ? 'year' : 'years'} ago`;
    }
    // Show months if more than 30 days ago
    if (daysAgo >= 30) {
      const monthsAgo = Math.floor(daysAgo / 30);
      const remainingDays = daysAgo % 30;
      if (remainingDays > 0) {
        return `Ended ${monthsAgo} ${monthsAgo === 1 ? 'month' : 'months'}, ${remainingDays} ${remainingDays === 1 ? 'day' : 'days'} ago`;
      }
      return `Ended ${monthsAgo} ${monthsAgo === 1 ? 'month' : 'months'} ago`;
    }
    return `Ended ${daysAgo} ${daysAgo === 1 ? 'day' : 'days'} ago`;
  }
  if (daysLeft === 0 && hoursLeft !== null) {
    return `Ends in ${hoursLeft} ${hoursLeft === 1 ? 'hour' : 'hours'}!`;
  }
  if (daysLeft === 0) {
    return 'Ends today';
  }
  // Show years if more than 365 days left
  if (daysLeft >= 365) {
    const yearsLeft = Math.floor(daysLeft / 365);
    const remainingDays = daysLeft % 365;
    const monthsLeft = Math.floor(remainingDays / 30);
    if (monthsLeft > 0) {
      return `${yearsLeft} ${yearsLeft === 1 ? 'year' : 'years'}, ${monthsLeft} ${monthsLeft === 1 ? 'month' : 'months'} left`;
    }
    return `${yearsLeft} ${yearsLeft === 1 ? 'year' : 'years'} left`;
  }
  // Show months if more than 30 days left
  if (daysLeft >= 30) {
    const monthsLeft = Math.floor(daysLeft / 30);
    const remainingDays = daysLeft % 30;
    if (remainingDays > 0) {
      return `${monthsLeft} ${monthsLeft === 1 ? 'month' : 'months'}, ${remainingDays} ${remainingDays === 1 ? 'day' : 'days'} left`;
    }
    return `${monthsLeft} ${monthsLeft === 1 ? 'month' : 'months'} left`;
  }
  return `${daysLeft} ${daysLeft === 1 ? 'day' : 'days'} left`;
}

/**
 * Render a simple proposal widget (legacy function)
 */
export function renderProposalWidget(container, proposalData, originalUrl) {
  console.log("🎨 [RENDER] Rendering widget with data:", proposalData);
  
  if (!container) {
    console.error("❌ [RENDER] Container is null!");
    return;
  }

  const activeStatuses = ["active", "pending", "open"];
  const executedStatuses = ["executed", "crosschainexecuted", "completed"];
  const isActive = activeStatuses.includes(proposalData.status?.toLowerCase());
  const isExecuted = executedStatuses.includes(proposalData.status?.toLowerCase());

  const voteStats = proposalData.voteStats || {};
  const votesFor = voteStats.for?.count || 0;
  const votesAgainst = voteStats.against?.count || 0;
  const votesAbstain = voteStats.abstain?.count || 0;
  const totalVotes = voteStats.total || 0;

  const percentFor = voteStats.for?.percent ? Number(voteStats.for.percent).toFixed(2) : (totalVotes > 0 ? ((votesFor / totalVotes) * 100).toFixed(2) : "0.00");
  const percentAgainst = voteStats.against?.percent ? Number(voteStats.against.percent).toFixed(2) : (totalVotes > 0 ? ((votesAgainst / totalVotes) * 100).toFixed(2) : "0.00");
  const percentAbstain = voteStats.abstain?.percent ? Number(voteStats.abstain.percent).toFixed(2) : (totalVotes > 0 ? ((votesAbstain / totalVotes) * 100).toFixed(2) : "0.00");

  // Use title from API, not ID
  const displayTitle = proposalData.title || "Snapshot Proposal";
  console.log("🎨 [RENDER] Display title:", displayTitle);

  container.innerHTML = `
    <div class="arbitrium-proposal-widget">
      <div class="proposal-content">
        <h4 class="proposal-title">
          <a href="${originalUrl}" target="_blank" rel="noopener">
            ${displayTitle}
          </a>
        </h4>
        ${proposalData.description ? (() => {
          const descLines = proposalData.description.split('\n');
          const preview = descLines.slice(0, 5).join('\n');
          const hasMore = descLines.length > 5;
          return `<div class="proposal-description">${preview.replace(/`/g, '\\`').replace(/\${/g, '\\${')}${hasMore ? '...' : ''}</div>`;
        })() : ""}
        ${proposalData.proposer?.name ? `<div class="proposal-author"><span class="author-label">Author:</span><span class="author-name">${(proposalData.proposer.name || '').replace(/`/g, '\\`')}</span></div>` : ""}
      </div>
      <div class="proposal-sidebar">
        <div class="status-badge ${isActive ? 'active' : isExecuted ? 'executed' : 'inactive'}">
          ${isActive ? 'ACTIVE' : isExecuted ? 'EXECUTED' : 'INACTIVE'}
        </div>
        ${totalVotes > 0 ? `
          <div class="voting-section">
            <div class="voting-bar">
              <div class="vote-option vote-for">
                <div class="vote-label-row">
                  <span class="vote-label">For</span>
                  <span class="vote-amount">${formatVoteAmount(votesFor)}</span>
                </div>
                <div class="vote-bar">
                  <div class="vote-fill vote-for" style="width: ${percentFor}%">${percentFor}%</div>
                </div>
              </div>
              <div class="vote-option vote-against">
                <div class="vote-label-row">
                  <span class="vote-label">Against</span>
                  <span class="vote-amount">${formatVoteAmount(votesAgainst)}</span>
                </div>
                <div class="vote-bar">
                  <div class="vote-fill vote-against" style="width: ${percentAgainst}%">${percentAgainst}%</div>
                </div>
              </div>
              <div class="vote-option vote-abstain">
                <div class="vote-label-row">
                  <span class="vote-label">Abstain</span>
                  <span class="vote-amount">${formatVoteAmount(votesAbstain)}</span>
                </div>
                <div class="vote-bar">
                  <div class="vote-fill vote-abstain" style="width: ${percentAbstain}%">${percentAbstain}%</div>
                </div>
              </div>
            </div>
            <a href="${originalUrl}" target="_blank" rel="noopener" class="vote-button">
              Vote on Snapshot
            </a>
          </div>
        ` : `
          <a href="${originalUrl}" target="_blank" rel="noopener" class="vote-button">
            View on Snapshot
          </a>
        `}
      </div>
    </div>
  `;
}

/**
 * Show network error widget
 */
export function showNetworkErrorWidget(count, type, getOrCreateWidgetsContainerFn) {
  const errorWidgetId = 'governance-error-widget';
  const existingError = document.getElementById(errorWidgetId);
  if (existingError) {
    existingError.remove();
  }
  
  const errorWidget = document.createElement("div");
  errorWidget.id = errorWidgetId;
  errorWidget.className = "tally-status-widget-container";
  errorWidget.setAttribute("data-widget-type", "error");
  
  errorWidget.innerHTML = `
    <div class="tally-status-widget" style="background: #fff; border: 1px solid #fca5a5; border-radius: 8px; padding: 16px;">
      <div style="font-weight: 700; font-size: 1em; margin-bottom: 12px; color: #dc2626;">⚠️ Network Error</div>
      <div style="font-size: 0.9em; color: #6b7280; line-height: 1.5; margin-bottom: 12px;">
        Unable to load ${count} ${type} proposal(s). This may be a temporary network issue.
      </div>
      <div style="font-size: 0.85em; color: #9ca3af;">
        The Snapshot API may be temporarily unavailable. Please try refreshing the page.
      </div>
    </div>
  `;
  
  // Add to container if it exists, otherwise create one
  const container = getOrCreateWidgetsContainerFn();
  if (container) {
    container.appendChild(errorWidget);
  } else {
    // Fallback: append to body if no container
    document.body.appendChild(errorWidget);
  }
  console.log(`⚠️ [ERROR] Showing error widget for ${count} failed ${type} proposal(s)`);
}

/**
 * Hide widget if no proposal
 */
export function hideWidgetIfNoProposal() {
  const allWidgets = document.querySelectorAll('.tally-status-widget-container');
  const widgetCount = allWidgets.length;
  allWidgets.forEach(widget => {
    // Remove widget from DOM completely, not just hide it
    widget.remove();
    // Clean up stored data
    const widgetId = widget.getAttribute('data-tally-status-id');
    if (widgetId) {
      delete window[`tallyWidget_${widgetId}`];
      // Clear any auto-refresh intervals
      const refreshKey = `tally_refresh_${widgetId}`;
      if (window[refreshKey]) {
        clearInterval(window[refreshKey]);
        delete window[refreshKey];
      }
    }
  });
  
  // Clean up empty container
  const container = document.getElementById('governance-widgets-wrapper');
  if (container && container.children.length === 0) {
    container.remove();
    console.log("🔵 [CONTAINER] Removed empty widgets container");
  }
  
  if (widgetCount > 0) {
    console.log("🔵 [WIDGET] Removed", widgetCount, "widget(s) - no proposal in current post");
  }
}

/**
 * Show widget
 */
export function showWidget() {
  const allWidgets = document.querySelectorAll('.tally-status-widget-container');
  allWidgets.forEach(widget => {
    widget.style.display = '';
    widget.style.visibility = '';
  });
}

