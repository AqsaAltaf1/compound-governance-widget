// Multi-stage widget renderer (Temp Check, ARFC, AIP)

import { formatVoteAmount, formatStatusForDisplay } from "../utils/formatting";
import { formatTimeDisplay, getOrCreateWidgetsContainer } from "./renderer";

/**
 * Render Snapshot stage section (Temp Check or ARFC)
 */
function renderSnapshotStage(stageData, stageUrl, stageName, formatTimeDisplayFn) {
  if (!stageData) {
    return '';
  }
  
  console.log(`🔵 [RENDER] Rendering ${stageName} stage with data:`, stageData);
  
  // Calculate support percentage from vote stats - always recalculate from actual votes
  const forVotes = Number(stageData.voteStats?.for?.count || 0);
  const againstVotes = Number(stageData.voteStats?.against?.count || 0);
  const abstainVotes = Number(stageData.voteStats?.abstain?.count || 0);
  const totalVotes = forVotes + againstVotes + abstainVotes;
  
  // Always calculate support percent from actual vote counts (most reliable)
  let supportPercent = totalVotes > 0 ? ((forVotes / totalVotes) * 100) : 0;
  
  // Fallback: use voteStats.for.percent if calculation gives 0 but we have votes
  if (supportPercent === 0 && totalVotes > 0 && stageData.voteStats?.for?.percent) {
    supportPercent = Number(stageData.voteStats.for.percent);
  }
  // Fallback: use stored supportPercent if calculation is 0 but stored value exists
  if (supportPercent === 0 && stageData.supportPercent && stageData.supportPercent > 0) {
    supportPercent = Number(stageData.supportPercent);
  }
  
  console.log(`🔵 [RENDER] ${stageName} - For: ${forVotes}, Against: ${againstVotes}, Total: ${totalVotes}, Support: ${supportPercent}%`);
  
  // Use actual status from API and format it properly (shows Defeated, Rejected, Failed, etc.)
  const rawStatus = stageData.status || 'unknown';
  const status = formatStatusForDisplay(rawStatus);
  
  // Determine CSS class based on status for styling
  const statusLower = rawStatus.toLowerCase();
  const isActive = statusLower === 'active' || statusLower === 'open' || statusLower === 'voting';
  const isExecuted = statusLower === 'executed' || statusLower === 'crosschainexecuted' || statusLower === 'completed' || statusLower === 'passed';
  const isDefeated = statusLower === 'defeated' || statusLower === 'defeat' || statusLower === 'rejected' || statusLower === 'failed';
  const isQuorumNotReached = statusLower.includes('quorum not reached') || statusLower.includes('quorumnotreached');
  const isCancelled = statusLower === 'cancelled' || statusLower === 'canceled';
  const isExpired = statusLower === 'expired';
  const isQueued = statusLower === 'queued' || statusLower === 'queuing';
  const isPending = statusLower === 'pending' || statusLower.includes('pending execution');
  
  const statusClass = isActive ? 'active' :
                     isExecuted ? 'executed' :
                     isDefeated || isQuorumNotReached ? 'defeated' :
                     isCancelled ? 'cancelled' :
                     isExpired ? 'expired' :
                     isQueued ? 'queued' :
                     isPending ? 'pending' :
                     'inactive';
  const timeDisplay = formatTimeDisplayFn(stageData.daysLeft, stageData.hoursLeft);
  
  // Calculate percentages for progress bar
  const forPercent = totalVotes > 0 ? (forVotes / totalVotes) * 100 : 0;
  const againstPercent = totalVotes > 0 ? (againstVotes / totalVotes) * 100 : 0;
  const abstainPercent = totalVotes > 0 ? (abstainVotes / totalVotes) * 100 : 0;
  
  // Progress bar HTML
  const progressBarHtml = totalVotes > 0 ? `
    <div class="progress-bar-container" style="margin-top: 8px; margin-bottom: 8px;">
      <div class="progress-bar">
        ${forPercent > 0 ? `<div class="progress-segment progress-for" style="width: ${forPercent}%"></div>` : ''}
        ${againstPercent > 0 ? `<div class="progress-segment progress-against" style="width: ${againstPercent}%"></div>` : ''}
        ${abstainPercent > 0 ? `<div class="progress-segment progress-abstain" style="width: ${abstainPercent}%"></div>` : ''}
      </div>
    </div>
  ` : '';
  
  // Determine if ended - includes passed and executed statuses, or daysLeft < 0
  // Use case-insensitive comparison for status
  const statusLower2 = (stageData.status || '').toLowerCase();
  const isEnded = (stageData.daysLeft !== null && stageData.daysLeft < 0) ||
                  statusLower2 === 'executed' || 
                  statusLower2 === 'passed' ||
                  statusLower2 === 'queued' ||
                  statusLower2 === 'failed' ||
                  statusLower2 === 'cancelled' ||
                  statusLower2 === 'expired';
  
  // Format "Ended X days ago" text - use months if >30 days, years if >365 days
  let endedText = '';
  if (isEnded && stageData.daysLeft !== null && stageData.daysLeft !== undefined) {
    const daysAgo = Math.abs(Math.floor(stageData.daysLeft));
    if (daysAgo === 0) {
      endedText = 'Ended today';
    } else if (daysAgo === 1) {
      endedText = 'Ended 1 day ago';
    } else if (daysAgo >= 365) {
      // Show years if more than 365 days ago
      const yearsAgo = Math.floor(daysAgo / 365);
      const remainingDays = daysAgo % 365;
      const monthsAgo = Math.floor(remainingDays / 30);
      if (monthsAgo > 0) {
        endedText = `Ended ${yearsAgo} ${yearsAgo === 1 ? 'year' : 'years'}, ${monthsAgo} ${monthsAgo === 1 ? 'month' : 'months'} ago`;
      } else {
        endedText = yearsAgo === 1 ? 'Ended 1 year ago' : `Ended ${yearsAgo} years ago`;
      }
    } else if (daysAgo >= 30) {
      // Show months if more than 30 days ago
      const monthsAgo = Math.floor(daysAgo / 30);
      const remainingDays = daysAgo % 30;
      if (remainingDays > 0) {
        endedText = `Ended ${monthsAgo} ${monthsAgo === 1 ? 'month' : 'months'}, ${remainingDays} ${remainingDays === 1 ? 'day' : 'days'} ago`;
      } else {
        endedText = monthsAgo === 1 ? 'Ended 1 month ago' : `Ended ${monthsAgo} months ago`;
      }
    } else {
      endedText = `Ended ${daysAgo} days ago`;
    }
  }
  
  // For ended proposals, wrap in collapsible container
  const stageId = `stage-${stageName.toLowerCase().replace(/\s+/g, '-')}-${Date.now()}`;
  const collapsedContent = isEnded ? `
    <div class="stage-collapsed-content" id="${stageId}-content" style="display: none;">
      ${progressBarHtml}
      <div style="font-size: 0.85em; color: #6b7280; margin-top: 4px; margin-bottom: 8px; line-height: 1.5;">
        <strong style="color: #10b981;">For: ${formatVoteAmount(forVotes)}</strong> | 
        <strong style="color: #ef4444;">Against: ${formatVoteAmount(againstVotes)}</strong> | 
        <strong style="color: #6b7280;">Abstain: ${formatVoteAmount(abstainVotes)}</strong>
      </div>
      <a href="${stageUrl}" target="_blank" rel="noopener" class="vote-button" style="display: block; width: 100%; padding: 8px 12px; border: none; border-radius: 4px; font-size: 0.85em; font-weight: 600; text-align: center; text-decoration: none; margin-top: 10px; box-sizing: border-box; background-color: #e5e7eb !important; color: #6b7280 !important;">
        View on Snapshot
      </a>
    </div>
  ` : `
    ${progressBarHtml}
    <div style="font-size: 0.85em; color: #6b7280; margin-top: 4px; margin-bottom: 8px; line-height: 1.5;">
      <strong style="color: #10b981;">For: ${formatVoteAmount(forVotes)}</strong> | 
      <strong style="color: #ef4444;">Against: ${formatVoteAmount(againstVotes)}</strong> | 
      <strong style="color: #6b7280;">Abstain: ${formatVoteAmount(abstainVotes)}</strong>
    </div>
    <a href="${stageUrl}" target="_blank" rel="noopener" class="vote-button" style="display: block; width: 100%; padding: 8px 12px; border: none; border-radius: 4px; font-size: 0.85em; font-weight: 600; text-align: center; text-decoration: none; margin-top: 10px; box-sizing: border-box; background-color: var(--d-button-primary-bg-color, #2563eb) !important; color: var(--d-button-primary-text-color, white) !important;">
      Vote on Snapshot
    </a>
  `;
  
  return `
    <div class="governance-stage ${isEnded ? 'stage-ended' : ''}">
      <div style="display: flex; justify-content: space-between; align-items: center; font-weight: 600; font-size: 0.9em; margin-bottom: 8px; color: #111827; padding-right: 32px;">
        <span>${stageName} (Snapshot)</span>
        <div style="display: flex; align-items: center; gap: 8px;">
          <div class="status-badge ${statusClass}">
            ${status}
          </div>
        </div>
      </div>
      ${endedText || (!isEnded && timeDisplay) ? `
        <div style="margin-bottom: 12px;">
          <div class="days-left-badge" style="padding: 4px 10px; border-radius: 4px; font-size: 0.7em; font-weight: 600; color: #6b7280; white-space: nowrap;">
            ${endedText || timeDisplay}
          </div>
        </div>
      ` : ''}
      ${isEnded ? `
        <div id="${stageId}-collapse-container" style="display: flex; align-items: center; gap: 4px; margin-bottom: 8px; font-size: 0.8em; color: #9ca3af; font-style: italic; line-height: 1.4;">
          <button class="stage-toggle-btn" data-stage-id="${stageId}" style="background: transparent; border: none; cursor: pointer; color: #6b7280; font-size: 14px; padding: 0; margin: 0; width: 18px; height: 18px; display: flex; align-items: center; justify-content: center; border-radius: 4px; transition: all 0.2s; flex-shrink: 0;" title="Click to expand">
            <span id="${stageId}-icon">▶</span>
          </button>
          <span id="${stageId}-collapsed-text" style="flex: 1;">[Collapsed by default]</span>
        </div>
      ` : ''}
      ${collapsedContent}
    </div>
  `;
}

/**
 * Render AIP stage section
 */
function renderAIPStage(stageData, stageUrl, formatTimeDisplayFn) {
  if (!stageData) {
    return '';
  }
  
  console.log('🔵 [RENDER] Rendering AIP stage with data:', stageData);
  
  // Use exact status from API and format it properly
  const rawStatus = stageData.status || 'unknown';
  const status = formatStatusForDisplay(rawStatus);
  // Map status to CSS class for styling
  // "passed" means proposal passed voting but hasn't been executed yet (different from "executed")
  const statusClass = stageData.status === 'active' ? 'active' : 
                     stageData.status === 'executed' ? 'executed' :
                     stageData.status === 'passed' ? 'passed' :
                     stageData.status === 'queued' ? 'queued' :
                     stageData.status === 'failed' ? 'failed' :
                     stageData.status === 'cancelled' ? 'cancelled' :
                     stageData.status === 'expired' ? 'expired' : 'inactive';
  
  // Calculate percentages from vote counts - use actual vote counts
  // The Graph API returns forVotes/againstVotes directly, not in voteStats
  // NOTE: Aave V3 does NOT support abstain votes - only For/Against
  // Handle null votes (not available from subgraph) - common for failed/cancelled proposals
  const forVotesRaw = stageData.forVotes;
  const againstVotesRaw = stageData.againstVotes;
  const votesAvailable = forVotesRaw !== null && forVotesRaw !== undefined && 
                        againstVotesRaw !== null && againstVotesRaw !== undefined;
  
  const forVotes = votesAvailable ? Number(forVotesRaw || 0) : null;
  const againstVotes = votesAvailable ? Number(againstVotesRaw || 0) : null;
  const totalVotes = votesAvailable ? (forVotes + againstVotes) : null; // No abstain in Aave V3
  
  // Use percent from voteStats if available, otherwise calculate
  let forPercent = stageData.voteStats?.for?.percent;
  let againstPercent = stageData.voteStats?.against?.percent;
  
  // Only calculate percentages if votes are available
  if (votesAvailable && totalVotes !== null && totalVotes > 0) {
    if (forPercent === undefined || forPercent === null) {
      forPercent = (forVotes / totalVotes) * 100;
    } else {
      forPercent = Number(forPercent);
    }
    
    if (againstPercent === undefined || againstPercent === null) {
      againstPercent = (againstVotes / totalVotes) * 100;
    } else {
      againstPercent = Number(againstPercent);
    }
  } else {
    forPercent = 0;
    againstPercent = 0;
  }
  
  // Get quorum - use the actual quorum value from data (already converted from wei to AAVE)
  const quorum = Number(stageData.quorum || 0);
  // For quorum calculation, use totalVotes (current votes) vs quorum (required votes)
  // Only calculate if votes are available
  const quorumPercent = (quorum > 0 && totalVotes !== null && totalVotes > 0) ? (totalVotes / quorum) * 100 : 0;
  const quorumReached = quorum > 0 && totalVotes !== null && totalVotes >= quorum;
  
  console.log(`🔵 [RENDER] AIP - For: ${forVotes !== null ? forVotes : 'N/A'} (${forPercent}%), Against: ${againstVotes !== null ? againstVotes : 'N/A'} (${againstPercent}%), Total: ${totalVotes !== null ? totalVotes : 'N/A'}, Quorum: ${quorum} (${quorumPercent}%) - Reached: ${quorumReached}`);
  
  const timeDisplay = formatTimeDisplayFn(stageData.daysLeft, stageData.hoursLeft);
  
  // Extract AIP number from title if possible
  const aipMatch = stageData.title.match(/AIP[#\s]*(\d+)/i);
  const aipNumber = aipMatch ? `#${aipMatch[1]}` : '';
  
  // Determine if ended - includes passed and executed statuses, or daysLeft < 0
  // "passed" means proposal passed voting but is waiting to be executed - should be collapsed
  // "executed" means proposal has been executed on-chain - should be collapsed
  // Use case-insensitive comparison for status
  const statusLower = (stageData.status || '').toLowerCase();
  const isEnded = (stageData.daysLeft !== null && stageData.daysLeft < 0) ||
                 statusLower === 'executed' || 
                 statusLower === 'passed' ||
                 statusLower === 'queued' || 
                 statusLower === 'failed' || 
                 statusLower === 'cancelled' || 
                 statusLower === 'expired';
  
  // Format end date (if we have daysLeft, calculate when it ended)
  // Use months if >30 days, years if >365 days
  let endDateText = '';
  if (isEnded && stageData.daysLeft !== null && stageData.daysLeft !== undefined) {
    const daysAgo = Math.abs(Math.floor(stageData.daysLeft));
    if (daysAgo === 0) {
      endDateText = 'Ended today';
    } else if (daysAgo === 1) {
      endDateText = 'Ended 1 day ago';
    } else if (daysAgo >= 365) {
      // Show years if more than 365 days ago
      const yearsAgo = Math.floor(daysAgo / 365);
      const remainingDays = daysAgo % 365;
      const monthsAgo = Math.floor(remainingDays / 30);
      if (monthsAgo > 0) {
        endDateText = `Ended ${yearsAgo} ${yearsAgo === 1 ? 'year' : 'years'}, ${monthsAgo} ${monthsAgo === 1 ? 'month' : 'months'} ago`;
      } else {
        endDateText = yearsAgo === 1 ? 'Ended 1 year ago' : `Ended ${yearsAgo} years ago`;
      }
    } else if (daysAgo >= 30) {
      // Show months if more than 30 days ago
      const monthsAgo = Math.floor(daysAgo / 30);
      const remainingDays = daysAgo % 30;
      if (remainingDays > 0) {
        endDateText = `Ended ${monthsAgo} ${monthsAgo === 1 ? 'month' : 'months'}, ${remainingDays} ${remainingDays === 1 ? 'day' : 'days'} ago`;
      } else {
        endDateText = monthsAgo === 1 ? 'Ended 1 month ago' : `Ended ${monthsAgo} months ago`;
      }
    } else {
      endDateText = `Ended ${daysAgo} days ago`;
    }
  } else if (isEnded) {
    endDateText = 'Ended';
  }
  
  // Use formatted status (already formatted by formatStatusForDisplay)
  const statusBadgeText = status;
  
  // For cancelled and failed proposals, voting never happened - don't show vote data
  const isCancelledOrFailed = stageData.status === 'cancelled' || stageData.status === 'failed';
  const shouldShowVotes = !isCancelledOrFailed && votesAvailable && totalVotes !== null && totalVotes > 0;
  
  // Progress bar HTML - For AIP: show For/Against votes, no abstain
  // Only show progress bar if votes are available AND proposal is not cancelled/failed
  const progressBarHtml = shouldShowVotes ? `
    <div class="progress-bar-container" style="margin-top: 8px; margin-bottom: 8px;">
      <div class="progress-bar">
        ${forPercent > 0 ? `<div class="progress-segment progress-for" style="width: ${forPercent}%"></div>` : ''}
        ${againstPercent > 0 ? `<div class="progress-segment progress-against" style="width: ${againstPercent}%"></div>` : ''}
      </div>
    </div>
  ` : '';
  
  // Quorum display for AIP (instead of abstain)
  // Only show quorum if votes are available AND proposal is not cancelled/failed
  const quorumHtml = (quorum > 0 && shouldShowVotes) ? `
    <div style="font-size: 0.85em; color: #6b7280; margin-top: 8px; margin-bottom: 8px; padding: 8px; background: ${quorumReached ? '#f0fdf4' : '#fef2f2'}; border-radius: 4px; border-left: 3px solid ${quorumReached ? '#10b981' : '#ef4444'};">
        <strong style="color: #111827;">Quorum:</strong> ${formatVoteAmount(totalVotes)} / ${formatVoteAmount(quorum)} AAVE 
        <span style="color: ${quorumReached ? '#10b981' : '#ef4444'}; font-weight: 600;">
          (${Math.round(quorumPercent)}% - ${quorumReached ? '✓ Reached' : '✗ Not Reached'})
        </span>
    </div>
  ` : '';
  
  // For ended proposals, wrap in collapsible container
  const stageId = `stage-aip-${Date.now()}`;
  const collapsedContent = isEnded ? `
    <div class="stage-collapsed-content" id="${stageId}-content" style="display: none;">
      ${progressBarHtml}
      ${shouldShowVotes ? `
        <div style="font-size: 0.85em; color: #6b7280; margin-top: 4px; margin-bottom: 8px; line-height: 1.5;">
          <strong style="color: #10b981;">For: ${formatVoteAmount(forVotes)}</strong> | 
          <strong style="color: #ef4444;">Against: ${formatVoteAmount(againstVotes)}</strong>
        </div>
      ` : isCancelledOrFailed ? `
        <div style="font-size: 0.85em; color: #9ca3af; margin-top: 4px; margin-bottom: 8px; line-height: 1.5; font-style: italic;">
          ${stageData.status === 'cancelled' ? 'Voting was cancelled before it started' : 'Voting failed - no vote data available'}
        </div>
      ` : `
        <div style="font-size: 0.85em; color: #9ca3af; margin-top: 4px; margin-bottom: 8px; line-height: 1.5; font-style: italic;">
          Vote data not available from subgraph
        </div>
      `}
      ${quorumHtml}
      <a href="${stageUrl}" target="_blank" rel="noopener" class="vote-button" style="display: block; width: 100%; padding: 8px 12px; border: none; border-radius: 4px; font-size: 0.85em; font-weight: 600; text-align: center; text-decoration: none; margin-top: 10px; box-sizing: border-box; background-color: #e5e7eb !important; color: #6b7280 !important;">
        View on Aave
      </a>
    </div>
  ` : `
    ${progressBarHtml}
    ${shouldShowVotes ? `
      <div style="font-size: 0.85em; color: #6b7280; margin-top: 4px; margin-bottom: 8px; line-height: 1.5;">
        <strong style="color: #10b981;">For: ${formatVoteAmount(forVotes)}</strong> | 
        <strong style="color: #ef4444;">Against: ${formatVoteAmount(againstVotes)}</strong>
      </div>
    ` : isCancelledOrFailed ? `
      <div style="font-size: 0.85em; color: #9ca3af; margin-top: 4px; margin-bottom: 8px; line-height: 1.5; font-style: italic;">
        ${stageData.status === 'cancelled' ? 'Voting was cancelled before it started' : 'Voting failed - no vote data available'}
      </div>
    ` : `
      <div style="font-size: 0.85em; color: #9ca3af; margin-top: 4px; margin-bottom: 8px; line-height: 1.5; font-style: italic;">
        Vote data not available from subgraph
      </div>
    `}
    ${quorumHtml}
    <a href="${stageUrl}" target="_blank" rel="noopener" class="vote-button" style="display: block; width: 100%; padding: 8px 12px; border: none; border-radius: 4px; font-size: 0.85em; font-weight: 600; text-align: center; text-decoration: none; margin-top: 10px; box-sizing: border-box; background-color: var(--d-button-primary-bg-color, #2563eb) !important; color: var(--d-button-primary-text-color, white) !important;">
      Vote on Aave
    </a>
  `;
  
  return `
    <div class="governance-stage ${isEnded ? 'stage-ended' : ''}">
      <div style="display: flex; justify-content: space-between; align-items: center; font-weight: 600; font-size: 0.9em; margin-bottom: 8px; color: #111827; padding-right: 32px;">
        <span>AIP (On-Chain) ${aipNumber}</span>
        <div style="display: flex; align-items: center; gap: 8px;">
          <div class="status-badge ${statusClass}">
            ${statusBadgeText}
          </div>
        </div>
      </div>
      ${(endDateText && endDateText !== 'Ended') || (!isEnded && timeDisplay) ? `
        <div style="margin-bottom: 12px;">
          <div class="days-left-badge" style="padding: 4px 10px; border-radius: 4px; font-size: 0.7em; font-weight: 600; color: #6b7280; white-space: nowrap;">
            ${endDateText && endDateText !== 'Ended' ? endDateText : timeDisplay}
          </div>
        </div>
      ` : ''}
      ${isEnded ? `
        <div id="${stageId}-collapse-container" style="display: flex; align-items: center; gap: 4px; margin-bottom: 8px; font-size: 0.8em; color: #9ca3af; font-style: italic; line-height: 1.4;">
          <button class="stage-toggle-btn" data-stage-id="${stageId}" style="background: transparent; border: none; cursor: pointer; color: #6b7280; font-size: 14px; padding: 0; margin: 0; width: 18px; height: 18px; display: flex; align-items: center; justify-content: center; border-radius: 4px; transition: all 0.2s; flex-shrink: 0;" title="Click to expand">
            <span id="${stageId}-icon">▶</span>
          </button>
          <span id="${stageId}-collapsed-text" style="flex: 1;">[Collapsed by default]</span>
        </div>
      ` : ''}
      ${collapsedContent}
    </div>
  `;
}

/**
 * Render multi-stage widget showing Temp Check, ARFC, and AIP all together
 */
export function renderMultiStageWidget(stages, widgetId, proposalOrder, renderingUrls, fetchingUrls) {
  const statusWidgetId = `aave-governance-widget-${widgetId}`;
  
  // Determine widget type - if all stages are present, use 'combined', otherwise use specific type
  const hasSnapshotStages = stages.tempCheck || stages.arfc;
  const hasAllStages = hasSnapshotStages && stages.aip;
  const widgetType = hasAllStages ? 'combined' : (stages.aip ? 'aip' : 'snapshot');
  
  // Get the URL from stages to check for duplicates by URL (more reliable than ID)
  const proposalUrl = stages.aipUrl || stages.arfcUrl || stages.tempCheckUrl || null;
  
  // SPECIAL HANDLING FOR AIP: Remove all existing AIP widgets to ensure only one is shown
  if (stages.aip && stages.aipUrl) {
    const existingAipWidgets = document.querySelectorAll('.tally-status-widget-container[data-proposal-type="aip"]');
    if (existingAipWidgets.length > 0) {
      console.log(`🔵 [RENDER] Found ${existingAipWidgets.length} existing AIP widget(s), removing to prevent duplicates`);
      existingAipWidgets.forEach(widget => {
        const widgetUrl = widget.getAttribute('data-tally-url');
        if (widgetUrl) {
          renderingUrls.delete(widgetUrl);
          fetchingUrls.delete(widgetUrl);
        }
        widget.remove();
      });
    }
  }
  
  // First, check for existing widgets with the same URL to prevent duplicates (check DOM first)
  // This is the same logic used for snapshot widgets - check DOM before checking renderingUrls
  if (proposalUrl) {
    const existingWidgetsByUrl = document.querySelectorAll(`.tally-status-widget-container[data-tally-url="${proposalUrl}"]`);
    if (existingWidgetsByUrl.length > 0) {
      console.log(`🔵 [RENDER] Found ${existingWidgetsByUrl.length} existing widget(s) with same URL, skipping duplicate render`);
      return;
    }
  }
  
  // CRITICAL: Check if this URL is already being rendered (race condition prevention)
  if (proposalUrl && renderingUrls.has(proposalUrl)) {
    console.log(`🔵 [RENDER] URL ${proposalUrl} is already being rendered, skipping duplicate render`);
    return;
  }
  
  // Mark this URL as being rendered
  if (proposalUrl) {
    renderingUrls.add(proposalUrl);
  }
  
  // Remove existing widget with the same ID (to allow re-rendering), but keep others
  // This allows multiple widgets to coexist (one per proposal)
  const existingWidget = document.getElementById(statusWidgetId);
  if (existingWidget) {
    existingWidget.remove();
    console.log(`🔵 [RENDER] Removed existing widget with ID: ${statusWidgetId}`);
  }
  
  console.log(`🔵 [RENDER] Rendering ${widgetType} widget with stages:`, {
    tempCheck: !!stages.tempCheck,
    arfc: !!stages.arfc,
    aip: !!stages.aip
  });
  
  // Debug: Log what data we have for each stage
  if (stages.tempCheck) {
    console.log("🔵 [RENDER] Temp Check data:", {
      title: stages.tempCheck.title,
      status: stages.tempCheck.status,
      stage: stages.tempCheck.stage,
      supportPercent: stages.tempCheck.supportPercent
    });
  } else {
    // This is normal if only ARFC or only AIP is provided (not a warning)
    console.log("ℹ️ [RENDER] No Temp Check data - this is normal if only ARFC/AIP is provided");
  }
  
  if (stages.arfc) {
    console.log("🔵 [RENDER] ARFC data:", {
      title: stages.arfc.title,
      status: stages.arfc.status,
      stage: stages.arfc.stage,
      supportPercent: stages.arfc.supportPercent
    });
  } else {
    // This is normal if only Temp Check or only AIP is provided (not a warning)
    console.log("ℹ️ [RENDER] No ARFC data - this is normal if only Temp Check/AIP is provided");
  }
  
  const statusWidget = document.createElement("div");
  statusWidget.id = statusWidgetId;
  statusWidget.className = "tally-status-widget-container";
  statusWidget.setAttribute("data-widget-id", widgetId);
  statusWidget.setAttribute("data-widget-type", widgetType); // Mark widget type
  // Add URL attribute for duplicate detection
  if (proposalUrl) {
    statusWidget.setAttribute("data-tally-url", proposalUrl);
  }
  // Add proposal type for filtering
  const proposalType = stages.aip ? 'aip' : 'snapshot';
  statusWidget.setAttribute("data-proposal-type", proposalType);
  
  // Use proposal order (order in content) for positioning, fallback to stage order
  // Proposal order takes precedence - widgets appear in the order proposals appear in content
  const orderValue = proposalOrder !== null ? proposalOrder : 
    (hasAllStages ? 3 : (stages.tempCheck && !stages.arfc && !stages.aip ? 1 : 
    (stages.arfc && !stages.aip ? 2 : 3)));
  
  // Set both attributes for compatibility
  statusWidget.setAttribute("data-proposal-order", orderValue);
  statusWidget.setAttribute("data-stage-order", orderValue); // Keep for backward compatibility
  
  // Build stage HTML separately for debugging
  const tempCheckHTML = stages.tempCheck ? renderSnapshotStage(stages.tempCheck, stages.tempCheckUrl, 'Temp Check', formatTimeDisplay) : '';
  const arfcHTML = stages.arfc ? renderSnapshotStage(stages.arfc, stages.arfcUrl, 'ARFC', formatTimeDisplay) : '';
  const aipHTML = stages.aip ? renderAIPStage(stages.aip, stages.aipUrl, formatTimeDisplay) : '';
  
  console.log(`🔵 [RENDER] Generated HTML lengths - Temp Check: ${tempCheckHTML.length}, ARFC: ${arfcHTML.length}, AIP: ${aipHTML.length}`);
  if (tempCheckHTML.length === 0 && stages.tempCheck) {
    console.error("❌ [RENDER] Temp Check data exists but HTML is empty!");
  }
  
  // Check if any stage has ended/passed to use dim background
  const checkStageEnded = (stage) => {
    if (!stage) {
      return false;
    }
    // Check if ended by daysLeft or status
    const isEndedByTime = stage.daysLeft !== null && stage.daysLeft < 0;
    // "passed" means voting ended and proposal passed, but not executed yet
    // "executed" means proposal has been executed on-chain
    // Use case-insensitive comparison for status
    const statusLower = (stage.status || '').toLowerCase();
    const isExecuted = statusLower === 'executed';
    const isPassed = statusLower === 'passed';
    const isQueued = statusLower === 'queued';
    const isFailed = statusLower === 'failed';
    const isCancelled = statusLower === 'cancelled';
    const isExpired = statusLower === 'expired';
    // All these statuses should be dimmed and collapsed (voting is over)
    return isEndedByTime || isExecuted || isPassed || isQueued || isFailed || isCancelled || isExpired;
  };
  
  const hasEndedStage = checkStageEnded(stages.tempCheck) || 
                        checkStageEnded(stages.arfc) || 
                        checkStageEnded(stages.aip);
  
  // Dim ended proposals with opacity instead of changing background color
  const widgetOpacity = hasEndedStage ? 'opacity: 0.6;' : '';
  
  const widgetHTML = `
    <div class="tally-status-widget" style="background: #fff; ${widgetOpacity} border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px; width: 100%; max-width: 100%; box-sizing: border-box; position: relative;">
      <button class="widget-close-btn" style="position: absolute; top: 8px; right: 8px; background: transparent; border: none; font-size: 18px; cursor: pointer; color: #6b7280; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; border-radius: 4px; transition: all 0.2s; z-index: 100;" title="Close widget" onmouseover="this.style.background='#f3f4f6'; this.style.color='#111827';" onmouseout="this.style.background='transparent'; this.style.color='#6b7280';">
        ×
      </button>
      ${tempCheckHTML}
      ${arfcHTML}
      ${aipHTML}
    </div>
  `;
  
  statusWidget.innerHTML = widgetHTML;
  
  // Add close button handler
  const closeBtn = statusWidget.querySelector('.widget-close-btn');
  if (closeBtn) {
    closeBtn.addEventListener('click', () => {
      statusWidget.style.display = 'none';
      statusWidget.remove();
    });
  }
  
  // Set widget styles for column layout
  statusWidget.style.width = '100%';
  statusWidget.style.maxWidth = '100%';
  statusWidget.style.marginBottom = '0';
  
  // Position widget - use container for desktop, inline for mobile
  // Use more reliable mobile detection
  const isMobile = window.innerWidth <= 1024 || 
                   /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
  
  console.log(`🔵 [MOBILE] Detection - window.innerWidth: ${window.innerWidth}, isMobile: ${isMobile}`);
  
  // Ensure widget is visible on mobile
  if (isMobile) {
    statusWidget.style.display = 'block';
    statusWidget.style.visibility = 'visible';
    statusWidget.style.opacity = '1';
    statusWidget.style.position = 'relative';
    statusWidget.style.marginBottom = '20px';
    statusWidget.style.width = '100%';
    statusWidget.style.maxWidth = '100%';
    statusWidget.style.marginLeft = '0';
    statusWidget.style.marginRight = '0';
    statusWidget.style.zIndex = '1';
  }
  
  // Handle mobile positioning (complex logic - see original for full implementation)
  if (isMobile) {
    // On mobile, check if widget is already in the correct position to prevent re-insertion
    if (statusWidget.parentNode) {
      // Widget is already in DOM - check if it's in a valid location
      const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream, .topic-post-stream');
      const firstPost = document.querySelector('.topic-post, .post, [data-post-id], article[data-post-id]');
      
      // If widget is already in a valid location (before posts or in topic body), don't re-insert
      if (topicBody && (topicBody.contains(statusWidget) || 
          (firstPost && firstPost.parentNode && firstPost.parentNode.contains(statusWidget)))) {
        console.log("✅ [MOBILE] Widget already in correct position, skipping re-insertion");
        // Remove URL from rendering set now that widget is confirmed in DOM
        if (proposalUrl) {
          renderingUrls.delete(proposalUrl);
        }
        return; // Exit early - widget is already positioned correctly
      }
    }
    
    // On mobile, use same ordering logic as desktop - new widgets appear at bottom
    // Insert widget in correct order based on stage (temp-check -> arfc -> aip)
    try {
      const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream, .topic-post-stream');
      const firstPost = document.querySelector('.topic-post, .post, [data-post-id], article[data-post-id]');
      
      // Get proposal order for this widget (order in content, not stage order)
      const thisProposalOrder = parseInt(statusWidget.getAttribute("data-proposal-order") || statusWidget.getAttribute("data-stage-order") || "999", 10);
      
      // Find all existing widgets in the insertion area
      let widgetsContainer = null;
      let existingWidgets = [];
      
      if (firstPost && firstPost.parentNode) {
        // Find widgets before the first post
        widgetsContainer = firstPost.parentNode;
        const siblings = Array.from(firstPost.parentNode.children);
        existingWidgets = siblings.filter(sibling => 
          sibling.classList.contains('tally-status-widget-container') && 
          siblings.indexOf(sibling) < siblings.indexOf(firstPost)
        );
      } else if (topicBody) {
        widgetsContainer = topicBody;
        existingWidgets = Array.from(topicBody.querySelectorAll('.tally-status-widget-container'));
      } else {
        const mainContent = document.querySelector('main, .topic-body, .posts-wrapper, [role="main"]');
        if (mainContent) {
          widgetsContainer = mainContent;
          existingWidgets = Array.from(mainContent.querySelectorAll('.tally-status-widget-container'));
        }
      }
      
      if (widgetsContainer && existingWidgets.length > 0) {
        // Find the correct position to insert based on proposal order (order in content)
        let insertBefore = null;
        
        // Find first widget with higher proposal order (or same order, insert after)
        for (const widget of existingWidgets) {
          const widgetProposalOrder = parseInt(widget.getAttribute("data-proposal-order") || widget.getAttribute("data-stage-order") || "999", 10);
          if (widgetProposalOrder > thisProposalOrder) {
            insertBefore = widget;
            break;
          }
        }
        
        if (insertBefore) {
          widgetsContainer.insertBefore(statusWidget, insertBefore);
          console.log(`✅ [MOBILE] Widget inserted in correct order (proposal order: ${thisProposalOrder})`);
        } else {
          // No widget with higher order, append at end (new widgets at bottom)
          if (firstPost && firstPost.parentNode) {
            // Insert before first post (which is after all widgets)
            firstPost.parentNode.insertBefore(statusWidget, firstPost);
          } else if (topicBody) {
            // Append to topic body
            topicBody.appendChild(statusWidget);
          } else {
            const mainContent = document.querySelector('main, .topic-body, .posts-wrapper, [role="main"]');
            if (mainContent) {
              mainContent.appendChild(statusWidget);
            } else {
              document.body.appendChild(statusWidget);
            }
          }
          console.log(`✅ [MOBILE] Widget appended at end (proposal order: ${thisProposalOrder}) - new widget at bottom`);
        }
      } else {
        // No existing widgets, insert before first post or at beginning
        if (firstPost && firstPost.parentNode) {
          firstPost.parentNode.insertBefore(statusWidget, firstPost);
          console.log("✅ [MOBILE] Widget inserted before first post (first widget)");
        } else if (topicBody) {
          if (topicBody.firstChild) {
            topicBody.insertBefore(statusWidget, topicBody.firstChild);
          } else {
            topicBody.appendChild(statusWidget);
          }
          console.log("✅ [MOBILE] Widget inserted in topic body (first widget)");
        } else {
          const mainContent = document.querySelector('main, .topic-body, .posts-wrapper, [role="main"]');
          if (mainContent) {
            if (mainContent.firstChild) {
              mainContent.insertBefore(statusWidget, mainContent.firstChild);
            } else {
              mainContent.appendChild(statusWidget);
            }
            console.log("✅ [MOBILE] Widget inserted in main content (first widget)");
          } else {
            const bodyFirstChild = document.body.firstElementChild || document.body.firstChild;
            if (bodyFirstChild) {
              document.body.insertBefore(statusWidget, bodyFirstChild);
            } else {
              document.body.appendChild(statusWidget);
            }
            console.log("✅ [MOBILE] Widget inserted in body (first widget)");
          }
        }
      }
      
      // Remove URL from rendering set now that widget is in DOM
      if (proposalUrl) {
        renderingUrls.delete(proposalUrl);
      }
    } catch (error) {
      console.error("❌ [MOBILE] Error inserting widget:", error);
      // Remove URL from rendering set on error
      if (proposalUrl) {
        renderingUrls.delete(proposalUrl);
      }
      // Fallback: try to append to a safe location (append at end for new widgets at bottom)
      const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream, main');
      if (topicBody) {
        topicBody.appendChild(statusWidget);
        // Remove URL from rendering set after fallback insert
        if (proposalUrl) {
          renderingUrls.delete(proposalUrl);
        }
      } else {
        document.body.appendChild(statusWidget);
        // Remove URL from rendering set after fallback insert
        if (proposalUrl) {
          renderingUrls.delete(proposalUrl);
        }
      }
    }
  } else {
    // Desktop: Append to container for column layout
    // Insert widget in correct order based on proposal order (order in content)
    const widgetsContainer = getOrCreateWidgetsContainer();
    if (widgetsContainer) {
      // Get proposal order for this widget (order in content, not stage order)
      const thisProposalOrder = parseInt(statusWidget.getAttribute("data-proposal-order") || statusWidget.getAttribute("data-stage-order") || "999", 10);
      
      // Find the correct position to insert based on proposal order
      const existingWidgets = Array.from(widgetsContainer.children);
      let insertBefore = null;
      
      // Find first widget with higher proposal order (or same order, insert after)
      for (const widget of existingWidgets) {
        const widgetProposalOrder = parseInt(widget.getAttribute("data-proposal-order") || widget.getAttribute("data-stage-order") || "999", 10);
        if (widgetProposalOrder > thisProposalOrder) {
          insertBefore = widget;
          break;
        }
      }
      
      if (insertBefore) {
        widgetsContainer.insertBefore(statusWidget, insertBefore);
        console.log(`✅ [DESKTOP] Widget inserted in correct order (proposal order: ${thisProposalOrder})`);
      } else {
        // No widget with higher order, append at end
        widgetsContainer.appendChild(statusWidget);
        console.log(`✅ [DESKTOP] Widget appended at end (proposal order: ${thisProposalOrder})`);
      }
      
      // Remove URL from rendering set now that widget is in DOM
      if (proposalUrl) {
        renderingUrls.delete(proposalUrl);
      }
    } else {
      // Fallback: if container creation failed, insert inline (shouldn't happen on desktop)
      console.warn("⚠️ [DESKTOP] Container not available, inserting inline");
      const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream');
      if (topicBody) {
        const firstPost = document.querySelector('.topic-post, .post, [data-post-id]');
        if (firstPost && firstPost.parentNode) {
          firstPost.parentNode.insertBefore(statusWidget, firstPost);
        } else {
          topicBody.insertBefore(statusWidget, topicBody.firstChild);
        }
      }
    }
  }
  
  // Attach event listeners for collapse/expand buttons (CSP-safe, no inline handlers)
  // Use requestAnimationFrame to ensure DOM is ready
  requestAnimationFrame(() => {
    const toggleButtons = statusWidget.querySelectorAll('.stage-toggle-btn[data-stage-id]');
    toggleButtons.forEach(button => {
      const stageId = button.getAttribute('data-stage-id');
      const content = document.getElementById(`${stageId}-content`);
      const icon = document.getElementById(`${stageId}-icon`);
      const collapsedText = document.getElementById(`${stageId}-collapsed-text`);
      
      if (!content || !icon) {
        console.warn(`⚠️ [COLLAPSE] Missing elements for stage ${stageId}`);
        return;
      }
      
      // Remove any existing listeners by cloning the button
      const newButton = button.cloneNode(true);
      button.parentNode.replaceChild(newButton, button);
      
      // Add hover effects
      newButton.addEventListener('mouseenter', () => {
        newButton.style.background = '#f3f4f6';
        newButton.style.color = '#111827';
      });
      newButton.addEventListener('mouseleave', () => {
        newButton.style.background = 'transparent';
        newButton.style.color = '#6b7280';
      });
      
      // Add click handler - when expanded, hide the collapse container completely
      const collapseContainer = document.getElementById(`${stageId}-collapse-container`);
      newButton.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        if (content.style.display === 'none' || content.style.display === '') {
          // Expand: show content, hide collapse button and text
          content.style.display = 'block';
          if (collapseContainer) {
            collapseContainer.style.display = 'none';
          }
        } else {
          // Collapse: hide content, show collapse button and text
          content.style.display = 'none';
          if (collapseContainer) {
            collapseContainer.style.display = 'flex';
          }
          icon.textContent = '▶';
          icon.setAttribute('title', 'Expand');
          if (collapsedText) {
            collapsedText.style.display = 'inline';
          }
        }
      });
    });
  });
  
  console.log("✅ [WIDGET]", widgetType === 'aip' ? 'AIP' : 'Snapshot', "widget rendered");
}

