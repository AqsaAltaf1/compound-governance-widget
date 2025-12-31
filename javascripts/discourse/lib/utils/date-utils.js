// Date calculation utilities

/**
 * Calculate daysLeft and hoursLeft from end timestamp (in seconds)
 * Returns { daysLeft: number|null, hoursLeft: number|null }
 */
export function calculateTimeRemaining(endTimestampSeconds) {
  if (!endTimestampSeconds || endTimestampSeconds <= 0) {
    return { daysLeft: null, hoursLeft: null };
  }
  
  const endTimestampMs = endTimestampSeconds * 1000;
  const now = Date.now();
  const diffTime = endTimestampMs - now;
  const diffTimeInDays = diffTime / (1000 * 60 * 60 * 24);
  
  // Use Math.floor for positive values (remaining full days)
  // Use Math.ceil for negative values (past dates)
  let diffDays;
  if (diffTimeInDays >= 0) {
    diffDays = Math.floor(diffTimeInDays);
  } else {
    diffDays = Math.ceil(diffTimeInDays);
  }
  
  // Validate that diffDays is a valid number
  if (!isNaN(diffDays) && isFinite(diffDays)) {
    const daysLeft = diffDays;
    let hoursLeft = null;
    
    // If it ends today (daysLeft === 0), calculate hours left
    if (diffDays === 0 && diffTime > 0) {
      const diffTimeInHours = diffTime / (1000 * 60 * 60);
      hoursLeft = Math.floor(diffTimeInHours);
    }
    
    return { daysLeft, hoursLeft };
  }
  
  return { daysLeft: null, hoursLeft: null };
}

