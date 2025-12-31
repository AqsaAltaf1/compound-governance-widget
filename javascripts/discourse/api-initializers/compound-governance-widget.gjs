import { apiInitializer } from "discourse/lib/api";

import {
  AAVE_FORUM_URL_REGEX,
  AAVE_V3_SUBGRAPH,
  AIP_URL_REGEX,
  SNAPSHOT_URL_REGEX
} from "../lib/config/constants";
import { renderMultiStageWidget } from "../lib/dom/multi-stage-widget";
import {
  hideWidgetIfNoProposal,
  renderProposalWidget,
  showNetworkErrorWidget
} from "../lib/dom/renderer";
import { fetchAIPProposal, getStateMapping } from "../lib/services/aip-service";
import { fetchWithRetry } from "../lib/services/fetch-service";
import { fetchSnapshotProposal } from "../lib/services/snapshot-service";
import { calculateTimeRemaining } from "../lib/utils/date-utils";
import { escapeHtml, formatStatusForDisplay, formatVoteAmount } from "../lib/utils/formatting";
import {
  extractAIPProposalInfo,
  extractProposalInfo,
  extractSnapshotProposalInfo
} from "../lib/utils/url-parser";

console.log("✅ Aave Governance Widget: JavaScript file loaded!");

/**
 * PLATFORM SUPPORT:
 * 
 * ✅ SNAPSHOT (snapshot.org)
 *    - Full support: Fetches proposal data, voting results, status
 *    - URL formats: snapshot.org/#/{space}/{proposal-id}
 *    - Stages: Temp Check, ARFC
 *    - Voting: Happens on Snapshot platform
 * 
 * ✅ AAVE GOVERNANCE (AIP - Aave Improvement Proposals)
 *    - URL recognition: ✅ Supported (robust extraction)
 *      - app.aave.com/governance/v3/proposal/?proposalId={id}
 *      - app.aave.com/governance/{id}
 *      - governance.aave.com/t/{slug}/{id}
 *      - vote.onaave.com/proposal/?proposalId={id}
 *    - Data fetching: ✅ Robust architecture
 *      - Flow: URL → extract proposalId → fetch on-chain (source of truth) → enrich with subgraph → render
 *      - Primary: On-chain data via ethers.js (no CORS, no API dependency, future-proof)
 *      - Enhancement: Subgraph for metadata (titles, descriptions)
 *      - Fallback: JSON Data API if on-chain unavailable
 *      - IMPORTANT: proposalId is the primary key - URL is only an identifier carrier
 *    - Benefits:
 *      - No CORS issues (direct blockchain access)
 *      - No backend required (pure frontend)
 *      - Future-proof (works even if APIs change)
 *      - Source of truth (on-chain data is authoritative)
 */

export default apiInitializer((api) => {
  console.log("✅ Aave Governance Widget: apiInitializer called!");

  // Track errors that are being handled to avoid false positives in unhandled rejection handler
  const handledErrors = new WeakSet();
  
  // Global unhandled rejection handler to prevent console errors
  // This catches any promise rejections that slip through our error handling
  window.addEventListener('unhandledrejection', (event) => {
    // Check if this is one of our Snapshot fetch errors
    if (event.reason && (
      event.reason.message?.includes('Failed to fetch') ||
      event.reason.message?.includes('ERR_CONNECTION_RESET') ||
      event.reason.message?.includes('network') ||
      event.reason?.name === 'TypeError'
    )) {
      // Check if this error is already being handled
      if (handledErrors.has(event.reason)) {
        // Silently suppress - error is already being handled
        event.preventDefault();
        return;
      }
      
      // This might be a truly unhandled error, but it's likely from our retry logic
      // Suppress it silently - errors are handled gracefully by retry logic and catch blocks
      // The retry logic already logs appropriate warnings, so we don't need to log here
      event.preventDefault();
      return;
    }
    // Let other unhandled rejections through
  });

  // Configuration constants are now imported from ../lib/config/constants
  
  // Function to ensure ethers.js is loaded
  async function ensureEthersLoaded() {
    // Check if already loaded
    if (window.ethers) {
      return window.ethers;
    }
    
    // Start loading ethers.js v5 (stable version)
    let ethersPromise = new Promise((resolve, reject) => {
      try {
        const script = document.createElement('script');
        // Use jsDelivr CDN for reliable loading
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
          ethersPromise = null; // Reset so we can try again
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
  
  // NOTE: TheGraph subgraphs have been removed by TheGraph
  // The endpoints below are kept for reference but will not work
  // const AAVE_SUBGRAPH_MAINNET = "https://api.thegraph.com/subgraphs/name/aave/governance-v3-mainnet"; // REMOVED
  // const AAVE_SUBGRAPH_POLYGON = "https://api.thegraph.com/subgraphs/name/aave/governance-v3-voting-polygon"; // REMOVED
  // const AAVE_SUBGRAPH_AVALANCHE = "https://api.thegraph.com/subgraphs/name/aave/governance-v3-voting-avalanche"; // REMOVED
  
  // Constants are now imported from ../lib/config/constants
  const proposalCache = new Map();

  // Removed unused truncate function

  // Utility functions are now imported from ../lib/utils/*


  // URL parsing functions are now imported from ../lib/utils/url-parser
  // Fetch with retry is now imported from ../lib/services/fetch-service
  // Snapshot service is now imported from ../lib/services/snapshot-service

  // Wrapper function to call Snapshot service with shared state (proposalCache, handledErrors)
  async function fetchSnapshotProposalLocal(space, proposalId, cacheKey, isTestnet = false) {
    return await fetchSnapshotProposal(space, proposalId, cacheKey, isTestnet, proposalCache, handledErrors);
  }

  // AIP service is now imported from ../lib/services/aip-service

  // Wrapper function to call AIP service with shared state and config
  async function fetchAIPProposalLocal(proposalId, cacheKey, urlSource = 'app.aave.com') {
    // Get config from global variables (if available)
    // These are expected to be defined as global variables in the Discourse theme settings
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

  // mergeProposalData, parseFrontMatter, and fetchAIPMarkdown are now imported from ../lib/services/aip-service

  // fetchAIPFromSubgraph, fetchAIPFromOnChain, getStateMapping, transformAIPDataFromOnChain are now imported from ../lib/services/aip-service

  // Old function definitions removed - using service imports instead
  // eslint-disable-next-line no-unused-vars
  async function fetchAIPFromSubgraphOld(proposalId) {
    try {
      // Convert proposalId to string and ensure it's a number
      const proposalIdStr = String(proposalId).trim();
      console.log("🔵 [AIP] Fetching proposal with ID:", proposalIdStr);
      
      const query = `
        {
          proposals(where: { proposalId: "${proposalIdStr}" }) {
            proposalId
            state
            creator
            ipfsHash
            votingDuration
            proposalMetadata {
              title
            }
            votes {
              forVotes
              againstVotes
            }
            transactions {
              id
              created {
                id
                timestamp
                blockNumber
              }
              active {
                id
                timestamp
                blockNumber
              }
            }
            votingConfig {
              id
              cooldownBeforeVotingStart
              votingDuration
            }
          }
        }
      `;
      
      console.log("🔵 [AIP] GraphQL Query:", query);

      const response = await fetchWithRetry(AAVE_V3_SUBGRAPH, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ query }),
      }, 3, 1000, handledErrors);

      if (response.ok) {
        const result = await response.json();
        console.log("🔵 [AIP] GraphQL Response:", JSON.stringify(result, null, 2));
        
        if (result.errors) {
          console.error("❌ [AIP] GraphQL Errors:", JSON.stringify(result.errors, null, 2));
          return null;
        }

        const proposals = result.data?.proposals;
        if (!proposals || proposals.length === 0) {
          console.log(`❌ [AIP] No proposal found with ID: ${proposalId}`);
          console.log("🔵 [AIP] Full response data:", result.data);
          return null;
        }
        
        console.log(`✅ [AIP] Found ${proposals.length} proposal(s) with ID: ${proposalId}`);

        const p = proposals[0];
        
        // Debug: Log the raw proposal data
        console.log("🔵 [AIP] Raw proposal data:", JSON.stringify(p, null, 2));
        console.log("🔵 [AIP] Raw votes object:", p.votes);
        console.log("🔵 [AIP] Votes type:", typeof p.votes, "Is array:", Array.isArray(p.votes));
        
        // Handle votes - could be object, array, or null
        let votesData = null;
        let votesAvailable = false;
        
        if (p.votes) {
          votesAvailable = true;
          // If votes is an array, take the first element (or aggregate)
          if (Array.isArray(p.votes)) {
            votesData = p.votes[0] || p.votes;
            console.log("🔵 [AIP] Votes is array, using:", votesData);
          } else {
            votesData = p.votes;
            console.log("🔵 [AIP] Votes is object:", votesData);
          }
        } else {
          console.warn("⚠️ [AIP] No votes data found in subgraph for proposal", proposalId);
          console.warn("⚠️ [AIP] This is common for failed/cancelled proposals - votes may not be indexed");
          votesAvailable = false;
        }
        
        console.log("🔵 [AIP] forVotes raw:", votesData?.forVotes, "type:", typeof votesData?.forVotes);
        console.log("🔵 [AIP] againstVotes raw:", votesData?.againstVotes, "type:", typeof votesData?.againstVotes);
        
        // Convert votes from wei to AAVE (exact same as ava.mjs)
        const decimals = BigInt(10 ** 18);
        
        // Get raw vote values - handle null/undefined
        // NOTE: Aave V3 subgraph does NOT have abstainVotes field - only forVotes and againstVotes
        const forVotesRaw = votesData?.forVotes || p.forVotes || null;
        const againstVotesRaw = votesData?.againstVotes || p.againstVotes || null;
        
        console.log("🔵 [AIP] Extracted - forVotesRaw:", forVotesRaw, "againstVotesRaw:", againstVotesRaw);
        
        // Convert to BigInt - exact same logic as ava.mjs: BigInt(p.votes?.forVotes || 0)
        // Handle string numbers and null/undefined
        // If votes are not available, set to null (not 0) so UI can show "N/A" or similar
        const forVotesBigInt = forVotesRaw ? BigInt(String(forVotesRaw)) : (votesAvailable ? BigInt(0) : null);
        const againstVotesBigInt = againstVotesRaw ? BigInt(String(againstVotesRaw)) : (votesAvailable ? BigInt(0) : null);
        
        console.log("🔵 [AIP] BigInt values - For:", forVotesBigInt?.toString() || 'null', "Against:", againstVotesBigInt?.toString() || 'null');
        console.log("🔵 [AIP] Decimals:", decimals.toString());
        
        // Divide by decimals to get AAVE amount (BigInt division truncates, which is correct)
        // If votes are null (not available), keep as null string for UI to handle
        const forVotes = forVotesBigInt !== null ? (forVotesBigInt / decimals).toString() : null;
        const againstVotes = againstVotesBigInt !== null ? (againstVotesBigInt / decimals).toString() : null;
        // Aave V3 doesn't support abstain - always 0
        const abstainVotes = '0';
        
        console.log("🔵 [AIP] Final converted votes - For:", forVotes || 'null (not available)', "Against:", againstVotes || 'null (not available)', "Abstain:", abstainVotes);

        // Map state to status string - use default app.aave.com mapping for subgraph
        // (Subgraph uses Aave V3 enum, but we'll allow override if urlSource is provided)
        const stateMap = getStateMapping('app.aave.com'); // Subgraph always uses Aave V3 enum
        const status = stateMap[p.state] || 'unknown';

        // Calculate votingActivationTimestamp from transactions.active.timestamp
        // This is when the proposal moves to 'Active' state (voting starts)
        let votingActivationTimestamp = null;
        let daysLeft = null;
        let hoursLeft = null;
        
        // Try to get votingActivationTimestamp from transactions.active
        if (p.transactions?.active?.timestamp) {
          votingActivationTimestamp = Number(p.transactions.active.timestamp);
          console.log("🔵 [AIP] Found votingActivationTimestamp from transactions.active:", votingActivationTimestamp);
        } else if (p.transactions?.created?.timestamp && p.votingConfig?.cooldownBeforeVotingStart) {
          // Calculate: created timestamp + cooldown period = activation timestamp
          const createdTimestamp = Number(p.transactions.created.timestamp);
          const cooldown = Number(p.votingConfig.cooldownBeforeVotingStart);
          votingActivationTimestamp = createdTimestamp + cooldown;
          console.log("🔵 [AIP] Calculated votingActivationTimestamp: created (", createdTimestamp, ") + cooldown (", cooldown, ") =", votingActivationTimestamp);
        }
        
        // Calculate end date: votingActivationTimestamp + votingDuration
        // Then calculate daysLeft and hoursLeft
        if (votingActivationTimestamp && p.votingDuration) {
          const votingDuration = Number(p.votingDuration);
          const endTimestamp = votingActivationTimestamp + votingDuration;
          
          const timeRemaining = calculateTimeRemaining(endTimestamp);
          daysLeft = timeRemaining.daysLeft;
          hoursLeft = timeRemaining.hoursLeft;
          
          console.log("🔵 [AIP] Calculated dates - Activation:", new Date(votingActivationTimestamp * 1000).toISOString(), "End:", new Date(endTimestamp * 1000).toISOString(), "Days left:", daysLeft, "Hours left:", hoursLeft);
        } else {
          console.log("⚠️ [AIP] Cannot calculate end date: votingActivationTimestamp or votingDuration missing");
          console.log("   votingActivationTimestamp:", votingActivationTimestamp, "votingDuration:", p.votingDuration);
        }

        return {
          id: p.proposalId?.toString() || proposalId.toString(),
          proposalId: p.proposalId?.toString() || proposalId.toString(),
          title: p.proposalMetadata?.title || `Proposal ${proposalId}`,
          description: null, // Description not available in this query
          status,
          state: p.state,
          creator: p.creator,
          proposer: p.creator,
          ipfsHash: p.ipfsHash,
          votingDuration: p.votingDuration,
          votingActivationTimestamp, // Add this for end date calculation
          forVotes,
          againstVotes,
          abstainVotes,
          quorum: null,
          daysLeft,
          hoursLeft,
        };
      } else {
        console.error("❌ [AIP] Subgraph response not OK:", response.status, response.statusText);
    return null;
      }
    } catch (error) {
      console.error("❌ [AIP] Subgraph fetch error:", error.message);
      return null;
    }
  }

  // Old duplicate functions removed - using imported versions from aip-service

  // formatVoteAmount is now imported from ../lib/utils/formatting
  // renderProposalWidget is now imported from ../lib/dom/renderer

  // renderProposalWidget is now imported from ../lib/dom/renderer - use directly

  // getOrCreateWidgetsContainer, updateContainerPosition are now imported from ../lib/dom/renderer
  // renderMultiStageWidget is now imported from ../lib/dom/multi-stage-widget

  // getOrCreateWidgetsContainer is now imported from ../lib/dom/renderer - use directly

  // Old function definitions removed - using imported versions

  // formatStatusForDisplay is now imported from ../lib/utils/formatting
  // renderMultiStageWidget is now imported from ../lib/dom/multi-stage-widget

  // renderMultiStageWidget is now imported from ../lib/dom/multi-stage-widget - use directly with renderingUrls and fetchingUrls

  // Old function definition removed - using imported version

  function renderStatusWidget(proposalData, originalUrl, widgetId, proposalInfo = null) {
    const statusWidgetId = `aave-status-widget-${widgetId}`;
    const proposalType = proposalData.type || 'snapshot'; // 'snapshot' or 'aip'
    
    // Check if mobile to determine update strategy
    const isMobile = window.innerWidth <= 1024 || 
                     /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
    
    // Check if widget with same ID already exists (for in-place updates during auto-refresh)
    const existingWidgetById = document.getElementById(statusWidgetId);
    if (existingWidgetById && existingWidgetById.getAttribute('data-tally-url') === originalUrl) {
      // Widget exists with same ID and URL - update in place (especially important on mobile to prevent flickering)
      console.log(`🔵 [WIDGET] Updating existing widget in place (ID: ${statusWidgetId}) to prevent flickering`);
      
      // Update the widget content in place
      // We'll generate the HTML and update innerHTML, but keep the container element
      // This prevents the widget from disappearing/reappearing on mobile
      
      // Continue with the rest of the function to generate the HTML, then update in place
      // (We'll handle this after generating the HTML)
    } else {
      // Widget doesn't exist or has different ID/URL - remove duplicates and create new
      const existingWidgetsByUrl = document.querySelectorAll(`.tally-status-widget-container[data-tally-url="${originalUrl}"]`);
      if (existingWidgetsByUrl.length > 0) {
        console.log(`🔵 [WIDGET] Found ${existingWidgetsByUrl.length} existing widget(s) with same URL, removing duplicates`);
        existingWidgetsByUrl.forEach(widget => {
          // Don't remove if it's the same widget we're about to update
          if (widget.id !== statusWidgetId) {
            widget.remove();
            // Clean up stored data
            const existingWidgetId = widget.getAttribute('data-tally-status-id');
            if (existingWidgetId) {
              delete window[`tallyWidget_${existingWidgetId}`];
              // Clear any auto-refresh intervals
              const refreshKey = `tally_refresh_${existingWidgetId}`;
              if (window[refreshKey]) {
                clearInterval(window[refreshKey]);
                delete window[refreshKey];
              }
            }
          }
        });
      } else {
        // Fallback: Remove widgets of the same type if no URL match (for backwards compatibility)
        const existingWidgetsByType = document.querySelectorAll(`.tally-status-widget-container[data-proposal-type="${proposalType}"]`);
        if (existingWidgetsByType.length > 0) {
          console.log(`🔵 [WIDGET] No URL match found, removing ${existingWidgetsByType.length} existing ${proposalType} widget(s) by type`);
          existingWidgetsByType.forEach(widget => {
            // Don't remove if it's the same widget we're about to update
            if (widget.id !== statusWidgetId) {
              widget.remove();
              // Clean up stored data
              const existingWidgetId = widget.getAttribute('data-tally-status-id');
              if (existingWidgetId) {
                delete window[`tallyWidget_${existingWidgetId}`];
                // Clear any auto-refresh intervals
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
    
    // Store proposal info for auto-refresh
    if (proposalInfo) {
      window[`tallyWidget_${widgetId}`] = {
        proposalInfo,
        originalUrl,
        widgetId,
        lastUpdate: Date.now()
      };
    }

    // Check if widget already exists for in-place update (prevents flickering on mobile during auto-refresh)
    let statusWidget = existingWidgetById;
    const isUpdatingInPlace = statusWidget && statusWidget.getAttribute('data-tally-url') === originalUrl;
    
    if (!statusWidget) {
      // Create new widget element
      statusWidget = document.createElement("div");
      statusWidget.id = statusWidgetId;
      statusWidget.className = "tally-status-widget-container";
      statusWidget.setAttribute("data-tally-status-id", widgetId);
      statusWidget.setAttribute("data-tally-url", originalUrl);
      statusWidget.setAttribute("data-proposal-type", proposalType); // Mark widget type
    } else {
      // Update existing widget attributes (in case they changed)
      statusWidget.setAttribute("data-tally-status-id", widgetId);
      statusWidget.setAttribute("data-tally-url", originalUrl);
      statusWidget.setAttribute("data-proposal-type", proposalType);
      console.log(`🔵 [WIDGET] Updating widget in place (ID: ${statusWidgetId}) to prevent flickering`);
    }

    // Get exact status from API FIRST (before any processing)
    // Preserve the exact status text (e.g., "Quorum not reached", "Defeat", etc.)
    const rawStatus = proposalData.status || 'unknown';
    const exactStatus = rawStatus; // Keep original case - don't uppercase, preserve exact text
    const status = rawStatus.toLowerCase().trim();
    
    console.log("🔵 [WIDGET] ========== STATUS DETECTION ==========");
    console.log("🔵 [WIDGET] Raw status from API (EXACT):", JSON.stringify(rawStatus));
    console.log("🔵 [WIDGET] Status length:", rawStatus.length);
    console.log("🔵 [WIDGET] Status char codes:", Array.from(rawStatus).map(c => c.charCodeAt(0)));
    console.log("🔵 [WIDGET] Normalized status (for logic):", JSON.stringify(status));
    console.log("🔵 [WIDGET] Display status (EXACT from Snapshot):", JSON.stringify(exactStatus));

    // Status detection - check in order of specificity
    // Preserve exact status text (e.g., "Quorum not reached", "Defeat", etc.)
    // Only use status flags for CSS class determination, not for display text
    const activeStatuses = ["active", "open"];
    const executedStatuses = ["executed", "crosschainexecuted", "completed"];
    const queuedStatuses = ["queued", "queuing"];
    const pendingStatuses = ["pending"];
    const defeatStatuses = ["defeat", "defeated", "rejected"];
    // eslint-disable-next-line no-unused-vars
    const quorumStatuses = ["quorum not reached", "quorumnotreached"];
    
    // Check for "pending execution" first (most specific) - handle various formats
    // API might return: "Pending execution", "pending execution", "pendingexecution", "pending_execution"
    // OR: "queued" status when proposal has passed (quorum reached, majority support) = "Pending execution"
    const normalizedStatus = status.replace(/[_\s]/g, ''); // Remove spaces and underscores
    let isPendingExecution = normalizedStatus.includes("pendingexecution") || 
                             status.includes("pending execution") ||
                             status.includes("pending_execution");
    
    // Note: We'll check if "queued" should be "pending execution" after we calculate votes/quorum below
    
    // Check for "quorum not reached" FIRST (more specific than defeat)
    // Handle various formats: "Quorum not reached", "quorum not reached", "quorumnotreached", etc.
    const isQuorumNotReached = normalizedStatus.includes("quorumnotreached") ||
                                status.includes("quorum not reached") ||
                                status.includes("quorum_not_reached") ||
                                status.includes("quorumnotreached") ||
                                (status.includes("quorum") && status.includes("not") && status.includes("reached"));
    
    console.log("🔵 [WIDGET] Quorum check - normalizedStatus:", normalizedStatus);
    console.log("🔵 [WIDGET] Quorum check - includes 'quorumnotreached':", normalizedStatus.includes("quorumnotreached"));
    console.log("🔵 [WIDGET] Quorum check - includes 'quorum not reached':", status.includes("quorum not reached"));
    console.log("🔵 [WIDGET] Quorum check - isQuorumNotReached:", isQuorumNotReached);
    
    // Check for defeat statuses (but NOT if it's quorum not reached)
    // Only match standalone "defeat" status, not if it's part of "quorum not reached"
    const isDefeat = !isQuorumNotReached && defeatStatuses.some(s => {
      const defeatWord = s.toLowerCase();
      const matches = status === defeatWord || (status.includes(defeatWord) && !status.includes("quorum"));
      if (matches) {
        console.log("🔵 [WIDGET] Defeat match found for word:", defeatWord);
      }
      return matches;
    });
    
    console.log("🔵 [WIDGET] Defeat check - isDefeat:", isDefeat);
    
    // Get voting data - use percent directly from API
    const voteStats = proposalData.voteStats || {};
    // Parse as BigInt or Number to handle very large wei amounts
    const votesFor = typeof voteStats.for?.count === 'string' ? BigInt(voteStats.for.count) : (voteStats.for?.count || 0);
    const votesAgainst = typeof voteStats.against?.count === 'string' ? BigInt(voteStats.against.count) : (voteStats.against?.count || 0);
    const votesAbstain = typeof voteStats.abstain?.count === 'string' ? BigInt(voteStats.abstain.count) : (voteStats.abstain?.count || 0);
    
    // Convert BigInt to Number for formatting (lose precision but needed for display)
    const votesForNum = typeof votesFor === 'bigint' ? Number(votesFor) : votesFor;
    const votesAgainstNum = typeof votesAgainst === 'bigint' ? Number(votesAgainst) : votesAgainst;
    const votesAbstainNum = typeof votesAbstain === 'bigint' ? Number(votesAbstain) : votesAbstain;
    
    const totalVotes = votesForNum + votesAgainstNum + votesAbstainNum;
    
    // Check quorum to determine correct status (Tally website shows "QUORUM NOT REACHED" when quorum isn't met)
    // Even though API returns "defeated", we should check quorum like Tally website does
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
    
    // Check if proposal passed (majority support - for votes > against votes)
    const hasMajoritySupport = votesForNum > votesAgainstNum;
    const proposalPassed = quorumReached && hasMajoritySupport;
    
    console.log("🔵 [WIDGET] Quorum check - threshold:", quorumNum, "total votes:", totalVotes, "reached:", quorumReached);
    console.log("🔵 [WIDGET] Majority support - for:", votesForNum, "against:", votesAgainstNum, "passed:", proposalPassed);
    
    // If status is "queued" and proposal passed (quorum + majority), it's "Pending execution" (like Tally website)
    if (!isPendingExecution && status === "queued" && proposalPassed) {
      isPendingExecution = true;
      console.log("🔵 [WIDGET] Status is 'queued' but proposal passed - treating as 'Pending execution' (like Tally website)");
    }
    
    // If status is "defeated" but quorum wasn't reached, display "Quorum not reached" (like Tally website)
    const isActuallyQuorumNotReached = isQuorumNotReached || 
                                       (quorumNotReachedByVotes && (status === "defeated" || status === "defeat"));
    const finalIsQuorumNotReached = isActuallyQuorumNotReached;
    const finalIsDefeat = isDefeat && !finalIsQuorumNotReached && quorumReached;
    
    // formatStatusForDisplay is now imported from ../lib/utils/formatting - use directly
    
    // Determine display status - prioritize showing actual status from proposal
    let displayStatus = exactStatus;
    
    // Special cases that need override (quorum/execution logic)
    if (isPendingExecution && status === "queued") {
      displayStatus = "Pending Execution";
      console.log("🔵 [WIDGET] Overriding status: 'queued' → 'Pending Execution' (proposal passed)");
    } else if (finalIsQuorumNotReached && !isQuorumNotReached) {
      displayStatus = "Quorum Not Reached";
      console.log("🔵 [WIDGET] Overriding status: 'defeated' → 'Quorum Not Reached' (quorum not met)");
    } else if (finalIsDefeat && quorumReached) {
      // Show "Defeated" if quorum was reached but proposal was defeated
      displayStatus = "Defeated";
      console.log("🔵 [WIDGET] Status: 'Defeated' (quorum reached but proposal defeated)");
    } else {
      // Use the actual status from the proposal, properly formatted
      // This ensures we show "Rejected", "Failed", "Cancelled", etc. as they are
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

    // Use percent directly from API response (more accurate)
    const percentFor = voteStats.for?.percent ? Number(voteStats.for.percent) : 0;
    const percentAgainst = voteStats.against?.percent ? Number(voteStats.against.percent) : 0;
    const percentAbstain = voteStats.abstain?.percent ? Number(voteStats.abstain.percent) : 0;

    console.log("🔵 [WIDGET] Vote data:", { votesFor, votesAgainst, votesAbstain, totalVotes });
    console.log("🔵 [WIDGET] Percentages from API:", { percentFor, percentAgainst, percentAbstain });
    
    // Recalculate status flags with final quorum/defeat values
    const isActive = !isPendingExecution && !finalIsDefeat && !finalIsQuorumNotReached && activeStatuses.includes(status);
    const isExecuted = !isPendingExecution && !finalIsDefeat && !finalIsQuorumNotReached && executedStatuses.includes(status);
    const isQueued = !isPendingExecution && !finalIsDefeat && !finalIsQuorumNotReached && queuedStatuses.includes(status);
    const isPending = !isPendingExecution && !finalIsDefeat && !finalIsQuorumNotReached && !isQueued && (pendingStatuses.includes(status) || (status.includes("pending") && !isPendingExecution));
    
    console.log("🔵 [WIDGET] Status flags:", { isPendingExecution, isActive, isExecuted, isQueued, isPending, isDefeat: finalIsDefeat, isQuorumNotReached: finalIsQuorumNotReached });
    console.log("🔵 [WIDGET] Display status:", displayStatus, "(Raw from API:", exactStatus, ")");
    
    // Determine stage label and button text based on proposal type
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
      // Default fallback (shouldn't happen, but just in case)
      stageLabel = '';
      buttonText = 'View Proposal';
    }
    
    // Check if proposal is ending soon (< 24 hours)
    const isEndingSoon = proposalData.daysLeft !== null && 
                         proposalData.daysLeft !== undefined && 
                         !isNaN(proposalData.daysLeft) &&
                         proposalData.daysLeft >= 0 &&
                         (proposalData.daysLeft === 0 || (proposalData.daysLeft === 1 && proposalData.hoursLeft !== null && proposalData.hoursLeft < 24));
    
    // Determine urgency styling
    const urgencyClass = isEndingSoon ? 'ending-soon' : '';
    const urgencyStyle = isEndingSoon ? 'border: 2px solid #ef4444; background: #fef2f2;' : '';
    
    // Check if proposal has passed/ended - dim with opacity instead of changing background
    const isEnded = proposalData.daysLeft !== null && proposalData.daysLeft < 0;
    // "passed" means voting ended and proposal passed, but not executed yet (different from "executed")
    // All these statuses indicate the proposal has ended (voting is over)
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
          // Always show voting results, even if 0 (especially for PENDING status)
          // For PENDING proposals with no votes, show 0 for all
          const displayFor = totalVotes > 0 ? formatVoteAmount(votesForNum) : '0';
          const displayAgainst = totalVotes > 0 ? formatVoteAmount(votesAgainstNum) : '0';
          const displayAbstain = totalVotes > 0 ? formatVoteAmount(votesAbstainNum) : '0';
          
          // For progress bar, only show segments if there are votes
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

    // Add close button handler for this widget type
    // Remove old handlers first to prevent duplicates when updating in place
    const closeBtn = statusWidget.querySelector('.widget-close-btn');
    if (closeBtn) {
      // Clone and replace to remove all event listeners
      const newCloseBtn = closeBtn.cloneNode(true);
      closeBtn.parentNode.replaceChild(newCloseBtn, closeBtn);
      newCloseBtn.addEventListener('click', () => {
        statusWidget.style.display = 'none';
        statusWidget.remove();
      });
    }

    // Use the isMobile variable already declared at the top of the function
    console.log(`🔵 [MOBILE] Status widget detection - window.innerWidth: ${window.innerWidth}, isMobile: ${isMobile}`);
    
    if (isMobile) {
      // If updating in place, skip insertion (widget is already in DOM)
      if (isUpdatingInPlace) {
        console.log(`🔵 [MOBILE] Widget already exists, updated in place - skipping insertion to prevent flickering`);
        // Ensure widget is visible
        statusWidget.style.display = 'block';
        statusWidget.style.visibility = 'visible';
        statusWidget.style.opacity = '1';
        return; // Exit early - widget updated in place (close button handler already attached above)
      }
      
      // Mobile: Insert widgets sequentially so all are visible
      // Find existing widgets and insert after the last one, or before first post if none exist
      try {
        const allPosts = Array.from(document.querySelectorAll('.topic-post, .post, [data-post-id], article[data-post-id]'));
        const firstPost = allPosts.length > 0 ? allPosts[0] : null;
        const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream, .topic-post-stream');
        
        // Find all existing widgets on mobile (they should be before the first post)
        let lastWidget = null;
        
        // Find the last widget that's actually in the DOM and before posts
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
            // Insert after the last widget
            lastWidget.parentNode.insertBefore(statusWidget, lastWidget.nextSibling);
            console.log("✅ [MOBILE] Status widget inserted after last widget");
        } else {
            // No existing widgets, insert before first post
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
    
    // Pattern 2: Search for AIP references with proposal numbers
    // "AIP #123", "AIP 123", "proposal #123", "proposal 123"
    // Then try to construct URL from governance portal
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

  // Extract previous Snapshot stage URL from current Snapshot proposal (CASCADING SEARCH)
  // This finds Temp Check from ARFC, or ARFC from a later Snapshot proposal
  // ARFC proposals often reference the previous Temp Check: "Following the Temp Check [link]"
  // eslint-disable-next-line no-unused-vars
  function extractPreviousSnapshotStage(snapshotData) {
    if (!snapshotData) {
      return null;
    }
    
    console.log("🔍 [CASCADE] Searching for previous Snapshot stage link...");
    
    // Get all text content - prefer raw proposal body if available
    let combinedText = '';
    if (snapshotData._rawProposal && snapshotData._rawProposal.body) {
      combinedText = snapshotData._rawProposal.body || '';
      console.log("🔍 [CASCADE] Using raw proposal body for previous stage search");
    } else {
      const description = snapshotData.description || '';
      const body = snapshotData.body || '';
      combinedText = (description + ' ' + body).trim();
      console.log("🔍 [CASCADE] Using transformed description/body for previous stage search");
    }
    
    if (combinedText.length === 0) {
      console.log("⚠️ [CASCADE] No description/body text found for previous stage search");
      return null;
    }
    
    // Pattern 1: Look for explicit references to previous stages
    // "Following the Temp Check", "Previous Temp Check", "See Temp Check", "Temp Check [link]"
    const previousStagePatterns = [
      /(?:following|previous|see|after|from)\s+(?:the\s+)?(?:temp\s+check|tempcheck)[\s:]*([^\s\)]+snapshot\.org[^\s\)]+)/gi,
      /(?:temp\s+check|tempcheck)[\s:]*([^\s\)]+snapshot\.org[^\s\)]+)/gi,
      /(?:arfc|aave\s+request\s+for\s+comments)[\s:]*([^\s\)]+snapshot\.org[^\s\)]+)/gi
    ];
    
    for (const pattern of previousStagePatterns) {
      const matches = combinedText.match(pattern);
      if (matches && matches.length > 0) {
        // Extract the URL from the match
        const urlMatch = matches[0].match(SNAPSHOT_URL_REGEX);
        if (urlMatch && urlMatch.length > 0) {
          const foundUrl = urlMatch[0];
          // Prefer Aave Snapshot links
          if (foundUrl.includes('aave.eth') || foundUrl.includes('aavedao.eth')) {
            console.log(`✅ [CASCADE] Found previous Snapshot stage URL: ${foundUrl}`);
            return foundUrl;
          }
        }
      }
    }
    
    // Pattern 2: Direct Snapshot URLs in text (filter by context)
    const snapshotUrlMatches = combinedText.match(SNAPSHOT_URL_REGEX);
    if (snapshotUrlMatches && snapshotUrlMatches.length > 0) {
      // Filter for Aave Snapshot links and exclude the current proposal
      const currentUrl = snapshotData.url || '';
      const previousStageUrl = snapshotUrlMatches.find(url => {
        const isAave = url.includes('aave.eth') || url.includes('aavedao.eth');
        const isNotCurrent = !currentUrl || !url.includes(currentUrl.split('/').pop() || '');
        return isAave && isNotCurrent;
      });
      
      if (previousStageUrl) {
        console.log(`✅ [CASCADE] Found potential previous Snapshot stage URL: ${previousStageUrl}`);
        return previousStageUrl;
      }
    }
    
    console.log("❌ [CASCADE] No previous Snapshot stage link found");
    return null;
    }
    
  // Extract Snapshot URL from AIP proposal metadata/description (CASCADING SEARCH)
  // This helps find previous stages: AIP → ARFC/Temp Check
  // eslint-disable-next-line no-unused-vars
  function extractSnapshotUrlFromAIP(aipData) {
    if (!aipData) {
      return null;
    }
    
    console.log("🔍 [CASCADE] Searching for Snapshot link in AIP proposal description...");
    
    // Get all text content
    const description = aipData.description || '';
    
    if (description.length === 0) {
      console.log("⚠️ [CASCADE] No description text found in AIP proposal");
      return null;
    }
    
    console.log(`🔍 [CASCADE] Searching in ${description.length} characters of AIP proposal text`);
    
    // ENHANCED: Search for Snapshot links with multiple patterns
    // Pattern 1: Direct Snapshot URLs
    const snapshotUrlMatches = description.match(SNAPSHOT_URL_REGEX);
    if (snapshotUrlMatches && snapshotUrlMatches.length > 0) {
      // Filter for Aave Snapshot space links (preferred)
      const aaveSnapshotMatch = snapshotUrlMatches.find(url => 
        url.includes('aave.eth') || url.includes('aavedao.eth')
      );
      if (aaveSnapshotMatch) {
        console.log(`✅ [CASCADE] Found Aave Snapshot URL: ${aaveSnapshotMatch}`);
        return aaveSnapshotMatch;
      }
      // If no Aave-specific link, return first match anyway
      console.log(`✅ [CASCADE] Found Snapshot URL: ${snapshotUrlMatches[0]}`);
      return snapshotUrlMatches[0];
    }
    
    // Pattern 2: Check metadata fields
    if (aipData.metadata) {
      const metadataStr = JSON.stringify(aipData.metadata);
      const metadataMatch = metadataStr.match(SNAPSHOT_URL_REGEX);
      if (metadataMatch && metadataMatch.length > 0) {
        const aaveMetadataMatch = metadataMatch.find(url => 
          url.includes('aave.eth') || url.includes('aavedao.eth')
        );
        if (aaveMetadataMatch) {
          console.log(`✅ [CASCADE] Found Aave Snapshot URL in metadata: ${aaveMetadataMatch}`);
          return aaveMetadataMatch;
        }
        console.log(`✅ [CASCADE] Found Snapshot URL in metadata: ${metadataMatch[0]}`);
        return metadataMatch[0];
      }
    }
    
    // Pattern 3: Check for snapshotURL field directly (if AIP API includes this)
    if (aipData.snapshotURL) {
      console.log(`✅ [CASCADE] Found Snapshot URL in snapshotURL field: ${aipData.snapshotURL}`);
      return aipData.snapshotURL;
    }
    
    console.log("❌ [CASCADE] No Snapshot link found in AIP proposal description/metadata");
    return null;
  }

  // Set up separate widgets: Snapshot widget and AIP widget
  // AIP widget only shows after Snapshot proposals are concluded (not active)
  // Live vote counts (For, Against, Abstain) are shown for active Snapshot proposals
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
    
    // Check if widgets already exist and match current proposals - if so, don't clear them
    const existingWidgets = document.querySelectorAll('.tally-status-widget-container');
    const existingUrls = new Set();
    existingWidgets.forEach(widget => {
      const widgetUrl = widget.getAttribute('data-tally-url');
      if (widgetUrl) {
        existingUrls.add(widgetUrl);
      }
    });
    
    // Get all proposal URLs from current proposals
    const currentUrls = new Set([...allProposals.snapshot, ...allProposals.aip]);
    
    // Only clear widgets if the proposals have changed (different URLs)
    const urlsMatch = existingUrls.size === currentUrls.size && 
                     [...existingUrls].every(url => currentUrls.has(url)) &&
                     [...currentUrls].every(url => existingUrls.has(url));
    
    if (urlsMatch && existingWidgets.length > 0) {
      console.log(`🔵 [TOPIC] Widgets already match current proposals (${existingWidgets.length} widget(s)), skipping re-render`);
      return; // Don't re-render if widgets already match
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
    
    if (allProposals.snapshot.length === 0 && allProposals.aip.length === 0) {
      console.log("🔵 [TOPIC] No proposals found - removing widgets");
      hideWidgetIfNoProposal();
      return;
    }
    
    // Deduplicate URLs to prevent creating multiple widgets for the same proposal
    const uniqueSnapshotUrls = [...new Set(allProposals.snapshot)];
    const uniqueAipUrls = [...new Set(allProposals.aip)];
    
    if (uniqueSnapshotUrls.length !== allProposals.snapshot.length) {
      console.log(`🔵 [TOPIC] Deduplicated ${allProposals.snapshot.length} Snapshot URLs to ${uniqueSnapshotUrls.length} unique URLs`);
    }
    if (uniqueAipUrls.length !== allProposals.aip.length) {
      console.log(`🔵 [TOPIC] Deduplicated ${allProposals.aip.length} AIP URLs to ${uniqueAipUrls.length} unique URLs`);
    }
    
    const totalProposals = uniqueSnapshotUrls.length + uniqueAipUrls.length;
    console.log(`🔵 [TOPIC] Found ${totalProposals} unique proposal(s), will select max 3 based on priority`);
    
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
    // ============================================================================
    
    /**
     * Get priority score for proposal state (lower number = higher priority)
     * Priority order: active(1) > created(2) > pending(3) > executed(4) > ended(5) > failed(6)
     */
    function getStatePriority(status) {
      const normalizedStatus = (status || '').toLowerCase().trim();
      
      // Active states (highest priority)
      if (normalizedStatus === 'active' || normalizedStatus === 'open' || normalizedStatus === 'voting') {
        return 1;
      }
      
      // Created states
      if (normalizedStatus === 'created') {
        return 2;
      }
      
      // Pending states
      if (normalizedStatus === 'pending' || normalizedStatus === 'pendingexecution' || 
          normalizedStatus.includes('pending execution') || normalizedStatus === 'queued') {
        return 3;
      }
      
      // Executed states
      if (normalizedStatus === 'executed' || normalizedStatus === 'crosschainexecuted' || 
          normalizedStatus === 'completed' || normalizedStatus === 'passed') {
        return 4;
      }
      
      // Ended/Closed states
      if (normalizedStatus === 'closed' || normalizedStatus === 'ended' || normalizedStatus === 'expired') {
        return 5;
      }
      
      // Failed states (lowest priority)
      if (normalizedStatus === 'failed' || normalizedStatus === 'defeated' || 
          normalizedStatus === 'defeat' || normalizedStatus === 'rejected' ||
          normalizedStatus.includes('quorum not reached') || normalizedStatus === 'cancelled') {
        return 6;
      }
      
      // Unknown/other states - put at end
      return 7;
    }
    
    /**
     * Select top 3 proposals based on priority, with type variety consideration
     * Strategy: Prioritize by state, but try to show variety of types if possible
     */
    function selectTopProposals(proposalsList) {
      // Sort all proposals by priority (lower priority number = higher priority)
      const sorted = proposalsList.sort((a, b) => {
        const priorityA = getStatePriority(a.status);
        const priorityB = getStatePriority(b.status);
        
        // First sort by priority
        if (priorityA !== priorityB) {
          return priorityA - priorityB;
        }
        
        // If same priority, maintain original order
        return a.originalOrder - b.originalOrder;
      });
      
      // Select top 3, but try to show variety of types
      const selected = [];
      const typeCounts = { tempcheck: 0, arfc: 0, aip: 0 };
      const maxPerType = 2; // Max 2 of same type
      
      for (const proposal of sorted) {
        if (selected.length >= 3) {
          break;
        }
        
        const proposalType = proposal.stage || proposal.type || 'arfc';
        const typeKey = proposalType === 'temp-check' ? 'tempcheck' : 
                       proposalType === 'aip' ? 'aip' : 'arfc';
        
        // Check if we can add this proposal
        const canAdd = typeCounts[typeKey] < maxPerType || 
                      (selected.length < 3 && Object.values(typeCounts).every(count => count === 0));
        
        if (canAdd) {
          selected.push(proposal);
          typeCounts[typeKey]++;
        }
      }
      
      console.log(`🔵 [SELECTION] Selected ${selected.length} proposal(s) from ${allProposals.length} total:`);
      selected.forEach((p, idx) => {
        const type = p.stage || p.type || 'arfc';
        console.log(`  [${idx + 1}] ${p.title?.substring(0, 50)}... (${type}, status: ${p.status}, priority: ${getStatePriority(p.status)})`);
      });
      
      return selected;
    }
    
    /**
     * Render only the selected proposals (max 3, prioritized by state)
     */
    function renderSelectedProposals(snapshotProposals, aipProposals) {
      // Combine all proposals
      const combinedProposals = [...snapshotProposals, ...aipProposals];
      
      if (combinedProposals.length === 0) {
        console.log("🔵 [RENDER] No valid proposals to render");
        return;
      }
      
      // Select top 3 based on priority
      const selected = selectTopProposals(combinedProposals);
      
      console.log(`🔵 [RENDER] Rendering ${selected.length} selected widget(s) out of ${combinedProposals.length} total proposal(s)`);
      
      // Render each selected proposal
      selected.forEach((proposal, index) => {
        if (renderingUrls.has(proposal.url)) {
          console.log(`🔵 [RENDER] URL ${proposal.url} is already being rendered, skipping duplicate`);
          return;
        }
        
        renderingUrls.add(proposal.url);
        
        const stage = proposal.stage || proposal.type || 'arfc';
        const stageName = stage === 'temp-check' ? 'Temp Check' : 
                         stage === 'arfc' ? 'ARFC' : 
                         stage === 'aip' ? 'AIP' : 'Snapshot';
        
        console.log(`🔵 [RENDER] Creating widget ${index + 1}/${selected.length} for ${stageName} (status: ${proposal.status})`);
        console.log(`   Title: ${proposal.title?.substring(0, 60)}...`);
        console.log(`   URL: ${proposal.url}`);
        
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
        
        console.log(`✅ [RENDER] Widget ${index + 1} rendered`);
      });
    }
    
    // ===== SNAPSHOT WIDGETS - One per URL =====
    if (uniqueSnapshotUrls.length > 0) {
      // Filter out URLs that are already being fetched or rendered
      const snapshotUrlsToFetch = uniqueSnapshotUrls.filter(url => {
        if (fetchingUrls.has(url) || renderingUrls.has(url)) {
          console.log(`🔵 [TOPIC] Snapshot URL ${url} is already being fetched/rendered, skipping duplicate`);
          return false;
        }
        fetchingUrls.add(url);
        return true;
      });
      
      Promise.allSettled(snapshotUrlsToFetch.map(url => {
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
          
          // Store snapshot results for later selection (don't render yet)
          const snapshotProposals = validSnapshots.map((snapshot) => {
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
          
          // Check if we have AIP proposals to wait for
          if (uniqueAipUrls.length === 0) {
            // No AIP proposals, proceed with selection and rendering
            renderSelectedProposals(snapshotProposals, []);
          } else {
            // Store for later when AIPs are ready
            window._snapshotProposals = snapshotProposals;
          }
        })
        .catch(error => {
          console.error("❌ [TOPIC] Error processing Snapshot proposals:", error);
        });
    }
    
    // ===== AIP WIDGETS - One per URL =====
    if (uniqueAipUrls.length > 0) {
      const aipUrlsToFetch = uniqueAipUrls.filter(url => {
        if (fetchingUrls.has(url) || renderingUrls.has(url)) {
          console.log(`🔵 [TOPIC] AIP URL ${url} is already being fetched/rendered, skipping duplicate`);
          return false;
        }
        fetchingUrls.add(url);
        return true;
      });
      
      Promise.allSettled(aipUrlsToFetch.map(aipUrl => {
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
          
          // Store AIP results
          window._aipProposals = validAips.map((aip) => {
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
          
          // Now we have both snapshot and AIP proposals, proceed with selection and rendering
          renderSelectedProposals(window._snapshotProposals || [], window._aipProposals || []);
        })
        .catch(error => {
          console.error("❌ [TOPIC] Error processing AIP proposals:", error);
          // Still try to render snapshots if available
          renderSelectedProposals(window._snapshotProposals || [], []);
        });
    } else {
      // No AIP proposals, but we might have snapshots - check if they're ready
      if (uniqueSnapshotUrls.length === 0) {
        // No proposals at all
        console.log("🔵 [TOPIC] No proposals to render");
      }
      // If we have snapshots, they will be handled in the snapshot Promise.allSettled
    }
    
  }
  
  // Debounce widget setup to prevent duplicate widgets
  let widgetSetupTimeout = null;
  let isWidgetSetupRunning = false;
  
  // Track URLs currently being rendered to prevent race conditions
  const renderingUrls = new Set();
  // Track URLs currently being fetched to prevent duplicate fetches
  const fetchingUrls = new Set();
  
  function debouncedSetupTopicWidget() {
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
        });
      }
    }, 500);
  }
  
  // Watch for new posts being added to the topic and re-check for proposals
  function setupTopicWatcher() {
    // Watch for new posts being added
    const postObserver = new MutationObserver((mutations) => {
      // Ignore mutations that are only widget-related to prevent flickering
      let hasNonWidgetChanges = false;
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          // Check if the added node is a widget or inside a widget
          if (node.nodeType === Node.ELEMENT_NODE) {
            const isWidget = node.classList?.contains('tally-status-widget-container') ||
                           node.classList?.contains('governance-widgets-wrapper') ||
                           node.closest?.('.tally-status-widget-container') ||
                           node.closest?.('.governance-widgets-wrapper');
            if (!isWidget) {
              hasNonWidgetChanges = true;
              break;
            }
          }
        }
        if (hasNonWidgetChanges) {
          break;
        }
      }
      
      // Only trigger widget setup if there are actual post changes, not widget changes
      if (hasNonWidgetChanges) {
        // Use debounced version to prevent multiple rapid calls
        debouncedSetupTopicWidget();
      }
    });

    const postStream = document.querySelector('.post-stream, .topic-body, .posts-wrapper');
    if (postStream) {
      postObserver.observe(postStream, { childList: true, subtree: true });
      console.log("✅ [TOPIC] Watching for new posts in topic (ignoring widget changes)");
    }
    
    // Initial setup - use debounced version
    debouncedSetupTopicWidget();
    
    // Also check after delays to catch late-loading content (but only once)
    setTimeout(() => debouncedSetupTopicWidget(), 500);
    setTimeout(() => debouncedSetupTopicWidget(), 1500);
    
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
    setTimeout(() => {
      setupTopicWatcher();
      setupGlobalComposerDetection();
    }, 500);
  });
});


