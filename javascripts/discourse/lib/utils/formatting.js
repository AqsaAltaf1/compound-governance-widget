// Formatting utilities

/**
 * Escape HTML for safe insertion
 */
export function escapeHtml(unsafe) {
  if (!unsafe) {
    return '';
  }
  return String(unsafe)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

/**
 * Format vote amount for display (e.g., 1.14M, 51.74K)
 */
export function formatVoteAmount(amount) {
  if (!amount || amount === 0) {
    return "0";
  }

  // Convert from wei (18 decimals) to tokens
  // Always assume amounts are in wei if they're very large
  let tokens = amount;
  if (amount >= 1000000000000000) {
    // Convert from wei to tokens (divide by 10^18)
    tokens = amount / 1000000000000000000;
  }
  
  // Format numbers: 1.14M, 0.03, 51.74K, etc.
  if (tokens >= 1000000) {
    const millions = tokens / 1000000;
    return parseFloat(millions.toFixed(2)) + "M";
  }
  if (tokens >= 1000) {
    const thousands = tokens / 1000;
    return parseFloat(thousands.toFixed(2)) + "K";
  }
  // For numbers less than 1000, show 2 decimal places, remove trailing zeros
  const formatted = parseFloat(tokens.toFixed(2));
  return formatted.toString();
}

/**
 * Format status for display - works for all proposal types
 */
export function formatStatusForDisplay(statusValue) {
  if (!statusValue) {
    return 'Unknown';
  }

  const normalized = (statusValue || '').toLowerCase().trim();
  
  const statusMap = {
    'defeated': 'Defeated',
    'defeat': 'Defeated',
    'rejected': 'Rejected',
    'failed': 'Failed',
    'cancelled': 'Cancelled',
    'canceled': 'Cancelled',
    'expired': 'Expired',
    'executed': 'Executed',
    'crosschainexecuted': 'Executed',
    'completed': 'Completed',
    'passed': 'Passed',
    'active': 'Active',
    'open': 'Active',
    'voting': 'Active',
    'created': 'Created',
    'pending': 'Pending',
    'queued': 'Queued',
    'closed': 'Closed',
    'ended': 'Ended',
    'quorum not reached': 'Quorum Not Reached',
    'quorumnotreached': 'Quorum Not Reached',
    'pending execution': 'Pending Execution',
    'pendingexecution': 'Pending Execution',
  };

  // Check exact match first
  if (statusMap[normalized]) {
    return statusMap[normalized];
  }
  
  // Check for partial matches
  for (const [key, display] of Object.entries(statusMap)) {
    if (normalized.includes(key) || key.includes(normalized)) {
      return display;
    }
  }
  
  // Default: capitalize first letter, preserve rest
  return statusValue.charAt(0).toUpperCase() + statusValue.slice(1);
}

