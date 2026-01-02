import { apiInitializer } from "discourse/lib/api";
import {
  AAVE_FORUM_URL_REGEX,
  AIP_URL_REGEX,
  SNAPSHOT_URL_REGEX
} from "../lib/config/constants";
import { renderMultiStageWidget } from "../lib/dom/multi-stage-widget";
import {
  hideWidgetIfNoProposal,
  renderProposalWidget,
  showNetworkErrorWidget
} from "../lib/dom/renderer";
import { fetchAIPProposal } from "../lib/services/aip-service";
import { fetchSnapshotProposal } from "../lib/services/snapshot-service";
import { escapeHtml, formatStatusForDisplay, formatVoteAmount } from "../lib/utils/formatting";
import {
  extractAIPProposalInfo,
  extractProposalInfo,
  extractSnapshotProposalInfo
} from "../lib/utils/url-parser";
import { selectTopProposals } from "../lib/utils/widget-selection";

console.log("✅ Aave Governance Widget: JavaScript file loaded!");

export default apiInitializer((api) => {
  console.log("✅ Aave Governance Widget: apiInitializer called!");

  const handledErrors = new WeakSet();
  
  window.addEventListener('unhandledrejection', (event) => {
    if (event.reason && (
      event.reason.message?.includes('Failed to fetch') ||
      event.reason.message?.includes('ERR_CONNECTION_RESET') ||
      event.reason.message?.includes('network') ||
      event.reason?.name === 'TypeError'
    )) {
      if (handledErrors.has(event.reason)) {
        event.preventDefault();
        return;
      }
      
      event.preventDefault();
      return;
    }
  });

  async function ensureEthersLoaded() {
    if (window.ethers) {
      return window.ethers;
    }
    
    let ethersPromise = new Promise((resolve, reject) => {
      try {
        const script = document.createElement('script');
        script.src = 'https://cdn.jsdelivr.net/npm/ethers@5.7.2/dist/ethers.umd.min.js';
        script.async = true;
        script.crossOrigin = 'anonymous';
        
        script.onload = () => {
          if (window.ethers) {
            resolve(window.ethers);
          } else {
            reject(new Error("ethers.js loaded but not available on window"));
          }
        };
        
        script.onerror = () => {
          console.warn("⚠️ [AIP] Failed to load ethers.js, on-chain fetching disabled");
          ethersPromise = null;
          reject(new Error("Failed to load ethers.js"));
        };
        
        document.head.appendChild(script);
      } catch (err) {
        console.warn("⚠️ [AIP] Error loading ethers.js:", err);
        ethersPromise = null;
        reject(err);
      }
    });
    
    return ethersPromise;
  }
  
  const proposalCache = new Map();

  async function fetchSnapshotProposalLocal(space, proposalId, cacheKey, isTestnet = false) {
    return await fetchSnapshotProposal(space, proposalId, cacheKey, isTestnet, proposalCache, handledErrors);
  }

  async function fetchAIPProposalLocal(proposalId, cacheKey, urlSource = 'app.aave.com') {
    const config = {
      // eslint-disable-next-line no-undef
      ethRpcUrl: typeof ETH_RPC_URL !== 'undefined' ? ETH_RPC_URL : null,
      // eslint-disable-next-line no-undef
      aaveGovernanceV3Address: typeof AAVE_GOVERNANCE_V3_ADDRESS !== 'undefined' ? AAVE_GOVERNANCE_V3_ADDRESS : null,
      // eslint-disable-next-line no-undef
      aaveGovernanceV3Abi: typeof AAVE_GOVERNANCE_V3_ABI !== 'undefined' ? AAVE_GOVERNANCE_V3_ABI : null
    };
    
    return await fetchAIPProposal(proposalId, cacheKey, urlSource, proposalCache, handledErrors, ensureEthersLoaded, config);
  }

  function renderStatusWidget(proposalData, originalUrl, widgetId, proposalInfo = null) {
    const statusWidgetId = `aave-status-widget-${widgetId}`;
    const proposalType = proposalData.type || 'snapshot';
    
    const isMobile = window.innerWidth <= 1024 || 
                     /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
    
    const existingWidgetById = document.getElementById(statusWidgetId);
    if (existingWidgetById && existingWidgetById.getAttribute('data-tally-url') === originalUrl) {
      console.log(`🔵 [WIDGET] Updating existing widget in place (ID: ${statusWidgetId}) to prevent flickering`);
    } else {
      const existingWidgetsByUrl = document.querySelectorAll(`.tally-status-widget-container[data-tally-url="${originalUrl}"]`);
      if (existingWidgetsByUrl.length > 0) {
        console.log(`🔵 [WIDGET] Found ${existingWidgetsByUrl.length} existing widget(s) with same URL, removing duplicates`);
        existingWidgetsByUrl.forEach(widget => {
          if (widget.id !== statusWidgetId) {
            widget.remove();
            const existingWidgetId = widget.getAttribute('data-tally-status-id');
            if (existingWidgetId) {
              delete window[`tallyWidget_${existingWidgetId}`];
              const refreshKey = `tally_refresh_${existingWidgetId}`;
              if (window[refreshKey]) {
                clearInterval(window[refreshKey]);
                delete window[refreshKey];
              }
            }
          }
        });
      } else {
        const existingWidgetsByType = document.querySelectorAll(`.tally-status-widget-container[data-proposal-type="${proposalType}"]`);
        if (existingWidgetsByType.length > 0) {
          console.log(`🔵 [WIDGET] No URL match found, removing ${existingWidgetsByType.length} existing ${proposalType} widget(s) by type`);
          existingWidgetsByType.forEach(widget => {
            if (widget.id !== statusWidgetId) {
              widget.remove();
              const existingWidgetId = widget.getAttribute('data-tally-status-id');
              if (existingWidgetId) {
                delete window[`tallyWidget_${existingWidgetId}`];
                const refreshKey = `tally_refresh_${existingWidgetId}`;
                if (window[refreshKey]) {
                  clearInterval(window[refreshKey]);
                  delete window[refreshKey];
                }
              }
            }
          });
        }
      }
    }
    
    if (proposalInfo) {
      window[`tallyWidget_${widgetId}`] = {
        proposalInfo,
        originalUrl,
        widgetId,
        lastUpdate: Date.now()
      };
    }

    let statusWidget = existingWidgetById;
    const isUpdatingInPlace = statusWidget && statusWidget.getAttribute('data-tally-url') === originalUrl;
    
    if (!statusWidget) {
      statusWidget = document.createElement("div");
      statusWidget.id = statusWidgetId;
      statusWidget.className = "tally-status-widget-container";
      statusWidget.setAttribute("data-tally-status-id", widgetId);
      statusWidget.setAttribute("data-tally-url", originalUrl);
      statusWidget.setAttribute("data-proposal-type", proposalType);
    } else {
      statusWidget.setAttribute("data-tally-status-id", widgetId);
      statusWidget.setAttribute("data-tally-url", originalUrl);
      statusWidget.setAttribute("data-proposal-type", proposalType);
      console.log(`🔵 [WIDGET] Updating widget in place (ID: ${statusWidgetId}) to prevent flickering`);
    }

    const rawStatus = proposalData.status || 'unknown';
    const exactStatus = rawStatus;
    const status = rawStatus.toLowerCase().trim();
    
    console.log("🔵 [WIDGET] ========== STATUS DETECTION ==========");
    console.log("🔵 [WIDGET] Raw status from API (EXACT):", JSON.stringify(rawStatus));
    console.log("🔵 [WIDGET] Status length:", rawStatus.length);
    console.log("🔵 [WIDGET] Status char codes:", Array.from(rawStatus).map(c => c.charCodeAt(0)));
    console.log("🔵 [WIDGET] Normalized status (for logic):", JSON.stringify(status));
    console.log("🔵 [WIDGET] Display status (EXACT from Snapshot):", JSON.stringify(exactStatus));

    const activeStatuses = ["active", "open"];
    const executedStatuses = ["executed", "crosschainexecuted", "completed"];
    const queuedStatuses = ["queued", "queuing"];
    const pendingStatuses = ["pending"];
    const defeatStatuses = ["defeat", "defeated", "rejected"];
    // eslint-disable-next-line no-unused-vars
    const quorumStatuses = ["quorum not reached", "quorumnotreached"];
    
    const normalizedStatus = status.replace(/[_\s]/g, '');
    let isPendingExecution = normalizedStatus.includes("pendingexecution") || 
                             status.includes("pending execution") ||
                             status.includes("pending_execution");
    
    const isQuorumNotReached = normalizedStatus.includes("quorumnotreached") ||
                                status.includes("quorum not reached") ||
                                status.includes("quorum_not_reached") ||
                                status.includes("quorumnotreached") ||
                                (status.includes("quorum") && status.includes("not") && status.includes("reached"));
    
    console.log("🔵 [WIDGET] Quorum check - normalizedStatus:", normalizedStatus);
    console.log("🔵 [WIDGET] Quorum check - includes 'quorumnotreached':", normalizedStatus.includes("quorumnotreached"));
    console.log("🔵 [WIDGET] Quorum check - includes 'quorum not reached':", status.includes("quorum not reached"));
    console.log("🔵 [WIDGET] Quorum check - isQuorumNotReached:", isQuorumNotReached);
    
    const isDefeat = !isQuorumNotReached && defeatStatuses.some(s => {
      const defeatWord = s.toLowerCase();
      const matches = status === defeatWord || (status.includes(defeatWord) && !status.includes("quorum"));
      if (matches) {
        console.log("🔵 [WIDGET] Defeat match found for word:", defeatWord);
      }
      return matches;
    });
    
    console.log("🔵 [WIDGET] Defeat check - isDefeat:", isDefeat);
    
    const voteStats = proposalData.voteStats || {};
    const votesFor = typeof voteStats.for?.count === 'string' ? BigInt(voteStats.for.count) : (voteStats.for?.count || 0);
    const votesAgainst = typeof voteStats.against?.count === 'string' ? BigInt(voteStats.against.count) : (voteStats.against?.count || 0);
    const votesAbstain = typeof voteStats.abstain?.count === 'string' ? BigInt(voteStats.abstain.count) : (voteStats.abstain?.count || 0);
    
    const votesForNum = typeof votesFor === 'bigint' ? Number(votesFor) : votesFor;
    const votesAgainstNum = typeof votesAgainst === 'bigint' ? Number(votesAgainst) : votesAgainst;
    const votesAbstainNum = typeof votesAbstain === 'bigint' ? Number(votesAbstain) : votesAbstain;
    
    const totalVotes = votesForNum + votesAgainstNum + votesAbstainNum;
    
    const quorum = proposalData.quorum;
    let quorumNum = 0;
    if (quorum) {
      if (typeof quorum === 'string') {
        quorumNum = Number(BigInt(quorum));
      } else {
        quorumNum = Number(quorum);
      }
    }
    
    const quorumReached = quorumNum > 0 && totalVotes >= quorumNum;
    const quorumNotReachedByVotes = quorumNum > 0 && totalVotes > 0 && totalVotes < quorumNum;
    
    const hasMajoritySupport = votesForNum > votesAgainstNum;
    const proposalPassed = quorumReached && hasMajoritySupport;
    
    console.log("🔵 [WIDGET] Quorum check - threshold:", quorumNum, "total votes:", totalVotes, "reached:", quorumReached);
    console.log("🔵 [WIDGET] Majority support - for:", votesForNum, "against:", votesAgainstNum, "passed:", proposalPassed);
    
    if (!isPendingExecution && status === "queued" && proposalPassed) {
      isPendingExecution = true;
      console.log("🔵 [WIDGET] Status is 'queued' but proposal passed - treating as 'Pending execution' (like Tally website)");
    }
    
    const isActuallyQuorumNotReached = isQuorumNotReached || 
                                       (quorumNotReachedByVotes && (status === "defeated" || status === "defeat"));
    const finalIsQuorumNotReached = isActuallyQuorumNotReached;
    const finalIsDefeat = isDefeat && !finalIsQuorumNotReached && quorumReached;
    
    let displayStatus = exactStatus;
    
    if (isPendingExecution && status === "queued") {
      displayStatus = "Pending Execution";
      console.log("🔵 [WIDGET] Overriding status: 'queued' → 'Pending Execution' (proposal passed)");
    } else if (finalIsQuorumNotReached && !isQuorumNotReached) {
      displayStatus = "Quorum Not Reached";
      console.log("🔵 [WIDGET] Overriding status: 'defeated' → 'Quorum Not Reached' (quorum not met)");
    } else if (finalIsDefeat && quorumReached) {
      displayStatus = "Defeated";
      console.log("🔵 [WIDGET] Status: 'Defeated' (quorum reached but proposal defeated)");
    } else {
      displayStatus = formatStatusForDisplay(exactStatus);
      console.log("🔵 [WIDGET] Using actual status from proposal:", displayStatus, "(raw:", exactStatus, ")");
    }
    
    console.log("🔵 [WIDGET] Raw vote counts:", { 
      for: voteStats.for?.count, 
      against: voteStats.against?.count, 
      abstain: voteStats.abstain?.count 
    });
    console.log("🔵 [WIDGET] Parsed vote counts:", { 
      for: votesForNum, 
      against: votesAgainstNum, 
      abstain: votesAbstainNum 
    });

    const percentFor = voteStats.for?.percent ? Number(voteStats.for.percent) : 0;
    const percentAgainst = voteStats.against?.percent ? Number(voteStats.against.percent) : 0;
    const percentAbstain = voteStats.abstain?.percent ? Number(voteStats.abstain.percent) : 0;

    console.log("🔵 [WIDGET] Vote data:", { votesFor, votesAgainst, votesAbstain, totalVotes });
    console.log("🔵 [WIDGET] Percentages from API:", { percentFor, percentAgainst, percentAbstain });
    
    const isActive = !isPendingExecution && !finalIsDefeat && !finalIsQuorumNotReached && activeStatuses.includes(status);
    const isExecuted = !isPendingExecution && !finalIsDefeat && !finalIsQuorumNotReached && executedStatuses.includes(status);
    const isQueued = !isPendingExecution && !finalIsDefeat && !finalIsQuorumNotReached && queuedStatuses.includes(status);
    const isPending = !isPendingExecution && !finalIsDefeat && !finalIsQuorumNotReached && !isQueued && (pendingStatuses.includes(status) || (status.includes("pending") && !isPendingExecution));
    
    console.log("🔵 [WIDGET] Status flags:", { isPendingExecution, isActive, isExecuted, isQueued, isPending, isDefeat: finalIsDefeat, isQuorumNotReached: finalIsQuorumNotReached });
    console.log("🔵 [WIDGET] Display status:", displayStatus, "(Raw from API:", exactStatus, ")");
    let stageLabel = '';
    let buttonText = 'View Proposal';
    
    if (proposalData.type === 'snapshot') {
      if (proposalData.stage === 'temp-check') {
        stageLabel = 'Temp Check';
        buttonText = 'Vote on Snapshot';
      } else if (proposalData.stage === 'arfc') {
        stageLabel = 'ARFC';
        buttonText = 'Vote on Snapshot';
      } else {
        stageLabel = 'Snapshot';
        buttonText = 'View on Snapshot';
      }
    } else if (proposalData.type === 'aip') {
      stageLabel = 'AIP (On-Chain)';
      buttonText = proposalData.status === 'active' ? 'Vote on Aave' : 'View on Aave';
    } else {
      stageLabel = '';
      buttonText = 'View Proposal';
    }
    const isEndingSoon = proposalData.daysLeft !== null && 
                         proposalData.daysLeft !== undefined && 
                         !isNaN(proposalData.daysLeft) &&
                         proposalData.daysLeft >= 0 &&
                         (proposalData.daysLeft === 0 || (proposalData.daysLeft === 1 && proposalData.hoursLeft !== null && proposalData.hoursLeft < 24));
    
    const urgencyClass = isEndingSoon ? 'ending-soon' : '';
    const urgencyStyle = isEndingSoon ? 'border: 2px solid #ef4444; background: #fef2f2;' : '';
    
    const isEnded = proposalData.daysLeft !== null && proposalData.daysLeft < 0;
    const isPassedStatus = status === 'passed';
    const isExecutedStatus = status === 'executed';
    const isFailedStatus = status === 'failed';
    const isCancelledStatus = status === 'cancelled';
    const isExpiredStatus = status === 'expired';
    const hasPassed = isExecuted || isEnded || isExecutedStatus || isPassedStatus || isFailedStatus || isCancelledStatus || isExpiredStatus;
    const endedOpacity = hasPassed && !isEndingSoon ? 'opacity: 0.6;' : '';
    
    statusWidget.innerHTML = `
      <div class="tally-status-widget ${urgencyClass}" style="${urgencyStyle} background: #fff; ${endedOpacity} position: relative;">
        <button class="widget-close-btn" style="position: absolute; top: 8px; right: 8px; background: transparent; border: none; font-size: 18px; cursor: pointer; color: #6b7280; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; border-radius: 4px; transition: all 0.2s; z-index: 10;" title="Close widget" onmouseover="this.style.background='#f3f4f6'; this.style.color='#111827';" onmouseout="this.style.background='transparent'; this.style.color='#6b7280';">
          ×
        </button>
        ${stageLabel ? `<div class="stage-label" style="font-size: 0.75em; font-weight: 600; color: #6b7280; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.5px;">${stageLabel}</div>` : ''}
        ${isEndingSoon ? `<div class="urgency-alert" style="background: #fee2e2; color: #dc2626; padding: 8px; border-radius: 4px; margin-bottom: 12px; font-size: 0.85em; font-weight: 600; text-align: center;">⚠️ Ending Soon!</div>` : ''}
        <div class="status-badges-row">
          <div class="status-badge ${isPendingExecution ? 'pending' : isActive ? 'active' : isExecuted ? 'executed' : isQueued ? 'queued' : isPending ? 'pending' : finalIsDefeat ? 'defeated' : finalIsQuorumNotReached ? 'quorum-not-reached' : 'inactive'}">
            ${displayStatus}
          </div>
          ${(() => {
            if (proposalData.daysLeft !== null && proposalData.daysLeft !== undefined && !isNaN(proposalData.daysLeft)) {
              let displayText = '';
              let badgeStyle = '';
              if (proposalData.daysLeft < 0) {
                displayText = 'Ended';
              } else if (proposalData.daysLeft === 0 && proposalData.hoursLeft !== null) {
                displayText = proposalData.hoursLeft + ' ' + (proposalData.hoursLeft === 1 ? 'hour' : 'hours') + ' left';
                if (isEndingSoon) {
                  badgeStyle = 'background: #fee2e2; color: #dc2626; border-color: #fca5a5; font-weight: 700;';
                }
              } else if (proposalData.daysLeft === 0) {
                displayText = 'Ends today';
                if (isEndingSoon) {
                  badgeStyle = 'background: #fee2e2; color: #dc2626; border-color: #fca5a5; font-weight: 700;';
                }
              } else {
                displayText = proposalData.daysLeft + ' ' + (proposalData.daysLeft === 1 ? 'day' : 'days') + ' left';
                if (isEndingSoon) {
                  badgeStyle = 'background: #fef3c7; color: #92400e; border-color: #fde68a; font-weight: 700;';
              }
              }
              return `<div class="days-left-badge" style="${badgeStyle}">${displayText}</div>`;
            } else if (proposalData.daysLeft === null) {
              return '<div class="days-left-badge">Date unknown</div>';
            }
            return '';
          })()}
            </div>
        ${(() => {
          const displayFor = totalVotes > 0 ? formatVoteAmount(votesForNum) : '0';
          const displayAgainst = totalVotes > 0 ? formatVoteAmount(votesAgainstNum) : '0';
          const displayAbstain = totalVotes > 0 ? formatVoteAmount(votesAbstainNum) : '0';
          
          const progressBarHtml = totalVotes > 0 ? `
            <div class="progress-bar">
              <div class="progress-segment progress-for" style="width: ${percentFor}%"></div>
              <div class="progress-segment progress-against" style="width: ${percentAgainst}%"></div>
              <div class="progress-segment progress-abstain" style="width: ${percentAbstain}%"></div>
            </div>
          ` : `
            <div class="progress-bar">
              <!-- Empty progress bar for proposals with no votes -->
          </div>
          `;
          
          return `
            <div class="voting-results-inline">
              <span class="vote-result-inline vote-for">For <span class="vote-number">${displayFor}</span></span>
              <span class="vote-result-inline vote-against">Against <span class="vote-number">${displayAgainst}</span></span>
              <span class="vote-result-inline vote-abstain">Abstain <span class="vote-number">${displayAbstain}</span></span>
            </div>
            <div class="progress-bar-container">
              ${progressBarHtml}
            </div>
          `;
        })()}
        ${proposalData.quorum && proposalData.type === 'aip' ? `
          <div class="quorum-info" style="font-size: 0.85em; color: #6b7280; margin-top: 8px; margin-bottom: 8px;">
            Quorum: ${formatVoteAmount(totalVotes)} / ${formatVoteAmount(proposalData.quorum)}
          </div>
        ` : ''}
        <a href="${originalUrl}" target="_blank" rel="noopener" class="vote-button" style="${hasPassed && !isEndingSoon ? 'background-color: #e5e7eb !important; color: #6b7280 !important;' : 'background-color: var(--d-button-primary-bg-color, #2563eb) !important; color: var(--d-button-primary-text-color, white) !important;'}">
          ${buttonText}
        </a>
      </div>
    `;

    const closeBtn = statusWidget.querySelector('.widget-close-btn');
    if (closeBtn) {
      const newCloseBtn = closeBtn.cloneNode(true);
      closeBtn.parentNode.replaceChild(newCloseBtn, closeBtn);
      newCloseBtn.addEventListener('click', () => {
        statusWidget.style.display = 'none';
        statusWidget.remove();
      });
    }

    console.log(`🔵 [MOBILE] Status widget detection - window.innerWidth: ${window.innerWidth}, isMobile: ${isMobile}`);
    
    if (isMobile) {
      if (isUpdatingInPlace) {
        console.log(`🔵 [MOBILE] Widget already exists, updated in place - skipping insertion to prevent flickering`);
        statusWidget.style.display = 'block';
        statusWidget.style.visibility = 'visible';
        statusWidget.style.opacity = '1';
        return;
      }
      
      try {
        const allPosts = Array.from(document.querySelectorAll('.topic-post, .post, [data-post-id], article[data-post-id]'));
        const firstPost = allPosts.length > 0 ? allPosts[0] : null;
        const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream, .topic-post-stream');
        
        let lastWidget = null;
        
        if (firstPost && firstPost.parentNode) {
          const siblings = Array.from(firstPost.parentNode.children);
          for (let i = siblings.indexOf(firstPost) - 1; i >= 0; i--) {
            if (siblings[i].classList.contains('tally-status-widget-container')) {
              lastWidget = siblings[i];
          break;
            }
          }
        }
        
        if (firstPost && firstPost.parentNode) {
          if (lastWidget) {
            lastWidget.parentNode.insertBefore(statusWidget, lastWidget.nextSibling);
            console.log("✅ [MOBILE] Status widget inserted after last widget");
        } else {
            firstPost.parentNode.insertBefore(statusWidget, firstPost);
            console.log("✅ [MOBILE] Status widget inserted before first post (first widget)");
          }
        } else if (topicBody) {
          // Find last widget in topic body
          const widgetsInBody = Array.from(topicBody.querySelectorAll('.tally-status-widget-container'));
          if (widgetsInBody.length > 0) {
            // Insert after the last widget
            const lastWidgetInBody = widgetsInBody[widgetsInBody.length - 1];
            if (lastWidgetInBody.nextSibling) {
              topicBody.insertBefore(statusWidget, lastWidgetInBody.nextSibling);
      } else {
              topicBody.appendChild(statusWidget);
            }
            console.log("✅ [MOBILE] Status widget inserted after last widget in topic body");
          } else {
            // No existing widgets, insert at the beginning
            if (topicBody.firstChild) {
              topicBody.insertBefore(statusWidget, topicBody.firstChild);
            } else {
              topicBody.appendChild(statusWidget);
            }
            console.log("✅ [MOBILE] Status widget inserted at top of topic body (first widget)");
          }
        } else {
          // Try to find the main content area
          const mainContent = document.querySelector('main, .topic-body, .posts-wrapper, [role="main"]');
          if (mainContent) {
            const widgetsInMain = Array.from(mainContent.querySelectorAll('.tally-status-widget-container'));
            if (widgetsInMain.length > 0) {
              const lastWidgetInMain = widgetsInMain[widgetsInMain.length - 1];
              if (lastWidgetInMain.nextSibling) {
                mainContent.insertBefore(statusWidget, lastWidgetInMain.nextSibling);
              } else {
                mainContent.appendChild(statusWidget);
              }
              console.log("✅ [MOBILE] Status widget inserted after last widget in main content");
            } else {
              if (mainContent.firstChild) {
                mainContent.insertBefore(statusWidget, mainContent.firstChild);
              } else {
                mainContent.appendChild(statusWidget);
              }
              console.log("✅ [MOBILE] Status widget inserted in main content area (first widget)");
            }
          } else {
            // Last resort: append to body at top
            const bodyFirstChild = document.body.firstElementChild || document.body.firstChild;
            if (bodyFirstChild) {
              document.body.insertBefore(statusWidget, bodyFirstChild);
        } else {
          document.body.appendChild(statusWidget);
            }
            console.log("✅ [MOBILE] Status widget inserted at top of body");
          }
        }
        
        // Ensure widget is visible on mobile
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
      } catch (error) {
        console.error("❌ [MOBILE] Error inserting status widget:", error);
        // Fallback: try to append to a safe location
        const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream, main');
        if (topicBody) {
          topicBody.insertBefore(statusWidget, topicBody.firstChild);
        } else {
          document.body.insertBefore(statusWidget, document.body.firstChild);
        }
      }
    } else {
      // Desktop: Position widget next to timeline scroll indicator
      // Find main-outlet-wrapper to constrain widget within main content area
      const mainOutlet = document.getElementById('main-outlet-wrapper');
      const mainOutletRect = mainOutlet ? mainOutlet.getBoundingClientRect() : null;
      
      // Find timeline container and position widget relative to it
      const timelineContainer = document.querySelector('.topic-timeline-container, .timeline-container, .topic-timeline');
      if (timelineContainer) {
        // Find the actual numbers/text content within timeline to get precise right edge
        const timelineNumbers = timelineContainer.querySelector('.timeline-numbers, .topic-timeline-numbers, [class*="number"]');
        const timelineRect = timelineContainer.getBoundingClientRect();
        let rightEdge = timelineRect.right;
        let topPosition = timelineRect.top;
        
        // If we find the numbers element, use its right edge and position below it
        if (timelineNumbers) {
          const numbersRect = timelineNumbers.getBoundingClientRect();
          rightEdge = numbersRect.right;
          // Position below the scroll numbers
          topPosition = numbersRect.bottom + 10; // 10px gap below the numbers
        } else {
          // If no numbers found, position below the timeline container
          topPosition = timelineRect.bottom + 10;
        }
        
        // Constrain widget to stay within main-outlet-wrapper bounds if it exists
        let leftPosition = rightEdge;
        if (mainOutletRect) {
          // Ensure widget doesn't go beyond the right edge of main content
          const maxRight = mainOutletRect.right - 320 - 50; // widget width + margin
          leftPosition = Math.min(rightEdge, maxRight);
        }
        
        // Position next to timeline, below the scroll numbers
        statusWidget.style.position = 'fixed';
        statusWidget.style.left = `${leftPosition}px`;
        statusWidget.style.top = `${topPosition}px`;
        statusWidget.style.transform = 'none'; // No vertical centering, align to top
        
        // Append to body but constrain visually within main content
        document.body.appendChild(statusWidget);
        console.log("✅ [DESKTOP] Status widget positioned below timeline scroll indicator");
        console.log("📍 [POSITION DATA] Widget position:", {
          left: `${leftPosition}px`,
          top: `${topPosition}px`,
          rightEdge,
          timelineTop: timelineRect.top,
          timelineBottom: timelineRect.bottom,
          numbersBottom: timelineNumbers ? timelineNumbers.getBoundingClientRect().bottom : 'N/A',
          mainOutletRight: mainOutletRect ? mainOutletRect.right : 'N/A',
          windowWidth: window.innerWidth,
          widgetWidth: '320px'
        });
      } else {
        // Fallback: position on right side, constrained to main content
        let rightPosition = 50;
        if (mainOutletRect) {
          // Position relative to main content right edge
          rightPosition = window.innerWidth - mainOutletRect.right + 50;
        }
        statusWidget.style.position = 'fixed';
        statusWidget.style.right = `${rightPosition}px`;
        statusWidget.style.top = '50px';
        document.body.appendChild(statusWidget);
        console.log("✅ [DESKTOP] Status widget rendered on right side (timeline not found)");
        console.log("📍 [POSITION DATA] Widget position (fallback):", {
          right: `${rightPosition}px`,
          top: '50px',
          mainOutletRight: mainOutletRect ? mainOutletRect.right : 'N/A',
          windowWidth: window.innerWidth,
          widgetWidth: '320px'
        });
      }
    }
  }

  // Removed getCurrentPostNumber and scrollUpdateTimeout - no longer needed

  // Track which proposal is currently visible and update widget on scroll
  // eslint-disable-next-line no-unused-vars
  let currentVisibleProposal = null;

  // Find the FIRST Snapshot proposal URL in the entire topic (any post)
  // eslint-disable-next-line no-unused-vars
  function findFirstSnapshotProposalInTopic() {
    console.log("🔍 [TOPIC] Searching for first Snapshot proposal in topic...");
    
    // Find all posts in the topic
    const allPosts = Array.from(document.querySelectorAll('.topic-post, .post, [data-post-id]'));
    console.log("🔍 [TOPIC] Found", allPosts.length, "posts to search");
    
    if (allPosts.length === 0) {
      console.warn("⚠️ [TOPIC] No posts found! Trying alternative selectors...");
      // Try alternative selectors
      const altPosts = Array.from(document.querySelectorAll('article, .cooked, .post-content, [class*="post"]'));
      console.log("🔍 [TOPIC] Alternative search found", altPosts.length, "potential posts");
      if (altPosts.length > 0) {
        allPosts.push(...altPosts);
      }
    }
    
    // Search through posts in order (first post first)
    for (let i = 0; i < allPosts.length; i++) {
      const post = allPosts[i];
      
      // Method 1: Find Snapshot link in this post (check href attribute)
      // Check for both mainnet and testnet Snapshot URLs
      const snapshotLink = post.querySelector('a[href*="snapshot.org"], a[href*="testnet.snapshot.box"]');
      if (snapshotLink) {
        const url = snapshotLink.href || snapshotLink.getAttribute('href');
        if (url) {
          console.log("✅ [TOPIC] Found first Snapshot proposal in post", i + 1, "(via link):", url);
          return url;
        }
      }
      
      // Method 2: Search text content for Snapshot URLs (handles oneboxes, plain text, etc.)
      const postText = post.textContent || post.innerText || '';
      const textMatches = postText.match(SNAPSHOT_URL_REGEX);
      if (textMatches && textMatches.length > 0) {
        const url = textMatches[0];
        console.log("✅ [TOPIC] Found first Snapshot proposal in post", i + 1, "(via text):", url);
        return url;
      }
      
      // Method 3: Search HTML content (handles oneboxes and other embeds)
      const postHtml = post.innerHTML || '';
      const htmlMatches = postHtml.match(SNAPSHOT_URL_REGEX);
      if (htmlMatches && htmlMatches.length > 0) {
        const url = htmlMatches[0];
        console.log("✅ [TOPIC] Found first Snapshot proposal in post", i + 1, "(via HTML):", url);
        return url;
      }
    }
    
    console.log("⚠️ [TOPIC] No Snapshot proposal found in any post");
    console.log("🔍 [TOPIC] Debug: SNAPSHOT_URL_REGEX pattern:", SNAPSHOT_URL_REGEX);
    return null;
  }

  // Extract links from Aave Governance Forum thread content
  // When a forum link is detected, search the thread for Snapshot and AIP links
  // eslint-disable-next-line no-unused-vars
  function extractLinksFromForumThread(forumUrl) {
    console.log("🔍 [FORUM] Extracting links from Aave Governance Forum thread:", forumUrl);
    
    const extractedLinks = {
      snapshot: [],
      aip: []
    };
    
    // Extract thread ID from forum URL
    // Format: https://governance.aave.com/t/{slug}/{thread-id}
    const threadMatch = forumUrl.match(/governance\.aave\.com\/t\/[^\/]+\/(\d+)/i);
    if (!threadMatch) {
      console.warn("⚠️ [FORUM] Could not extract thread ID from URL:", forumUrl);
      return extractedLinks;
    }
    
    const threadId = threadMatch[1];
    console.log("🔵 [FORUM] Thread ID:", threadId);
    
    // Search all posts in the current page for links
    // Since we're already on Discourse, we can search the DOM directly
    const allPosts = Array.from(document.querySelectorAll('.topic-post, .post, [data-post-id], article, .cooked, .post-content'));
    
    console.log(`🔵 [FORUM] Searching ${allPosts.length} posts for Snapshot and AIP links...`);
    
    for (let i = 0; i < allPosts.length; i++) {
      const post = allPosts[i];
      const postText = post.textContent || post.innerText || '';
      const postHtml = post.innerHTML || '';
      const combinedContent = postText + ' ' + postHtml;
      
      // Find Snapshot links in this post
      const snapshotMatches = combinedContent.match(SNAPSHOT_URL_REGEX);
      if (snapshotMatches) {
        snapshotMatches.forEach(url => {
          // Include Aave Snapshot space links (mainnet) OR testnet URLs
          const isAaveSpace = url.includes('aave.eth') || url.includes('aavedao.eth');
          const isTestnet = url.includes('testnet.snapshot.box');
          if (isAaveSpace || isTestnet) {
            if (!extractedLinks.snapshot.includes(url)) {
              extractedLinks.snapshot.push(url);
              console.log("✅ [FORUM] Found Snapshot link:", url, isTestnet ? "(testnet)" : "(mainnet)");
            }
          }
        });
      }
      
      // Find AIP links in this post
      const aipMatches = combinedContent.match(AIP_URL_REGEX);
      if (aipMatches) {
        aipMatches.forEach(url => {
          if (!extractedLinks.aip.includes(url)) {
            extractedLinks.aip.push(url);
            console.log("✅ [FORUM] Found AIP link:", url);
          }
        });
      }
    }
    
    console.log(`✅ [FORUM] Extracted ${extractedLinks.snapshot.length} Snapshot links and ${extractedLinks.aip.length} AIP links from forum thread`);
    return extractedLinks;
  }

  // Find all proposal links (Snapshot, AIP, or Aave Forum) in the topic
  function findAllProposalsInTopic() {
    console.log("🔍 [TOPIC] Searching for Snapshot, AIP, and Aave Forum proposals in topic...");
    
    const proposals = {
      snapshot: [],
      aip: [],
      forum: [] // Aave Governance Forum links
    };
    
    // Find all posts in the topic
    const allPosts = Array.from(document.querySelectorAll('.topic-post, .post, [data-post-id]'));
    console.log("🔍 [TOPIC] Found", allPosts.length, "posts to search");
    
    if (allPosts.length === 0) {
      const altPosts = Array.from(document.querySelectorAll('article, .cooked, .post-content, [class*="post"]'));
      if (altPosts.length > 0) {
        allPosts.push(...altPosts);
      }
    }
    
    // Search through all posts
    for (let i = 0; i < allPosts.length; i++) {
      const post = allPosts[i];
      const postText = post.textContent || post.innerText || '';
      const postHtml = post.innerHTML || '';
      const combinedContent = postText + ' ' + postHtml;
      
      // Find Aave Governance Forum links (single-link strategy)
      // Match: governance.aave.com/t/{slug}/{id} or governance.aave.com/t/{slug}
      const forumMatches = combinedContent.match(AAVE_FORUM_URL_REGEX);
      if (forumMatches) {
        forumMatches.forEach(url => {
          // Clean up URL (remove trailing slashes, fragments, etc.)
          const cleanUrl = url.replace(/[\/#\?].*$/, '').replace(/\/$/, '');
          if (!proposals.forum.includes(cleanUrl) && !proposals.forum.includes(url)) {
            proposals.forum.push(cleanUrl);
            console.log("✅ [TOPIC] Found Aave Governance Forum link:", cleanUrl);
          }
        });
      }
      
      // Also check for forum links in a more flexible way (in case regex misses some)
      if (combinedContent.includes('governance.aave.com/t/')) {
        const flexibleMatch = combinedContent.match(/https?:\/\/[^\s<>"']*governance\.aave\.com\/t\/[^\s<>"']+/gi);
        if (flexibleMatch) {
          flexibleMatch.forEach(url => {
            const cleanUrl = url.replace(/[\/#\?].*$/, '').replace(/\/$/, '');
            if (!proposals.forum.includes(cleanUrl) && !proposals.forum.includes(url)) {
              proposals.forum.push(cleanUrl);
              console.log("✅ [TOPIC] Found Aave Governance Forum link (flexible match):", cleanUrl);
            }
          });
        }
      }
      
      // Find Snapshot links (direct links, or will be extracted from forum)
      const snapshotMatches = combinedContent.match(SNAPSHOT_URL_REGEX);
      if (snapshotMatches) {
        snapshotMatches.forEach(url => {
          // Include Aave Snapshot space links (mainnet) OR testnet URLs
          const isAaveSpace = url.includes('aave.eth') || url.includes('aavedao.eth');
          const isTestnet = url.includes('testnet.snapshot.box');
          if (isAaveSpace || isTestnet) {
            if (!proposals.snapshot.includes(url)) {
              proposals.snapshot.push(url);
              console.log("✅ [TOPIC] Added Snapshot URL:", url, isTestnet ? "(testnet)" : "(mainnet)");
            }
          }
        });
      }
      
      // Find AIP links (direct links, or will be extracted from forum)
      const aipMatches = combinedContent.match(AIP_URL_REGEX);
      if (aipMatches) {
        aipMatches.forEach(url => {
          if (!proposals.aip.includes(url)) {
            proposals.aip.push(url);
          }
        });
      }
    }
    
    console.log("✅ [TOPIC] Found proposals:", {
      forum: proposals.forum.length,
      snapshot: proposals.snapshot.length,
      aip: proposals.aip.length
    });
    
    // Log all found URLs for debugging
    if (proposals.forum.length > 0) {
      console.log("🔵 [TOPIC] Aave Governance Forum URLs found:");
      proposals.forum.forEach((url, idx) => {
        console.log(`  [${idx + 1}] ${url}`);
      });
    }
    if (proposals.snapshot.length > 0) {
      console.log("🔵 [TOPIC] Snapshot URLs found:");
      proposals.snapshot.forEach((url, idx) => {
        console.log(`  [${idx + 1}] ${url}`);
      });
    }
    if (proposals.aip.length > 0) {
      console.log("🔵 [TOPIC] AIP URLs found:");
      proposals.aip.forEach((url, idx) => {
        console.log(`  [${idx + 1}] ${url}`);
      });
    }
    
    return proposals;
  }

  // showNetworkErrorWidget, hideWidgetIfNoProposal, showWidget are now imported from ../lib/dom/renderer

  // showNetworkErrorWidget is now imported from ../lib/dom/renderer - use directly with getOrCreateWidgetsContainer

  // Fetch proposal data (wrapper for compatibility with old code)
  async function fetchProposalData(proposalId, url, govId, urlProposalNumber, forceRefresh = false) {
    if (!url) {return null;}
    
    // Determine type from URL
    let type = null;
    if (url.includes('snapshot.org') || url.includes('testnet.snapshot.box')) {
      type = 'snapshot';
    } else if (url.includes('governance.aave.com') || url.includes('vote.onaave.com') || url.includes('app.aave.com/governance')) {
      type = 'aip';
    }
    
    if (!type) {
      console.warn("❌ Could not determine proposal type from URL:", url);
      return null;
    }
    
    return await fetchProposalDataByType(url, type, forceRefresh);
  }

  // Fetch proposal data based on type (Tally, Snapshot, or AIP)
  async function fetchProposalDataByType(url, type, forceRefresh = false) {
    try {
      const cacheKey = url;
      
      // Check cache (skip if forceRefresh is true)
      if (!forceRefresh && proposalCache.has(cacheKey)) {
        const cachedData = proposalCache.get(cacheKey);
        const cacheAge = Date.now() - (cachedData._cachedAt || 0);
        if (cacheAge < 5 * 60 * 1000) {
          console.log("🔵 [CACHE] Returning cached data (age:", Math.round(cacheAge / 1000), "seconds)");
          return cachedData;
        }
        proposalCache.delete(cacheKey);
      }
      
      if (type === 'snapshot') {
        const proposalInfo = extractSnapshotProposalInfo(url);
        if (!proposalInfo) {
          return null;
        }
        return await fetchSnapshotProposalLocal(proposalInfo.space, proposalInfo.proposalId, cacheKey, proposalInfo.isTestnet || false);
      } else if (type === 'aip') {
        const proposalInfo = extractAIPProposalInfo(url);
        if (!proposalInfo) {
          return null;
        }
        // Use proposalId as the primary key (extracted from URL)
        // This is the canonical identifier for fetching on-chain
        const proposalId = proposalInfo.proposalId || proposalInfo.topicId || proposalInfo.aipNumber;
        if (!proposalId) {
          console.warn("⚠️ [AIP] No proposalId extracted from URL:", url);
          return null;
        }
        // Pass URL source to use correct state enum mapping
        const urlSource = proposalInfo.urlSource || 'app.aave.com';
        return await fetchAIPProposalLocal(proposalId, cacheKey, 'mainnet', urlSource);
      }
      
      return null;
    } catch (error) {
      // Handle any unexpected errors gracefully
      // Mark error as handled to prevent unhandled rejection warnings
      handledErrors.add(error);
      if (error.cause) {
        handledErrors.add(error.cause);
      }
      console.warn(`⚠️ [FETCH] Error fetching ${type} proposal from ${url}:`, error.message || error);
      return null;
    }
  }

  // Extract AIP URL from Snapshot proposal metadata/description (CASCADING SEARCH)
  // This is critical for linking sequential proposals: ARFC → AIP
  // eslint-disable-next-line no-unused-vars
  function extractAIPUrlFromSnapshot(snapshotData) {
    if (!snapshotData) {
      return null;
    }
    
    console.log("🔍 [CASCADE] Searching for AIP link in Snapshot proposal description...");
    
    // Get all text content - prefer raw proposal body if available, otherwise use transformed data
    let combinedText = '';
    if (snapshotData._rawProposal && snapshotData._rawProposal.body) {
      // Use raw proposal body (most complete source)
      combinedText = snapshotData._rawProposal.body || '';
      console.log("🔍 [CASCADE] Using raw proposal body for search");
    } else {
      // Fall back to transformed data fields
    const description = snapshotData.description || '';
      const body = snapshotData.body || '';
      combinedText = (description + ' ' + body).trim();
      console.log("🔍 [CASCADE] Using transformed description/body fields for search");
    }
    
    if (combinedText.length === 0) {
      console.log("⚠️ [CASCADE] No description/body text found in Snapshot proposal");
      return null;
    }
    
    console.log(`🔍 [CASCADE] Searching in ${combinedText.length} characters of proposal text`);
    
    // ENHANCED: Search for AIP links with multiple patterns
    // Pattern 1: Direct URLs (governance.aave.com or app.aave.com/governance)
    const aipUrlMatches = combinedText.match(AIP_URL_REGEX);
    if (aipUrlMatches && aipUrlMatches.length > 0) {
      // Prefer full URLs, extract the first valid one
      const foundUrl = aipUrlMatches[0];
      console.log(`✅ [CASCADE] Found AIP URL in description: ${foundUrl}`);
      return foundUrl;
    }
    
    const aipNumberPatterns = [
      /AIP\s*[#]?\s*(\d+)/gi,
      /proposal\s*[#]?\s*(\d+)/gi,
      /governance\s*proposal\s*[#]?\s*(\d+)/gi,
      /aip\s*(\d+)/gi
    ];
    
    for (const pattern of aipNumberPatterns) {
      const matches = combinedText.match(pattern);
      if (matches && matches.length > 0) {
        // Extract the first number found
        const aipNumber = matches[0].match(/\d+/)?.[0];
        if (aipNumber) {
          // Try constructing URL (common format: app.aave.com/governance/proposal/{number})
          const constructedUrl = `https://app.aave.com/governance/proposal/${aipNumber}`;
          console.log(`✅ [CASCADE] Found AIP number ${aipNumber}, constructed URL: ${constructedUrl}`);
          // Return constructed URL - it will be validated when fetched
          return constructedUrl;
        }
      }
    }
    
    // Pattern 3: Check metadata/plugins fields for AIP link
    if (snapshotData.metadata) {
      const metadataStr = JSON.stringify(snapshotData.metadata);
      const metadataMatch = metadataStr.match(AIP_URL_REGEX);
      if (metadataMatch && metadataMatch.length > 0) {
        console.log(`✅ [CASCADE] Found AIP URL in metadata: ${metadataMatch[0]}`);
        return metadataMatch[0];
      }
    }
    
    // Pattern 4: Check plugins.discourse or other plugin structures
    if (snapshotData.plugins) {
      const pluginsStr = JSON.stringify(snapshotData.plugins);
      const pluginMatch = pluginsStr.match(AIP_URL_REGEX);
      if (pluginMatch && pluginMatch.length > 0) {
        console.log(`✅ [CASCADE] Found AIP URL in plugins: ${pluginMatch[0]}`);
        return pluginMatch[0];
      }
    }
    
    console.log("❌ [CASCADE] No AIP link found in Snapshot proposal description/metadata");
    return null;
  }

  // Set up separate widgets: Snapshot widget and AIP widget
  function setupTopicWidget() {
    console.log("🔵 [TOPIC] Setting up widgets - one per proposal URL...");
    
    // Category filtering - only run in allowed categories
    const allowedCategories = []; // e.g., ['governance', 'proposals', 'aave-governance']
    
    if (allowedCategories.length > 0) {
      let categorySlug = document.querySelector('[data-category-slug]')?.getAttribute('data-category-slug') ||
                        document.querySelector('.category-name')?.textContent?.trim()?.toLowerCase()?.replace(/\s+/g, '-') ||
                        document.querySelector('[data-category-id]')?.closest('.category')?.querySelector('.category-name')?.textContent?.trim()?.toLowerCase()?.replace(/\s+/g, '-');
      
      if (categorySlug && !allowedCategories.includes(categorySlug)) {
        console.log("⏭️ [WIDGET] Skipping - category '" + categorySlug + "' not in allowed list:", allowedCategories);
        return Promise.resolve();
      }
    }
    
    // Find all proposals directly in the post (no cascading search)
    const allProposals = findAllProposalsInTopic();
    
    console.log(`🔵 [TOPIC] Found ${allProposals.snapshot.length} Snapshot URL(s) and ${allProposals.aip.length} AIP URL(s) directly in post`);
    
    // Render widgets - one per URL
    setupTopicWidgetWithProposals(allProposals);
    return Promise.resolve();
  }
  
  // Separate function to set up widget with proposals (to allow re-running after extraction)
  // Render widgets - one per proposal URL
  function setupTopicWidgetWithProposals(allProposals) {
    // Safety check: ensure allProposals is valid
    if (!allProposals || typeof allProposals !== 'object') {
      console.warn("⚠️ [TOPIC] Invalid allProposals object, skipping widget setup");
      return;
    }
    
    // Ensure snapshot and aip are arrays (defensive programming)
    const snapshotUrls = Array.isArray(allProposals.snapshot) ? allProposals.snapshot : [];
    const aipUrls = Array.isArray(allProposals.aip) ? allProposals.aip : [];
    
    // Normalize URLs for comparison (remove trailing slashes, query params, fragments)
    const normalizeUrl = (url) => {
      if (!url) {
        return '';
      }
      return url.replace(/[\/#\?].*$/, '').replace(/\/$/, '').toLowerCase().trim();
    };
    
    // Check if widgets already exist and match current proposals - if so, don't clear them
    const existingWidgets = document.querySelectorAll('.tally-status-widget-container');
    const existingUrls = new Set();
    existingWidgets.forEach(widget => {
      const widgetUrl = widget.getAttribute('data-tally-url');
      if (widgetUrl) {
        existingUrls.add(normalizeUrl(widgetUrl));
      }
    });
    
    // Get all proposal URLs from current proposals (normalized)
    const currentUrls = new Set([
      ...snapshotUrls.map(normalizeUrl),
      ...aipUrls.map(normalizeUrl)
    ].filter(url => url)); // Filter out empty strings
    
    // Only clear widgets if the proposals have changed (different URLs)
    // Use normalized URLs for comparison
    const urlsMatch = existingUrls.size === currentUrls.size && 
                     existingUrls.size > 0 &&
                     [...existingUrls].every(url => currentUrls.has(url)) &&
                     [...currentUrls].every(url => existingUrls.has(url));
    
    if (urlsMatch && existingWidgets.length > 0) {
      console.log(`🔵 [TOPIC] Widgets already match current proposals (${existingWidgets.length} widget(s)), skipping re-render`);
      // Ensure widgetsInitialized is set to prevent future re-renders
      if (!widgetsInitialized) {
        widgetsInitialized = true;
      }
      return; // Don't re-render if widgets already match
    }
    
    // IMPORTANT: If widgets exist but no proposals are found, keep the widgets
    // This prevents widgets from disappearing when scrolling (proposals might not be in viewport/DOM)
    // OR if proposals were already found and widgets created on initial load
    if (snapshotUrls.length === 0 && aipUrls.length === 0 && existingWidgets.length > 0) {
      console.log(`🔵 [TOPIC] No proposals found but ${existingWidgets.length} widget(s) already exist - keeping widgets (they may be for proposals not currently in viewport or already rendered)`);
      // Mark as initialized if we have widgets, even if proposals aren't found now
      widgetsInitialized = true;
      return; // Keep existing widgets, don't remove them
    }
    
    // If widgets are initialized and we found the same proposals, skip re-rendering
    // Check if we have widgets for all current URLs (using normalized URLs)
    if (widgetsInitialized && existingWidgets.length > 0 && currentUrls.size > 0) {
      // Check if all current URLs have corresponding widgets (using normalized comparison)
      const urlArray = Array.from(currentUrls);
      const allUrlsHaveWidgets = urlArray.every(url => {
        return Array.from(existingWidgets).some(widget => {
          const widgetUrl = widget.getAttribute('data-tally-url');
          const normalizedWidgetUrl = normalizeUrl(widgetUrl);
          // Use normalized comparison for exact match
          return normalizedWidgetUrl === url;
        });
      });
      
      // Also check if we have the same number of widgets as URLs
      if (allUrlsHaveWidgets && existingWidgets.length >= currentUrls.size) {
        console.log(`🔵 [TOPIC] Widgets already initialized and match current proposals, skipping re-render`);
        return;
      }
    }
    
    // Clear all existing widgets only if proposals have changed
    if (existingWidgets.length > 0) {
      console.log(`🔵 [TOPIC] Proposals changed - clearing ${existingWidgets.length} existing widget(s) before creating new ones`);
      existingWidgets.forEach(widget => {
        // Get URL from widget before removing it
        const widgetUrl = widget.getAttribute('data-tally-url');
        if (widgetUrl) {
          // Remove from tracking sets when clearing widget
          renderingUrls.delete(widgetUrl);
          fetchingUrls.delete(widgetUrl);
        }
        widget.remove();
      });
    }
    
    // Also clear the container if it exists (will be recreated if needed)
    const container = document.getElementById('governance-widgets-wrapper');
    if (container) {
      container.remove();
      console.log("🔵 [TOPIC] Cleared widgets container");
    }
    
    // Clear all tracking sets when starting fresh
    renderingUrls.clear();
    fetchingUrls.clear();
    
    // Only remove widgets if no proposals found AND no widgets exist
    if (snapshotUrls.length === 0 && aipUrls.length === 0) {
      console.log("🔵 [TOPIC] No proposals found and no existing widgets - removing any remaining widgets");
      hideWidgetIfNoProposal();
      return;
    }
    
    // Deduplicate URLs to prevent creating multiple widgets for the same proposal
    const uniqueSnapshotUrls = [...new Set(snapshotUrls)];
    const uniqueAipUrls = [...new Set(aipUrls)];
    
    if (uniqueSnapshotUrls.length !== snapshotUrls.length) {
      console.log(`🔵 [TOPIC] Deduplicated ${snapshotUrls.length} Snapshot URLs to ${uniqueSnapshotUrls.length} unique URLs`);
    }
    if (uniqueAipUrls.length !== aipUrls.length) {
      console.log(`🔵 [TOPIC] Deduplicated ${aipUrls.length} AIP URLs to ${uniqueAipUrls.length} unique URLs`);
    }
    
    const totalProposals = uniqueSnapshotUrls.length + uniqueAipUrls.length;
    console.log(`🔵 [TOPIC] Found ${totalProposals} unique proposal(s), will select max 3 based on priority`);
    
    // Store initial proposal URLs for comparison (before fetching/rendering)
    // This helps prevent re-rendering when scrolling loads new posts with same proposals
    if (totalProposals > 0) {
      initialProposalUrls = new Set([...uniqueSnapshotUrls, ...uniqueAipUrls]);
      console.log(`🔵 [TOPIC] Stored ${initialProposalUrls.size} initial proposal URL(s) for comparison`);
    }
    
    // Show default loader before fetching
    if (totalProposals > 0) {
      showDefaultLoader();
    }
    
    // Create combined ordered list of all proposals (maintain order: snapshot first, then aip)
    // This preserves the order proposals appear in the content
    const orderedProposals = [];
    uniqueSnapshotUrls.forEach((url, index) => {
      orderedProposals.push({ url, type: 'snapshot', originalIndex: index });
    });
    uniqueAipUrls.forEach((url, index) => {
      orderedProposals.push({ url, type: 'aip', originalIndex: index });
    });
    
    // ============================================================================
    // WIDGET SELECTION LOGIC - Max 3 widgets, prioritized by state
    // Priority: active > created > pending > executed > ended > failed
    // Logic is now imported from ../lib/utils/widget-selection
    // ============================================================================
    
    /**
     * Store selected proposals in service instead of rendering directly
     * The component will handle rendering reactively
     */
    function renderSelectedProposals(snapshotProposals, aipProposals) {
      // Combine all proposals
      const combinedProposals = [...snapshotProposals, ...aipProposals];
      
      if (combinedProposals.length === 0) {
        console.log("🔵 [RENDER] No valid proposals to render");
        // Hide loader if no proposals to render
        hideDefaultLoader();
        // Clear service
        try {
          // eslint-disable-next-line no-undef
          const proposalManager = Discourse.__container__.lookup("service:proposal-manager");
          if (proposalManager) {
            proposalManager.clearProposals();
          }
        } catch (e) {
          console.warn("⚠️ [SERVICE] Could not access proposal-manager service:", e);
        }
        return;
      }
      
      // Select top 3 based on priority
      const selected = selectTopProposals(combinedProposals);
      
      console.log(`🔵 [RENDER] Storing ${selected.length} selected proposal(s) in service out of ${combinedProposals.length} total proposal(s)`);
      
      // Store proposals in service - component will render them reactively
      try {
        // eslint-disable-next-line no-undef
        const proposalManager = Discourse.__container__.lookup("service:proposal-manager");
        if (proposalManager) {
          proposalManager.setProposals(selected);
          console.log(`✅ [SERVICE] Stored ${selected.length} proposal(s) in service`);
          
          // Mark widgets as initialized
          widgetsInitialized = true;
          
          // Store initial URLs for comparison
          if (typeof uniqueSnapshotUrls !== 'undefined' && typeof uniqueAipUrls !== 'undefined') {
            const allUrls = [...uniqueSnapshotUrls, ...uniqueAipUrls];
            initialProposalUrls = new Set(allUrls);
          } else {
            // Fallback: extract URLs from proposals
            const allUrls = [...snapshotProposals.map(p => p.url), ...aipProposals.map(p => p.url)];
            initialProposalUrls = new Set(allUrls);
          }
          
          // Hide loader after proposals are stored
          hideDefaultLoader();
        } else {
          console.warn("⚠️ [SERVICE] proposal-manager service not found, falling back to direct rendering");
          // Fallback to direct rendering if service is not available
          selected.forEach((proposal, index) => {
            if (renderingUrls.has(proposal.url)) {
              console.log(`🔵 [RENDER] URL ${proposal.url} is already being rendered, skipping duplicate`);
              return;
            }
            
            renderingUrls.add(proposal.url);
            
            const stage = proposal.stage || proposal.type || 'arfc';
            const widgetId = `${stage}-widget-${index}-${Date.now()}`;
            
            // Render based on proposal type
            if (proposal.type === 'aip') {
              renderMultiStageWidget({
                tempCheck: null,
                tempCheckUrl: null,
                arfc: null,
                arfcUrl: null,
                aip: proposal.data,
                aipUrl: proposal.url
              }, widgetId, index, renderingUrls, fetchingUrls);
            } else {
              // Snapshot proposal
              renderMultiStageWidget({
                tempCheck: stage === 'temp-check' ? proposal.data : null,
                tempCheckUrl: stage === 'temp-check' ? proposal.url : null,
                arfc: (stage === 'arfc' || stage === 'snapshot') ? proposal.data : null,
                arfcUrl: (stage === 'arfc' || stage === 'snapshot') ? proposal.url : null,
                aip: null,
                aipUrl: null
              }, widgetId, index, renderingUrls, fetchingUrls);
            }
          });
          
          if (selected.length > 0) {
            setTimeout(() => {
              const renderedWidgets = document.querySelectorAll('.tally-status-widget-container');
              if (renderedWidgets.length > 0) {
                widgetsInitialized = true;
                hideDefaultLoader();
              } else {
                hideDefaultLoader();
              }
            }, 100);
          } else {
            hideDefaultLoader();
          }
        }
      } catch (e) {
        console.warn("⚠️ [SERVICE] Error accessing proposal-manager service:", e);
        // Fallback to direct rendering
        hideDefaultLoader();
      }
    }
    
    // ===== FETCH ALL PROPOSALS IN PARALLEL, THEN RENDER ALL AT ONCE =====
    // Start both snapshot and AIP fetches in parallel, wait for ALL to complete before rendering
    
    const snapshotPromise = uniqueSnapshotUrls.length > 0 ? (() => {
      // Filter out URLs that are already being fetched or rendered
      const snapshotUrlsToFetch = uniqueSnapshotUrls.filter(url => {
        if (fetchingUrls.has(url) || renderingUrls.has(url)) {
          console.log(`🔵 [TOPIC] Snapshot URL ${url} is already being fetched/rendered, skipping duplicate`);
          return false;
        }
        fetchingUrls.add(url);
        return true;
      });
      
      return Promise.allSettled(snapshotUrlsToFetch.map(url => {
        // Wrap in Promise.resolve to ensure we always return a promise that resolves
        return Promise.resolve()
          .then(() => fetchProposalDataByType(url, 'snapshot'))
          .then(data => {
            // Remove from fetching set when fetch completes
            fetchingUrls.delete(url);
            return { url, data, type: 'snapshot' };
          })
          .catch(error => {
            // Remove from fetching set on error
            fetchingUrls.delete(url);
            // Mark error as handled to prevent unhandled rejection warnings
            handledErrors.add(error);
            if (error.cause) {
              handledErrors.add(error.cause);
            }
            console.warn(`⚠️ [TOPIC] Failed to fetch Snapshot proposal from ${url}:`, error.message || error);
            return { url, data: null, type: 'snapshot', error: error.message || String(error) };
          });
      }))
        .then(snapshotResults => {
          // Filter out failed promises and invalid data
          const validSnapshots = snapshotResults
            .filter(result => result.status === 'fulfilled' && result.value && result.value.data && result.value.data.title)
            .map(result => result.value);
          
          // Check for failed fetches
          const failedSnapshots = snapshotResults.filter(result => 
            result.status === 'rejected' || 
            (result.status === 'fulfilled' && (!result.value || !result.value.data || !result.value.data.title))
          );
          
          if (failedSnapshots.length > 0 && validSnapshots.length === 0) {
            // All proposals failed - show error message
            console.warn(`⚠️ [TOPIC] All ${uniqueSnapshotUrls.length} Snapshot proposal(s) failed to load. This may be a temporary network issue.`);
            // Optionally show a user-visible error widget
            showNetworkErrorWidget(uniqueSnapshotUrls.length, 'snapshot');
          } else if (failedSnapshots.length > 0) {
            console.warn(`⚠️ [TOPIC] ${failedSnapshots.length} out of ${uniqueSnapshotUrls.length} Snapshot proposal(s) failed to load`);
          }
          
          console.log(`🔵 [TOPIC] Found ${validSnapshots.length} valid Snapshot proposal(s) out of ${snapshotUrlsToFetch.length} unique URL(s)`);
          
          // Return snapshot results
          return validSnapshots.map((snapshot) => {
            const stage = snapshot.data.stage || 'snapshot';
            return {
              url: snapshot.url,
              data: snapshot.data,
              type: 'snapshot',
              stage,
              status: snapshot.data.status || snapshot.data.state || 'unknown',
              title: snapshot.data.title,
              originalOrder: orderedProposals.findIndex(p => p.url === snapshot.url && p.type === 'snapshot')
            };
          });
        })
        .catch(error => {
          console.error("❌ [TOPIC] Error processing Snapshot proposals:", error);
          return [];
        });
    })() : Promise.resolve([]);
    
    const aipPromise = uniqueAipUrls.length > 0 ? (() => {
      const aipUrlsToFetch = uniqueAipUrls.filter(url => {
        if (fetchingUrls.has(url) || renderingUrls.has(url)) {
          console.log(`🔵 [TOPIC] AIP URL ${url} is already being fetched/rendered, skipping duplicate`);
          return false;
        }
        fetchingUrls.add(url);
        return true;
      });
      
      return Promise.allSettled(aipUrlsToFetch.map(aipUrl => {
        return Promise.resolve()
          .then(() => fetchProposalDataByType(aipUrl, 'aip'))
          .then(aipData => {
            fetchingUrls.delete(aipUrl);
            return { url: aipUrl, data: aipData, type: 'aip' };
          })
          .catch(error => {
            fetchingUrls.delete(aipUrl);
            handledErrors.add(error);
            if (error.cause) {
              handledErrors.add(error.cause);
            }
            console.warn(`⚠️ [TOPIC] Failed to fetch AIP proposal from ${aipUrl}:`, error.message || error);
            return { url: aipUrl, data: null, type: 'aip', error: error.message || String(error) };
          });
      }))
        .then(aipResults => {
          const validAips = aipResults
            .filter(result => result.status === 'fulfilled' && result.value && result.value.data && result.value.data.title)
            .map(result => result.value);
          
          console.log(`🔵 [TOPIC] Found ${validAips.length} valid AIP proposal(s) out of ${aipUrlsToFetch.length} unique URL(s)`);
          
          // Return AIP results
          return validAips.map((aip) => {
            return {
              url: aip.url,
              data: aip.data,
              type: 'aip',
              stage: 'aip',
              status: aip.data.status || 'unknown',
              title: aip.data.title,
              originalOrder: orderedProposals.findIndex(p => p.url === aip.url && p.type === 'aip')
            };
          });
        })
        .catch(error => {
          console.error("❌ [TOPIC] Error processing AIP proposals:", error);
          return [];
        });
    })() : Promise.resolve([]);
    
    // Wait for ALL fetches to complete, then render all widgets at once
    Promise.all([snapshotPromise, aipPromise])
      .then(([snapshotProposals, aipProposals]) => {
        console.log(`🔵 [TOPIC] All fetches complete - Snapshot: ${snapshotProposals.length}, AIP: ${aipProposals.length}`);
        // Render all widgets at once after all data is fetched
        renderSelectedProposals(snapshotProposals, aipProposals);
      })
      .catch(error => {
        console.error("❌ [TOPIC] Error waiting for all fetches:", error);
        // Still try to render what we have
        hideDefaultLoader();
      });
    
  }
  
  // Debounce widget setup to prevent duplicate widgets
  let widgetSetupTimeout = null;
  let isWidgetSetupRunning = false;
  
  // Track if widgets have been successfully initialized (prevents re-rendering on scroll)
  let widgetsInitialized = false;
  // Track the initial set of proposal URLs to detect actual changes
  let initialProposalUrls = new Set();
  
  // Track URLs currently being rendered to prevent race conditions
  const renderingUrls = new Set();
  // Track URLs currently being fetched to prevent duplicate fetches
  const fetchingUrls = new Set();
  
  // Default loader functions
  function showDefaultLoader() {
    // Remove any existing loader
    hideDefaultLoader();
    
    // Create loader element
    const loader = document.createElement("div");
    loader.id = "governance-widgets-default-loader";
    loader.className = "governance-widgets-default-loader";
    loader.style.cssText = `
      position: fixed;
      right: 50px;
      top: 180px;
      width: 320px;
      max-width: 320px;
      z-index: 500;
      background: #fff;
      border: 1px solid #e5e7eb;
      border-radius: 8px;
      padding: 40px 20px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 16px;
      box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
    `;
    
    loader.innerHTML = `
      <div class="loading-spinner" style="
        width: 32px;
        height: 32px;
        border: 4px solid #f3f4f6;
        border-top-color: #2563eb;
        border-radius: 50%;
        animation: spin 0.8s linear infinite;
      "></div>
      <span style="
        font-size: 0.9em;
        color: #6b7280;
        text-align: center;
      ">Loading governance widgets...</span>
    `;
    
    // Add spinner animation if not already defined
    if (!document.getElementById('governance-loader-styles')) {
      const style = document.createElement('style');
      style.id = 'governance-loader-styles';
      style.textContent = `
        @keyframes spin {
          to { transform: rotate(360deg); }
        }
      `;
      document.head.appendChild(style);
    }
    
    document.body.appendChild(loader);
    console.log("🔵 [LOADER] Showing default loader");
  }
  
  function hideDefaultLoader() {
    const loader = document.getElementById("governance-widgets-default-loader");
    if (loader) {
      loader.remove();
      console.log("🔵 [LOADER] Hiding default loader");
    }
  }
  
  function debouncedSetupTopicWidget(force = false) {
    // If widgets are already initialized and we're not forcing, skip
    if (widgetsInitialized && !force) {
      console.log("🔵 [TOPIC] Widgets already initialized, skipping re-render (use force=true to override)");
      return;
    }
    
    // Clear any pending setup
    if (widgetSetupTimeout) {
      clearTimeout(widgetSetupTimeout);
    }
    
    // Debounce: wait 500ms before running (increased from 300ms to reduce flickering on mobile)
    widgetSetupTimeout = setTimeout(() => {
      if (!isWidgetSetupRunning) {
        isWidgetSetupRunning = true;
        setupTopicWidget().finally(() => {
          isWidgetSetupRunning = false;
          // Don't set widgetsInitialized here - it should only be set when widgets are actually created
          // The flag is set in renderSelectedProposals after DOM verification
        });
      }
    }, 500);
  }
  
  // Watch for new posts being added to the topic and re-check for proposals
  function setupTopicWatcher() {
    // Track previous post count to detect actual new posts
    let previousPostCount = document.querySelectorAll('.topic-post, .post, [data-post-id]').length;
    
    // Debounce proposal checking to prevent excessive calls during scroll
    let proposalCheckTimeout = null;
    
    // Watch for new posts being added
    const postObserver = new MutationObserver((mutations) => {
      // Ignore mutations that are only widget-related to prevent flickering
      let hasNewPost = false;
      
      for (const mutation of mutations) {
        // Only check for actual new post elements being added, not attribute changes
        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
          for (const node of mutation.addedNodes) {
            // Check if the added node is a widget or inside a widget
            if (node.nodeType === Node.ELEMENT_NODE) {
              const isWidget = node.classList?.contains('tally-status-widget-container') ||
                             node.classList?.contains('governance-widgets-wrapper') ||
                             node.closest?.('.tally-status-widget-container') ||
                             node.closest?.('.governance-widgets-wrapper');
              
              // Check if it's a new post element
              const isPost = node.matches?.('.topic-post, .post, [data-post-id]') ||
                           node.querySelector?.('.topic-post, .post, [data-post-id]');
              
              if (isPost && !isWidget) {
                hasNewPost = true;
                break;
              }
            }
          }
        }
        
        // Ignore attribute changes (like class changes from scrolling) - these are not new posts
        if (mutation.type === 'attributes') {
          continue;
        }
        
        if (hasNewPost) {
          break;
        }
      }
      
      // Only trigger widget setup if there are actual NEW POSTS added, not just DOM mutations
      if (hasNewPost) {
        const currentPostCount = document.querySelectorAll('.topic-post, .post, [data-post-id]').length;
        if (currentPostCount > previousPostCount) {
          previousPostCount = currentPostCount;
          console.log(`🔵 [TOPIC] New post detected (total: ${currentPostCount}), will check if proposals changed`);
          
          // Debounce the proposal checking to avoid excessive calls during rapid scrolling
          if (proposalCheckTimeout) {
            clearTimeout(proposalCheckTimeout);
          }
          
          proposalCheckTimeout = setTimeout(() => {
            // Check if the new posts contain any proposal URLs we haven't seen before
            // Only re-initialize if proposals actually changed
            const newProposals = findAllProposalsInTopic();
            const newUrls = new Set([
              ...newProposals.snapshot.map(url => url.replace(/[\/#\?].*$/, '').replace(/\/$/, '').toLowerCase().trim()),
              ...newProposals.aip.map(url => url.replace(/[\/#\?].*$/, '').replace(/\/$/, '').toLowerCase().trim())
            ].filter(url => url));
            
            // Compare with initial proposal URLs
            const initialUrlsNormalized = new Set(
              Array.from(initialProposalUrls).map(url => url.replace(/[\/#\?].*$/, '').replace(/\/$/, '').toLowerCase().trim())
            );
            
            // Check if proposals actually changed
            const proposalsChanged = newUrls.size !== initialUrlsNormalized.size ||
              ![...newUrls].every(url => initialUrlsNormalized.has(url)) ||
              ![...initialUrlsNormalized].every(url => newUrls.has(url));
            
            if (proposalsChanged) {
              console.log(`🔵 [TOPIC] Proposals changed in new posts, re-initializing widgets`);
              widgetsInitialized = false;
              debouncedSetupTopicWidget(true);
            } else {
              console.log(`🔵 [TOPIC] New posts detected but proposals unchanged, skipping re-render`);
              // Update initial URLs to include any new ones (in case order changed)
              initialProposalUrls = new Set([...newProposals.snapshot, ...newProposals.aip]);
            }
          }, 1000); // Wait 1 second after last post addition before checking
        }
      }
    });

    const postStream = document.querySelector('.post-stream, .topic-body, .posts-wrapper');
    if (postStream) {
      // Only observe childList changes (new posts), not attributes (scroll-related changes)
      postObserver.observe(postStream, { childList: true, subtree: true });
      console.log("✅ [TOPIC] Watching for new posts in topic (ignoring widget changes and attribute mutations)");
    }
    
    // Initial setup - force initialization on page load
    widgetsInitialized = false;
    debouncedSetupTopicWidget(true);
    
    // Also check after delays to catch late-loading content (but only if not initialized yet)
    setTimeout(() => {
      if (!widgetsInitialized) {
        debouncedSetupTopicWidget(true);
      }
    }, 500);
    setTimeout(() => {
      if (!widgetsInitialized) {
        debouncedSetupTopicWidget(true);
      }
    }, 1500);
    
    console.log("✅ [TOPIC] Topic widget setup complete");
  }

  // OLD SCROLL TRACKING FUNCTIONS REMOVED - Using setupTopicWidget instead

  // Auto-refresh widget when Tally data changes
  // eslint-disable-next-line no-unused-vars
  function setupAutoRefresh(widgetId, proposalInfo, url) {
    // Clear any existing refresh interval for this widget
    const refreshKey = `tally_refresh_${widgetId}`;
    if (window[refreshKey]) {
      clearInterval(window[refreshKey]);
    }
    
    // Refresh every 2 minutes to check for status/vote changes
    window[refreshKey] = setInterval(async () => {
      console.log("🔄 [REFRESH] Checking for updates for widget:", widgetId);
      
      const proposalId = proposalInfo.isInternalId ? proposalInfo.internalId : null;
      // Force refresh by bypassing cache
      const freshData = await fetchProposalData(proposalId, url, proposalInfo.govId, proposalInfo.urlProposalNumber, true);
      
      if (freshData && freshData.title && freshData.title !== "Snapshot Proposal") {
        // Update widget with fresh data (status, votes, days left)
        console.log("🔄 [REFRESH] Updating widget with fresh data from Snapshot");
        renderStatusWidget(freshData, url, widgetId, proposalInfo);
      }
    }, 2 * 60 * 1000); // Refresh every 2 minutes
    
    console.log("✅ [REFRESH] Auto-refresh set up for widget:", widgetId, "(every 2 minutes)");
  }

  // Handle posts (saved content) - Show simple link preview (not full widget)
  api.decorateCookedElement((element) => {
    const text = element.textContent || element.innerHTML || '';
    const matches = Array.from(text.matchAll(SNAPSHOT_URL_REGEX));
    if (matches.length === 0) {
      console.log("🔵 [POST] No Snapshot URLs found in post");
      return;
    }

    console.log("🔵 [POST] Found", matches.length, "Snapshot URL(s) in saved post");
    
    // Watch for oneboxes being added dynamically (Discourse creates them asynchronously)
    const oneboxObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
          for (const node of mutation.addedNodes) {
            if (node.nodeType === 1) {
              // Check if a onebox was added
              const onebox = node.classList?.contains('onebox') || node.classList?.contains('onebox-body') 
                ? node 
                : node.querySelector?.('.onebox, .onebox-body');
              
              if (onebox) {
                const oneboxText = onebox.textContent || onebox.innerHTML || '';
                const oneboxLinks = onebox.querySelectorAll?.('a[href*="snapshot.org"]') || [];
                if (oneboxText.match(SNAPSHOT_URL_REGEX) || (oneboxLinks && oneboxLinks.length > 0)) {
                  console.log("🔵 [POST] Onebox detected, will replace with custom preview");
                  // Re-run the replacement logic for all matches
                  setTimeout(() => {
                    for (const match of matches) {
                      const url = match[0];
                      const proposalInfo = extractProposalInfo(url);
                      if (proposalInfo) {
                        let widgetId = proposalInfo.internalId || proposalInfo.urlProposalNumber;
                        if (!widgetId) {
                          const urlHash = url.split('').reduce((acc, char) => {
                            return ((acc << 5) - acc) + char.charCodeAt(0);
                          }, 0);
                          widgetId = `proposal_${Math.abs(urlHash)}`;
                        }
                        const existingPreview = element.querySelector(`[data-tally-preview-id="${widgetId}"]`);
                        if (!existingPreview) {
                          // Onebox was added, need to replace it
                          const previewContainer = document.createElement("div");
                          previewContainer.className = "tally-url-preview";
                          previewContainer.setAttribute("data-tally-preview-id", widgetId);
                          previewContainer.innerHTML = `
                            <div class="tally-preview-content">
                              <div class="tally-preview-loading">Loading proposal...</div>
                            </div>
                          `;
                          if (onebox.parentNode) {
                            onebox.parentNode.replaceChild(previewContainer, onebox);
                            // Fetch and render data
                            const proposalId = proposalInfo.isInternalId ? proposalInfo.internalId : null;
                            fetchProposalData(proposalId, url, proposalInfo.govId, proposalInfo.urlProposalNumber)
                              .then(data => {
                                if (data && data.title && data.title !== "Snapshot Proposal") {
                                  const title = (data.title || 'Snapshot Proposal').trim();
                                  const description = (data.description || '').trim();
                                  previewContainer.innerHTML = `
                                    <div class="tally-preview-content">
                                      <a href="${url}" target="_blank" rel="noopener" class="tally-preview-link">
                                        <strong>${escapeHtml(title)}</strong>
                                      </a>
                                      ${description ? `
                                        <div class="tally-preview-description">${escapeHtml(description)}</div>
                                      ` : '<div class="tally-preview-description" style="color: #9ca3af; font-style: italic;">No description available</div>'}
                                    </div>
                                  `;
                                }
                              })
                              .catch(() => {
                                previewContainer.innerHTML = `
                                  <div class="tally-preview-content">
                                    <a href="${url}" target="_blank" rel="noopener" class="tally-preview-link">
                                      <strong>Snapshot Proposal</strong>
                                    </a>
                                  </div>
                                `;
                              });
                          }
                        }
                      }
                    }
                  }, 100);
                }
              }
            }
          }
        }
      }
    });
    
    // Start observing for onebox additions
    oneboxObserver.observe(element, { childList: true, subtree: true });
    
    // Stop observing after 10 seconds (oneboxes are usually created within a few seconds)
    setTimeout(() => {
      oneboxObserver.disconnect();
    }, 10000);

    for (const match of matches) {
      const url = match[0];
      console.log("🔵 [POST] Processing URL:", url);
      
      const proposalInfo = extractProposalInfo(url);
      if (!proposalInfo) {
        console.warn("❌ [POST] Could not extract proposal info");
        continue;
      }

      // Create unique widget ID - use internalId if available, otherwise create hash from URL
      let widgetId = proposalInfo.internalId || proposalInfo.urlProposalNumber;
      if (!widgetId) {
        // Create a simple hash from URL for uniqueness
        const urlHash = url.split('').reduce((acc, char) => {
          return ((acc << 5) - acc) + char.charCodeAt(0);
        }, 0);
        widgetId = `proposal_${Math.abs(urlHash)}`;
      }
      console.log("🔵 [POST] Widget ID:", widgetId, "for URL:", url);
      
      // Check if already processed
      const existingPreview = element.querySelector(`[data-tally-preview-id="${widgetId}"]`);
      if (existingPreview) {
        console.log("🔵 [POST] Preview already exists, skipping");
        continue;
      }

      // Create simple preview container
      const previewContainer = document.createElement("div");
      previewContainer.className = "tally-url-preview";
      previewContainer.setAttribute("data-tally-preview-id", widgetId);
      
      // Show loading state
      previewContainer.innerHTML = `
        <div class="tally-preview-content">
          <div class="tally-preview-loading">Loading proposal...</div>
        </div>
      `;

      // Function to find and replace URL element with our preview
      const findAndReplaceUrl = (retryCount = 0) => {
        // Find URL element (link or onebox) - try multiple methods
        let urlElement = null;
        
        // Method 1: Find onebox first (Discourse creates these asynchronously)
        const oneboxes = element.querySelectorAll('.onebox, .onebox-body, .onebox-result');
        for (const onebox of oneboxes) {
          const oneboxText = onebox.textContent || onebox.innerHTML || '';
          const oneboxLinks = onebox.querySelectorAll('a[href*="tally.xyz"], a[href*="tally.so"]');
          if (oneboxText.includes(url) || oneboxLinks.length > 0) {
            urlElement = onebox;
            console.log("✅ [POST] Found URL in onebox");
            break;
          }
        }
        
        // Method 2: Find by href (link)
        if (!urlElement) {
          const links = element.querySelectorAll('a');
          for (const link of links) {
            const linkHref = link.href || link.getAttribute('href') || '';
            const linkText = link.textContent || '';
            if (linkHref.includes(url) || linkText.includes(url) || linkHref === url) {
              urlElement = link;
              console.log("✅ [POST] Found URL in <a> tag");
              break;
            }
          }
        }
        
        // Method 3: Find by text content (plain text URL)
        if (!urlElement) {
          const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
          let node;
          while (node = walker.nextNode()) {
            if (node.textContent && node.textContent.includes(url)) {
              urlElement = node.parentElement;
              console.log("✅ [POST] Found URL in text node");
              break;
            }
          }
        }

        // If we found the element, replace it
        if (urlElement && urlElement.parentNode) {
          // Check if we already replaced it
          if (urlElement.classList.contains('tally-url-preview') || urlElement.closest('.tally-url-preview')) {
            console.log("🔵 [POST] Already replaced, skipping");
            return true;
          }
          
          console.log("✅ [POST] Replacing URL element with preview");
          urlElement.parentNode.replaceChild(previewContainer, urlElement);
          return true;
        } else if (retryCount < 5) {
          // Onebox might not be created yet, retry after a delay
          console.log(`🔵 [POST] URL element not found (attempt ${retryCount + 1}/5), retrying in 500ms...`);
          setTimeout(() => findAndReplaceUrl(retryCount + 1), 500);
          return false;
        } else {
          // Last resort: append to post
          console.log("✅ [POST] Appending preview to post (URL element not found after retries)");
          element.appendChild(previewContainer);
          return true;
        }
      };
      
      // Try to find and replace immediately, with retries for async oneboxes
      findAndReplaceUrl();
      
      // Fetch and show preview (title + description + link)
      const proposalId = proposalInfo.isInternalId ? proposalInfo.internalId : null;
      console.log("🔵 [POST] Fetching proposal data for URL:", url, "ID:", proposalId, "govId:", proposalInfo.govId, "urlNumber:", proposalInfo.urlProposalNumber);
      
      fetchProposalData(proposalId, url, proposalInfo.govId, proposalInfo.urlProposalNumber)
        .then(data => {
          console.log("✅ [POST] Proposal data received - Title:", data?.title, "Has description:", !!data?.description, "Description length:", data?.description?.length || 0);
          
          // Ensure consistent rendering for all posts
          if (data && data.title && data.title !== "Snapshot Proposal") {
            const title = (data.title || 'Snapshot Proposal').trim();
            const description = (data.description || '').trim();
            
            console.log("🔵 [POST] Rendering preview - Title length:", title.length, "Description length:", description.length);
            console.log("🔵 [POST] Description exists?", !!description, "Description empty?", description === '');
            
            // Always show title, and description if available (consistent format)
            // Show description even if it's very long (CSS will handle overflow with max-height)
            previewContainer.innerHTML = `
              <div class="tally-preview-content">
                <a href="${url}" target="_blank" rel="noopener" class="tally-preview-link">
                  <strong>${escapeHtml(title)}</strong>
                </a>
                ${description ? `
                  <div class="tally-preview-description">${escapeHtml(description)}</div>
                ` : '<div class="tally-preview-description" style="color: #9ca3af; font-style: italic;">No description available</div>'}
              </div>
            `;
            console.log("✅ [POST] Preview rendered - Title:", title.substring(0, 50), "Description:", description ? (description.length > 50 ? description.substring(0, 50) + "..." : description) : "none");
            
            // Don't create sidebar widget here - let scroll tracking handle it
            // The sidebar widget will be created by updateWidgetForVisibleProposal()
            // when this post becomes visible
          } else {
            console.warn("⚠️ [POST] Invalid data, showing title only");
            previewContainer.innerHTML = `
              <div class="tally-preview-content">
                <a href="${url}" target="_blank" rel="noopener" class="tally-preview-link">
                  <strong>Snapshot Proposal</strong>
                </a>
              </div>
            `;
          }
        })
        .catch(err => {
          console.error("❌ [POST] Error loading proposal:", err);
          previewContainer.innerHTML = `
            <div class="tally-preview-content">
              <a href="${url}" target="_blank" rel="noopener" class="tally-preview-link">
                <strong>Snapshot Proposal</strong>
              </a>
            </div>
          `;
        });
    }
  }, { id: "arbitrium-tally-widget" });

  // Handle composer (reply box and new posts)
  api.modifyClass("component:composer-editor", {
    didInsertElement() {
      const checkForUrls = () => {
        // Find textarea - try multiple selectors
        // Check if this.element exists first
        if (!this.element) {
          console.log("🔵 [COMPOSER] Element not available");
          return;
        }
        
        const textarea = this.element.querySelector?.('.d-editor-input') ||
                        document.querySelector('.d-editor-input') ||
                        document.querySelector('textarea.d-editor-input');
        if (!textarea) {
          console.log("🔵 [COMPOSER] Textarea not found yet");
          return;
        }

        const text = textarea.value || textarea.textContent || '';
        console.log("🔵 [COMPOSER] Checking text for Snapshot URLs:", text.substring(0, 100));
        const matches = Array.from(text.matchAll(SNAPSHOT_URL_REGEX));
        if (matches.length === 0) {
          // Remove widgets if no URLs
          document.querySelectorAll('[data-composer-widget-id]').forEach(w => w.remove());
          return;
        }
        
        console.log("✅ [COMPOSER] Found", matches.length, "Snapshot URL(s) in composer");

        // Find the composer container
        const composerElement = this.element.closest(".d-editor-container") ||
                               document.querySelector(".d-editor-container");
        if (!composerElement) {
          console.log("🔵 [COMPOSER] Composer element not found");
          return;
        }

        // Find the main composer wrapper/popup that contains everything
        const composerWrapper = composerElement.closest(".composer-popup") ||
                               composerElement.closest(".composer-container") ||
                               document.querySelector(".composer-popup");
        
        if (!composerWrapper) {
          console.log("🔵 [COMPOSER] Composer wrapper not found");
          return;
        }

        console.log("🔵 [COMPOSER] Found composer wrapper:", composerWrapper.className);

        for (const match of matches) {
          const url = match[0];
          const proposalInfo = extractProposalInfo(url);
          if (!proposalInfo) {continue;}

          // Create unique widget ID - use internalId if available, otherwise create hash from URL
          let widgetId = proposalInfo.internalId || proposalInfo.urlProposalNumber;
          if (!widgetId) {
            // Create a simple hash from URL for uniqueness
            const urlHash = url.split('').reduce((acc, char) => {
              return ((acc << 5) - acc) + char.charCodeAt(0);
            }, 0);
            widgetId = `proposal_${Math.abs(urlHash)}`;
          }
          const existingWidget = composerWrapper.querySelector(`[data-composer-widget-id="${widgetId}"]`);
          if (existingWidget) {continue;}

          const widgetContainer = document.createElement("div");
          widgetContainer.className = "arbitrium-proposal-widget-container composer-widget";
          widgetContainer.setAttribute("data-composer-widget-id", widgetId);
          widgetContainer.setAttribute("data-url", url);

          widgetContainer.innerHTML = `
            <div class="arbitrium-proposal-widget loading">
              <div class="loading-spinner"></div>
              <span>Loading proposal preview...</span>
            </div>
          `;

          // Insert widget to create: Reply Box | Numbers (1/5) | Widget Box
          // Insert as sibling after composer element, on the right side
          if (composerElement.nextSibling) {
            composerElement.parentNode.insertBefore(widgetContainer, composerElement.nextSibling);
          } else {
            composerElement.parentNode.appendChild(widgetContainer);
          }
          
          console.log("✅ [COMPOSER] Widget inserted - Layout: Reply Box | Numbers | Widget");

          // Fetch proposal data and render widget (don't modify reply box)
          const proposalId = proposalInfo.isInternalId ? proposalInfo.internalId : null;
          fetchProposalData(proposalId, url, proposalInfo.govId, proposalInfo.urlProposalNumber)
            .then(data => {
              if (data && data.title && data.title !== "Snapshot Proposal") {
                // Render widget only (don't modify reply box textarea)
                renderProposalWidget(widgetContainer, data, url);
                console.log("✅ [COMPOSER] Widget rendered successfully");
              }
            })
            .catch(err => {
              console.error("❌ [COMPOSER] Error loading proposal:", err);
              widgetContainer.innerHTML = `
                <div class="arbitrium-proposal-widget error">
                  <p>Unable to load proposal</p>
                  <a href="${url}" target="_blank">View on Tally</a>
                </div>
              `;
            });
        }
      };

      // Wait for textarea to be available, then set up listeners
      const setupListeners = () => {
        // Check if this.element exists before trying to use it
        if (!this.element) {
          console.log("🔵 [COMPOSER] Element not available in setupListeners");
          return;
        }
        
        const textarea = this.element.querySelector('.d-editor-input') ||
                        document.querySelector('.d-editor-input') ||
                        document.querySelector('textarea.d-editor-input');
        if (textarea) {
          console.log("✅ [COMPOSER] Textarea found, setting up listeners");
          // Remove old listeners to avoid duplicates
          textarea.removeEventListener('input', checkForUrls);
          textarea.removeEventListener('paste', checkForUrls);
          textarea.removeEventListener('keyup', checkForUrls);
          // Add listeners
          textarea.addEventListener('input', checkForUrls, { passive: true });
          textarea.addEventListener('paste', checkForUrls, { passive: true });
          textarea.addEventListener('keyup', checkForUrls, { passive: true });
          // Initial check
          setTimeout(checkForUrls, 100);
        } else {
          // Retry after a short delay (only if element still exists)
          if (this.element) {
          setTimeout(setupListeners, 200);
          }
        }
      };

      // Start checking for URLs periodically (more frequent for better detection)
      // Wrap in a function that checks if element still exists
      const intervalId = setInterval(() => {
        if (this.element) {
          checkForUrls();
        } else {
          // Element destroyed, clear interval
          clearInterval(intervalId);
        }
      }, 500);
      
      // Set up event listeners when textarea is ready
      setupListeners();
      
      // Also observe DOM changes for composer
      const composerObserver = new MutationObserver(() => {
        // Only run if element still exists
        if (this.element) {
        setupListeners();
        checkForUrls();
        }
      });
      
      const composerContainer = document.querySelector('.composer-popup, .composer-container, .d-editor-container');
      if (composerContainer) {
        composerObserver.observe(composerContainer, { childList: true, subtree: true });
      }
      
      // Cleanup on destroy
      if (this.element) {
      this.element.addEventListener('willDestroyElement', () => {
        clearInterval(intervalId);
        composerObserver.disconnect();
      }, { once: true });
      }
    }
  }, { pluginId: "arbitrium-tally-widget-composer" });

  // Global composer detection (fallback for reply box and new posts)
  // This watches for any textarea changes globally - works for blue button, grey box, and new topic
  const setupGlobalComposerDetection = () => {
    const checkAllComposers = () => {
      // Find ALL textareas and contenteditable elements, then filter to only those in composers
      const allTextareas = document.querySelectorAll('textarea, [contenteditable="true"]');
      
      // Filter to only those inside an OPEN composer container
      const activeTextareas = Array.from(allTextareas).filter(ta => {
        // Check if it's inside a composer
        const composerContainer = ta.closest('.d-editor-container, .composer-popup, .composer-container, .composer-fields, .d-editor, .composer, #reply-control, .topic-composer, .composer-wrapper, .reply-to, .topic-composer-container, [class*="composer"]');
        
        if (!composerContainer) {return false;}
        
        // Check if composer is open (not closed/hidden)
        const isClosed = composerContainer.classList.contains('closed') || 
                        composerContainer.classList.contains('hidden') ||
                        composerContainer.style.display === 'none' ||
                        window.getComputedStyle(composerContainer).display === 'none';
        
        if (isClosed) {return false;}
        
        // Check if textarea is visible
        const isVisible = ta.offsetParent !== null || 
                         window.getComputedStyle(ta).display !== 'none' ||
                         window.getComputedStyle(ta).visibility !== 'hidden';
        
        return isVisible;
      });
      
      if (activeTextareas.length > 0) {
        console.log("✅ [GLOBAL COMPOSER] Found", activeTextareas.length, "active composer textareas");
        activeTextareas.forEach((ta, idx) => {
          const composer = ta.closest('.d-editor-container, .composer-popup, .composer-container, #reply-control');
          console.log(`  [${idx}] Composer:`, composer?.className || composer?.id, "Textarea:", ta.tagName, ta.className);
        });
      } else {
        // Debug: log what composers exist and their state
        const composers = document.querySelectorAll('.composer-popup, .composer-container, #reply-control, .d-editor-container, [class*="composer"]');
        if (composers.length > 0) {
          const openComposers = Array.from(composers).filter(c => 
            !c.classList.contains('closed') && 
            !c.classList.contains('hidden') &&
            window.getComputedStyle(c).display !== 'none'
          );
          
          if (openComposers.length > 0) {
            console.log("🔵 [GLOBAL COMPOSER] Found", openComposers.length, "OPEN composer containers but no active textareas");
            openComposers.forEach((c, idx) => {
              const textarea = c.querySelector('textarea, [contenteditable]');
              console.log(`  [${idx}] Open Composer:`, c.className || c.id, "Has textarea:", !!textarea, "Textarea visible:", textarea ? (textarea.offsetParent !== null) : false);
            });
          } else {
            console.log("🔵 [GLOBAL COMPOSER] Found", composers.length, "composer containers but all are CLOSED");
          }
        }
      }
      
      activeTextareas.forEach(textarea => {
        const text = textarea.value || textarea.textContent || textarea.innerText || '';
        const matches = Array.from(text.matchAll(SNAPSHOT_URL_REGEX));
        
        if (matches.length > 0) {
          console.log("✅ [GLOBAL COMPOSER] Found Snapshot URL in textarea:", matches.length, "URL(s)");
          console.log("✅ [GLOBAL COMPOSER] Textarea element:", textarea.tagName, textarea.className, "Text preview:", text.substring(0, 100));
          
          // Find composer container - try multiple selectors for different composer types
          // Also check if textarea itself is visible
          const isTextareaVisible = textarea.offsetParent !== null || 
                                   window.getComputedStyle(textarea).display !== 'none';
          
          if (!isTextareaVisible) {
            console.log("⚠️ [GLOBAL COMPOSER] Textarea found but not visible, skipping");
            return;
          }
          
          const composerElement = textarea.closest(".d-editor-container") ||
                                 textarea.closest(".composer-popup") ||
                                 textarea.closest(".composer-container") ||
                                 textarea.closest(".composer-fields") ||
                                 textarea.closest(".d-editor") ||
                                 textarea.closest(".composer") ||
                                 textarea.closest("#reply-control") ||
                                 textarea.closest(".topic-composer") ||
                                 textarea.closest(".composer-wrapper") ||
                                 textarea.closest("[class*='composer']") ||
                                 textarea.parentElement; // Fallback to parent
          
          if (composerElement) {
            // Find the main wrapper - could be popup, container, or the element itself
            const composerWrapper = composerElement.closest(".composer-popup") ||
                                   composerElement.closest(".composer-container") ||
                                   composerElement.closest(".composer-wrapper") ||
                                   composerElement.closest("#reply-control") ||
                                   composerElement.closest(".topic-composer") ||
                                   composerElement;
            
            console.log("✅ [GLOBAL COMPOSER] Found composer wrapper:", composerWrapper.className || composerWrapper.id);
            
            for (const match of matches) {
              const url = match[0];
              const proposalInfo = extractProposalInfo(url);
              if (!proposalInfo) {continue;}

              let widgetId = proposalInfo.internalId || proposalInfo.urlProposalNumber;
              if (!widgetId) {
                const urlHash = url.split('').reduce((acc, char) => {
                  return ((acc << 5) - acc) + char.charCodeAt(0);
                }, 0);
                widgetId = `proposal_${Math.abs(urlHash)}`;
              }
              
              const existingWidget = composerWrapper.querySelector(`[data-composer-widget-id="${widgetId}"]`);
              if (existingWidget) {continue;}

              const widgetContainer = document.createElement("div");
              widgetContainer.className = "arbitrium-proposal-widget-container composer-widget";
              widgetContainer.setAttribute("data-composer-widget-id", widgetId);
              widgetContainer.setAttribute("data-url", url);

              widgetContainer.innerHTML = `
                <div class="arbitrium-proposal-widget loading">
                  <div class="loading-spinner"></div>
                  <span>Loading proposal preview...</span>
                </div>
              `;

              // Insert widget - try multiple insertion strategies
              // Strategy 1: Insert after composer element
              let inserted = false;
              if (composerElement.nextSibling && composerElement.parentNode) {
                composerElement.parentNode.insertBefore(widgetContainer, composerElement.nextSibling);
                inserted = true;
                console.log("✅ [GLOBAL COMPOSER] Widget inserted after composer element");
              } else if (composerElement.parentNode) {
                composerElement.parentNode.appendChild(widgetContainer);
                inserted = true;
                console.log("✅ [GLOBAL COMPOSER] Widget appended to composer parent");
              } else if (composerWrapper) {
                // Strategy 2: Insert into composer wrapper
                composerWrapper.appendChild(widgetContainer);
                inserted = true;
                console.log("✅ [GLOBAL COMPOSER] Widget appended to composer wrapper");
              } else {
                // Strategy 3: Insert after textarea
                if (textarea.parentNode) {
                  textarea.parentNode.insertBefore(widgetContainer, textarea.nextSibling);
                  inserted = true;
                  console.log("✅ [GLOBAL COMPOSER] Widget inserted after textarea");
                }
              }
              
              if (!inserted) {
                console.error("❌ [GLOBAL COMPOSER] Failed to insert widget - no valid insertion point");
                return;
              }
              
              // Make sure widget is visible
              widgetContainer.style.display = 'block';
              widgetContainer.style.visibility = 'visible';
              console.log("✅ [GLOBAL COMPOSER] Widget inserted and made visible");

              // Fetch and render
              const proposalId = proposalInfo.isInternalId ? proposalInfo.internalId : null;
              fetchProposalData(proposalId, url, proposalInfo.govId, proposalInfo.urlProposalNumber)
                .then(data => {
                  if (data && data.title && data.title !== "Snapshot Proposal") {
                    renderProposalWidget(widgetContainer, data, url);
                    console.log("✅ [GLOBAL COMPOSER] Widget rendered");
                  }
                })
                .catch(err => {
                  console.error("❌ [GLOBAL COMPOSER] Error:", err);
                  widgetContainer.innerHTML = `
                    <div class="arbitrium-proposal-widget error">
                      <p>Unable to load proposal</p>
                      <a href="${url}" target="_blank">View on Tally</a>
                    </div>
                  `;
                });
            }
          }
        } else {
          // Remove widgets if no URLs
          const composerElement = textarea.closest(".d-editor-container") ||
                                 textarea.closest(".composer-popup") ||
                                 textarea.closest(".composer-container") ||
                                 textarea.closest(".composer-fields") ||
                                 textarea.closest(".d-editor") ||
                                 textarea.closest(".composer") ||
                                 textarea.closest("#reply-control") ||
                                 textarea.closest(".topic-composer");
          if (composerElement) {
            const composerWrapper = composerElement.closest(".composer-popup") ||
                                   composerElement.closest(".composer-container") ||
                                   composerElement.closest(".composer-wrapper") ||
                                   composerElement.closest("#reply-control") ||
                                   composerElement.closest(".topic-composer") ||
                                   composerElement;
            composerWrapper.querySelectorAll('[data-composer-widget-id]').forEach(w => {
              console.log("🔵 [GLOBAL COMPOSER] Removing widget (no URLs)");
              w.remove();
            });
          }
        }
      });
    };

    // Aggressive retry mechanism for composers that are opening
    const composerRetryMap = new Map(); // Track composers we're waiting for
    
    const checkComposerWithRetry = (composerElement, retryCount = 0) => {
      const maxRetries = 20; // Try for up to 10 seconds (20 * 500ms)
      const textarea = composerElement.querySelector('textarea, [contenteditable="true"]');
      
      if (textarea && textarea.offsetParent !== null) {
        // Found active textarea!
        console.log("✅ [GLOBAL COMPOSER] Found textarea in composer after", retryCount, "retries");
        composerRetryMap.delete(composerElement);
        checkAllComposers();
        return;
      }
      
      if (retryCount < maxRetries) {
        composerRetryMap.set(composerElement, retryCount + 1);
        setTimeout(() => checkComposerWithRetry(composerElement, retryCount + 1), 500);
      } else {
        console.log("⚠️ [GLOBAL COMPOSER] Gave up waiting for textarea in composer after", maxRetries, "retries");
        composerRetryMap.delete(composerElement);
      }
    };
    
    // Also check ALL visible textareas directly (more aggressive approach)
    const checkAllVisibleTextareas = () => {
      const allTextareas = document.querySelectorAll('textarea, [contenteditable="true"]');
      allTextareas.forEach(textarea => {
        // Check if visible
        const isVisible = textarea.offsetParent !== null || 
                         window.getComputedStyle(textarea).display !== 'none';
        
        if (!isVisible) {return;}
        
        const text = textarea.value || textarea.textContent || textarea.innerText || '';
        const matches = Array.from(text.matchAll(SNAPSHOT_URL_REGEX));
        
        if (matches.length > 0) {
          // Check if we already have a widget for this textarea
          const composer = textarea.closest('.d-editor-container, .composer-popup, .composer-container, #reply-control, [class*="composer"]') || textarea.parentElement;
          if (composer) {
            const existingWidget = composer.querySelector('[data-composer-widget-id]');
            if (existingWidget) {return;} // Already has widget
            
            console.log("✅ [AGGRESSIVE CHECK] Found Snapshot URL in visible textarea, creating widget");
            // Trigger the main check which will create the widget
            checkAllComposers();
          }
        }
      });
    };
    
    // Check periodically and on DOM changes
    // eslint-disable-next-line no-unused-vars
    const checkInterval = setInterval(() => {
      checkAllComposers();
      checkAllVisibleTextareas(); // Also do aggressive check
      
      // Also check for open composers that don't have textareas yet
      const openComposers = document.querySelectorAll('.composer-popup:not(.closed), .composer-container:not(.closed), #reply-control:not(.closed), .d-editor-container:not(.closed)');
      openComposers.forEach(composer => {
        if (!composerRetryMap.has(composer)) {
          const hasTextarea = composer.querySelector('textarea, [contenteditable="true"]');
          if (!hasTextarea || hasTextarea.offsetParent === null) {
            console.log("🔵 [GLOBAL COMPOSER] Open composer found without textarea, starting retry");
            checkComposerWithRetry(composer);
          }
        }
      });
    }, 500);
    
    // Watch for composer opening/closing and textarea changes
    const observer = new MutationObserver((mutations) => {
      let shouldCheck = false;
      
      mutations.forEach(mutation => {
        // Check if a composer was added or opened
        mutation.addedNodes.forEach(node => {
          if (node.nodeType === 1) { // Element node
            if (node.matches?.('.composer-popup, .composer-container, #reply-control, .d-editor-container, textarea, [contenteditable]') ||
                node.querySelector?.('.composer-popup, .composer-container, #reply-control, .d-editor-container, .d-editor-input, textarea, [contenteditable]')) {
              shouldCheck = true;
            }
          }
        });
        
        // Check if composer class changed (opened/closed)
        if (mutation.type === 'attributes' && mutation.attributeName === 'class') {
          const target = mutation.target;
          if (target.matches?.('.composer-popup, .composer-container, #reply-control, .d-editor-container, [class*="composer"]')) {
            // Check if it was opened (removed 'closed' class or added 'open' class)
            const wasClosed = mutation.oldValue?.includes('closed');
            const isNowOpen = !target.classList.contains('closed') && !target.classList.contains('hidden');
            if (wasClosed && isNowOpen) {
              console.log("✅ [GLOBAL COMPOSER] Composer opened, starting retry mechanism");
              shouldCheck = true;
              // Start aggressive retry for this composer
              setTimeout(() => checkComposerWithRetry(target), 100);
            }
          }
        }
      });
      
      if (shouldCheck) {
        setTimeout(checkAllComposers, 300);
      }
    });
    observer.observe(document.body, { 
      childList: true, 
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'style']
    });
    
    // Also watch for when composer becomes visible
    const visibilityObserver = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          console.log("✅ [GLOBAL COMPOSER] Composer became visible, checking for URLs");
          setTimeout(checkAllComposers, 200);
        }
      });
    }, { threshold: 0.1 });
    
    // Observe any composer containers
    const observeComposers = () => {
      document.querySelectorAll('.composer-popup, .composer-container, #reply-control, .d-editor-container').forEach(el => {
        visibilityObserver.observe(el);
      });
    };
    observeComposers();
    setInterval(observeComposers, 2000); // Re-observe periodically
    
    // Listen to ALL input/paste/keyup events and check if they're in a composer
    const handleComposerEvent = (e) => {
      const target = e.target;
      // Check if target is or is inside a composer
      const isInComposer = target.matches && (
        target.matches('.d-editor-input, textarea, [contenteditable="true"]') ||
        target.closest('.d-editor-container, .composer-popup, .composer-container, .composer-fields, .d-editor, .composer, #reply-control, .topic-composer, .composer-wrapper, .reply-to, .topic-composer-container')
      );
      
      if (isInComposer) {
        console.log("✅ [GLOBAL COMPOSER] Event detected in composer, checking for URLs");
        setTimeout(checkAllComposers, 100);
      }
    };
    
    document.addEventListener('input', handleComposerEvent, true);
    document.addEventListener('paste', handleComposerEvent, true);
    document.addEventListener('keyup', handleComposerEvent, true);
    
    // Also listen for focus events on composer elements
    document.addEventListener('focusin', (e) => {
      const target = e.target;
      if (target.matches && (
        target.matches('textarea, [contenteditable="true"]') ||
        target.closest('.d-editor-container, .composer-popup, .composer-container, #reply-control')
      )) {
        console.log("✅ [GLOBAL COMPOSER] Composer focused, checking for URLs");
        setTimeout(checkAllComposers, 200);
        
        // Also start retry for the composer container
        const composer = target.closest('.d-editor-container, .composer-popup, .composer-container, #reply-control');
        if (composer && !composerRetryMap.has(composer)) {
          checkComposerWithRetry(composer);
        }
      }
    }, true);
    
    // Listen for click events on reply/new topic buttons to catch composer opening
    document.addEventListener('click', (e) => {
      const target = e.target;
      // Check if it's a reply button or new topic button
      if (target.matches && (
        target.matches('.reply, .create, .btn-primary, [data-action="reply"], [data-action="create"], button[aria-label*="Reply"], button[aria-label*="Create"]') ||
        target.closest('.reply, .create, .btn-primary, [data-action="reply"], [data-action="create"]')
      )) {
        console.log("✅ [GLOBAL COMPOSER] Reply/new topic button clicked, will check for composer");
        // Wait a bit for composer to open, then start checking
        setTimeout(() => {
          const openComposers = document.querySelectorAll('.composer-popup:not(.closed), .composer-container:not(.closed), #reply-control:not(.closed), .d-editor-container:not(.closed)');
          openComposers.forEach(composer => {
            if (!composerRetryMap.has(composer)) {
              console.log("🔵 [GLOBAL COMPOSER] Starting retry for composer after button click");
              checkComposerWithRetry(composer);
            }
          });
        }, 500);
      }
    }, true);
  };

  // Initialize global composer detection
  setTimeout(setupGlobalComposerDetection, 500);

  // Initialize topic widget (shows first proposal found, no scroll tracking)
  setTimeout(() => {
    setupTopicWatcher();
  }, 1000);

  // Re-initialize topic widget on page changes
  api.onPageChange(() => {
    // Reset current proposal so we can detect the first one again
    currentVisibleProposal = null;
    // Reset initialization flag on page change
    widgetsInitialized = false;
    initialProposalUrls.clear();
    setTimeout(() => {
      setupTopicWatcher();
      setupGlobalComposerDetection();
    }, 500);
  });
});


