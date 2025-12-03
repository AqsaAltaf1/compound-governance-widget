import { apiInitializer } from "discourse/lib/api";

console.log("✅ Arbitrium Tally Widget: JavaScript file loaded!");

export default apiInitializer((api) => {
  console.log("✅ Arbitrium Tally Widget: apiInitializer called!");

  // Tally API Configuration
  const TALLY_API_KEY = "afc402378b98d62f181eb36471e49c3705766c5d6a3bf4018d55c400e9b97a07";
  const TALLY_GRAPHQL_ENDPOINT = "https://api.tally.xyz/query";
  const TALLY_URL_REGEX = /https?:\/\/(?:www\.)?tally\.(?:xyz|so)\/[^\s<>"']+/gi;
  const proposalCache = new Map();

  function truncate(text, maxLength) {
    if (!text || text.length <= maxLength) return text;
    return text.substring(0, maxLength) + "...";
  }

  // Helper to escape HTML for safe insertion
  function escapeHtml(unsafe) {
    if (!unsafe) return '';
    return String(unsafe)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function extractProposalInfo(url) {
    console.log("🔍 Extracting proposal info from URL:", url);

    let urlProposalNumber = null;
    let govId = null;
    let internalId = null;
    let isInternalId = false;

    // Format 1: tally.xyz/gov/{org}/proposal/{urlNumber}?govId={govId}
    // Example: https://tally.xyz/gov/compound/proposal/511?govId=eip155:1:0x309a862bbC1A00e45506cB8A802D1ff10004c8C0
    const xyzMatch = url.match(/tally\.xyz\/gov\/[^\/]+\/proposal\/([0-9]+)/i);
    if (xyzMatch) {
      urlProposalNumber = xyzMatch[1];
      try {
        const urlObj = new URL(url);
        govId = urlObj.searchParams.get('govId');
        console.log("✅ Extracted tally.xyz format:", { urlProposalNumber, govId });
      } catch (e) {
        console.warn("❌ Could not parse URL for govId:", e);
      }
      return { urlProposalNumber, govId, internalId, isInternalId: false };
    }

    // Format 2: tally.so/r/{internalId}
    // Note: These URLs may not exist, but we can try to use the ID for API
    const soMatch = url.match(/tally\.so\/r\/([a-zA-Z0-9]+)/i);
    if (soMatch) {
      internalId = soMatch[1];
      console.log("✅ Extracted tally.so format (internal ID):", internalId);
      return { urlProposalNumber, govId, internalId, isInternalId: true };
    }

    console.warn("❌ Could not extract proposal info from URL:", url);
    return null;
  }

  // Fetch proposal using governorId + onchainId (same approach as Node.js script)
  async function fetchProposalByOnchainId(governorId, onchainId, cacheKey) {
    try {
      console.log("🔵 [API] Fetching proposal - governorId:", governorId, "onchainId:", onchainId);

      // Use the same query structure as the working Node.js script
      const query = `
        query Proposal($input: ProposalInput!) {
          proposal(input: $input) {
            id
            onchainId
            chainId
            status
            quorum
            end {
              ... on Block {
                timestamp
                ts
              }
              ... on BlocklessTimestamp {
                timestamp
              }
            }
            metadata {
              title
              description
              discourseURL
              snapshotURL
            }
            voteStats {
              type
              votesCount
              votersCount
              percent
            }
            proposer {
              id
              address
              name
            }
          }
        }
      `;

      const variables = {
        input: {
          governorId: governorId,
          onchainId: onchainId,
          includeArchived: false,
          isLatest: true
        }
      };

      const response = await fetch(TALLY_GRAPHQL_ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Api-Key": TALLY_API_KEY,
        },
        body: JSON.stringify({
          query: query,
          variables: variables
        }),
      });

      if (response.ok) {
        const result = await response.json();
        if (result.errors) {
          console.error("❌ [API] GraphQL errors:", result.errors);
          return null;
        }

        const proposal = result.data?.proposal;
        if (proposal) {
          console.log("✅ [API] Proposal fetched successfully");
          console.log("🔵 [API] Raw status from Tally API:", proposal.status);
          console.log("🔵 [API] Full proposal data:", JSON.stringify(proposal, null, 2));
          const transformedProposal = transformProposalData(proposal);
          transformedProposal._cachedAt = Date.now(); // Add timestamp for cache expiration
          proposalCache.set(cacheKey, transformedProposal);
          return transformedProposal;
        } else {
          console.warn("⚠️ [API] No proposal data in response");
        }
      } else {
        const errorText = await response.text();
        console.error("❌ [API] HTTP error:", response.status, errorText);
      }
    } catch (error) {
      console.error("❌ [API] Error fetching proposal:", error);
    }
    return null;
  }

  // Fallback: Fetch by internal ID if we have it (for tally.so/r/ URLs)
  async function fetchProposalByInternalId(internalId, cacheKey) {
    try {
      console.log("🔵 [API] Fetching proposal by internal ID:", internalId);

      const query = `
        query Proposal($input: ProposalInput!) {
          proposal(input: $input) {
            id
            onchainId
            chainId
            status
            quorum
            end {
              ... on Block {
                timestamp
                ts
              }
              ... on BlocklessTimestamp {
                timestamp
              }
            }
            metadata {
              title
              description
              discourseURL
              snapshotURL
            }
            voteStats {
              type
              votesCount
              votersCount
              percent
            }
            proposer {
              id
              address
              name
            }
          }
        }
      `;

      const variables = {
        input: {
          id: internalId
        }
      };

      const response = await fetch(TALLY_GRAPHQL_ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Api-Key": TALLY_API_KEY,
        },
        body: JSON.stringify({
          query: query,
          variables: variables
        }),
      });

      if (response.ok) {
        const result = await response.json();
        if (result.errors) {
          console.error("❌ [API] GraphQL errors:", result.errors);
          return null;
        }

        const proposal = result.data?.proposal;
        if (proposal) {
          console.log("✅ [API] Proposal fetched successfully:", proposal);
          const transformedProposal = transformProposalData(proposal);
          transformedProposal._cachedAt = Date.now(); // Add timestamp for cache expiration
          proposalCache.set(cacheKey, transformedProposal);
          return transformedProposal;
        }
      }
    } catch (error) {
      console.error("❌ [API] Error fetching proposal by internal ID:", error);
    }
    return null;
  }

  // Resolve URL proposal number to internal ID by matching onchainId
  async function resolveProposalId(urlProposalNumber, govId) {
    try {
      console.log("🔵 [RESOLVE] Resolving proposal ID - URL number:", urlProposalNumber, "govId:", govId);

      // Query proposals and match by onchainId (which equals the URL proposal number)
      const query = `
        query Proposals($input: ProposalsInput!) {
          proposals(input: $input) {
            nodes {
              ... on Proposal {
                id
                onchainId
                metadata {
                  title
                }
              }
            }
          }
        }
      `;

      // Try querying with governor filter
      let variables = {
        input: {
          governorIds: [govId]
        }
      };

      console.log("🔵 [RESOLVE] GraphQL query variables:", JSON.stringify(variables, null, 2));

      let response = await fetch(TALLY_GRAPHQL_ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Api-Key": TALLY_API_KEY,
        },
        body: JSON.stringify({
          query: query,
          variables: variables,
        }),
      });

      // If that fails, try without governor filter
      if (!response.ok) {
        console.log("🔵 [RESOLVE] First query failed, trying without governor filter");
        variables = { input: {} };
        response = await fetch(TALLY_GRAPHQL_ENDPOINT, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Api-Key": TALLY_API_KEY,
          },
          body: JSON.stringify({
            query: query,
            variables: variables,
          }),
        });
      }

      console.log("🔵 [RESOLVE] API response status:", response.status, response.statusText);

      if (response.ok) {
        const result = await response.json();
        
        if (result.errors) {
          console.error("❌ [RESOLVE] GraphQL errors:", result.errors);
          return null;
        }

        const proposals = result.data?.proposals?.nodes || [];
        console.log("🔵 [RESOLVE] Found", proposals.length, "proposals");

        if (proposals.length === 0) {
          console.warn("⚠️ [RESOLVE] No proposals found");
          return null;
        }

        // Match by onchainId (which equals the URL proposal number)
        const urlNumber = urlProposalNumber.toString();
        const matchedProposal = proposals.find(p => p.onchainId === urlNumber);
        
        if (matchedProposal && matchedProposal.id) {
          console.log("✅ [RESOLVE] Found internal ID:", matchedProposal.id, "for onchainId:", urlNumber);
          return matchedProposal.id;
        }

        console.warn("⚠️ [RESOLVE] Could not find proposal with onchainId:", urlNumber);
      } else {
        const errorText = await response.text();
        console.error("❌ [RESOLVE] API error response:", response.status, errorText);
      }
    } catch (error) {
      console.error("❌ [RESOLVE] Error resolving proposal ID:", error);
    }
    return null;
  }

  async function fetchProposalData(proposalId, originalUrl, govId, urlProposalNumber, forceRefresh = false) {
    const cacheKey = originalUrl || proposalId;
    
    // Check cache, but allow force refresh to bypass it
    if (!forceRefresh && proposalCache.has(cacheKey)) {
      const cachedData = proposalCache.get(cacheKey);
      const cacheAge = Date.now() - (cachedData._cachedAt || 0);
      // Use cache if less than 5 minutes old, otherwise refresh
      if (cacheAge < 5 * 60 * 1000) {
        console.log("🔵 [CACHE] Returning cached data (age:", Math.round(cacheAge / 1000), "seconds)");
        return cachedData;
      } else {
        console.log("🔵 [CACHE] Cache expired, fetching fresh data");
        proposalCache.delete(cacheKey);
      }
    }

    // Priority 1: Use governorId + onchainId (for tally.xyz URLs) - same approach as Node.js script
    if (govId && urlProposalNumber) {
      console.log("🔵 [API] Fetching using governorId + onchainId");
      const onchainId = parseInt(urlProposalNumber, 10);
      const result = await fetchProposalByOnchainId(govId, onchainId, cacheKey);
      if (result && result.title && result.title !== "Tally Proposal") {
        console.log("✅ [API] Successfully fetched using governorId + onchainId");
        return result;
      } else {
        console.warn("⚠️ [API] Failed to fetch using governorId + onchainId");
      }
    }

    // Priority 2: Use internal ID (for tally.so/r/ URLs)
    if (proposalId) {
      console.log("🔵 [API] Fetching via GraphQL API using internal ID:", proposalId);
      const result = await fetchProposalByInternalId(proposalId, cacheKey);
      if (result && result.title && result.title !== "Tally Proposal") {
        console.log("✅ [API] Successfully fetched from GraphQL API");
        return result;
      } else {
        console.warn("⚠️ [API] GraphQL API returned no data or invalid data");
      }
    }

    // Fallback: Return basic structure with URL if API fails
    console.log("⚠️ [FALLBACK] Using fallback data structure");
    return {
      id: proposalId,
      title: "Tally Proposal",
      status: "unknown",
      voteStats: {
        for: { count: 0, voters: 0, percent: 0 },
        against: { count: 0, voters: 0, percent: 0 },
        abstain: { count: 0, voters: 0, percent: 0 },
        total: 0
      },
      url: originalUrl
    };
  }

  // HTML parsing function removed - using GraphQL API only

  function transformProposalData(proposal) {
    const voteStats = proposal.voteStats || [];
    const forVotes = voteStats.find(v => v.type === "for") || {};
    const againstVotes = voteStats.find(v => v.type === "against") || {};
    const abstainVotes = voteStats.find(v => v.type === "abstain") || {};

    const votesForCount = parseInt(forVotes.votesCount || "0", 10);
    const votesAgainstCount = parseInt(againstVotes.votesCount || "0", 10);
    const votesAbstainCount = parseInt(abstainVotes.votesCount || "0", 10);

    // Calculate days left from end timestamp
    let daysLeft = null;
    let hoursLeft = null;
    if (proposal.end) {
      console.log("🔵 [DAYS] Proposal end data:", proposal.end);
      
      // Try multiple ways to get the end timestamp
      let endTimestamp = null;
      let timestampMs = null;
      
      // Try direct timestamp properties (could be ISO string or number)
      if (proposal.end.timestamp !== undefined && proposal.end.timestamp !== null) {
        const tsValue = proposal.end.timestamp;
        if (typeof tsValue === 'string') {
          // ISO date string like "2025-12-01T14:18:23Z"
          const parsed = Date.parse(tsValue);
          if (!isNaN(parsed) && isFinite(parsed)) {
            timestampMs = parsed;
            console.log("🔵 [DAYS] Successfully parsed timestamp string:", tsValue, "->", parsed);
          } else {
            // Try using new Date() as fallback
            const dateObj = new Date(tsValue);
            if (!isNaN(dateObj.getTime())) {
              timestampMs = dateObj.getTime();
              console.log("🔵 [DAYS] Successfully parsed using new Date():", tsValue, "->", timestampMs);
            } else {
              console.warn("⚠️ [DAYS] Failed to parse timestamp string:", tsValue);
            }
          }
        } else if (typeof tsValue === 'number') {
          endTimestamp = tsValue;
        }
      } else if (proposal.end.ts !== undefined && proposal.end.ts !== null) {
        const tsValue = proposal.end.ts;
        if (typeof tsValue === 'string') {
          // ISO date string
          const parsed = Date.parse(tsValue);
          if (!isNaN(parsed) && isFinite(parsed)) {
            timestampMs = parsed;
            console.log("🔵 [DAYS] Successfully parsed ts string:", tsValue, "->", parsed);
          } else {
            // Try using new Date() as fallback
            const dateObj = new Date(tsValue);
            if (!isNaN(dateObj.getTime())) {
              timestampMs = dateObj.getTime();
              console.log("🔵 [DAYS] Successfully parsed ts using new Date():", tsValue, "->", timestampMs);
            } else {
              console.warn("⚠️ [DAYS] Failed to parse ts string:", tsValue);
            }
          }
        } else if (typeof tsValue === 'number') {
          endTimestamp = tsValue;
        }
      } else if (typeof proposal.end === 'number') {
        // If end is directly a number
        endTimestamp = proposal.end;
      } else if (typeof proposal.end === 'string') {
        // If end is a date string, try to parse it
        const parsed = Date.parse(proposal.end);
        if (!isNaN(parsed)) {
          timestampMs = parsed;
        }
      }
      
      // If we have a numeric timestamp, convert to milliseconds
      if (endTimestamp !== null && endTimestamp !== undefined && !isNaN(endTimestamp)) {
        // Handle both seconds (timestamp) and milliseconds (ts) formats
        // If timestamp is less than year 2000 in milliseconds, assume it's in seconds
        timestampMs = endTimestamp > 946684800000 ? endTimestamp : endTimestamp * 1000;
      }
      
      console.log("🔵 [DAYS] End timestamp value:", proposal.end.timestamp || proposal.end.ts, "Type:", typeof (proposal.end.timestamp || proposal.end.ts));
      console.log("🔵 [DAYS] Parsed timestamp in ms:", timestampMs);
      
      if (timestampMs !== null && timestampMs !== undefined && !isNaN(timestampMs) && isFinite(timestampMs)) {
        const endDate = new Date(timestampMs);
        console.log("🔵 [DAYS] Created date object:", endDate, "Is valid:", !isNaN(endDate.getTime()));
        
        // Validate the date
        if (isNaN(endDate.getTime())) {
          console.warn("⚠️ [DAYS] Invalid date created from timestamp:", timestampMs);
          // Set to null to indicate date parsing failed (date unknown)
          daysLeft = null;
        } else {
        const now = new Date();
        const diffTime = endDate - now;
          const diffTimeInDays = diffTime / (1000 * 60 * 60 * 24);
          
          // Use Math.floor for positive values (remaining full days)
          // Use Math.ceil for negative values (past dates)
          // This ensures we show accurate remaining time
          let diffDays;
          if (diffTimeInDays >= 0) {
            // Future date: use floor to show remaining full days
            diffDays = Math.floor(diffTimeInDays);
      } else {
            // Past date: use ceil (which will be negative or 0)
            diffDays = Math.ceil(diffTimeInDays);
          }
          
          // Validate that diffDays is a valid number
          if (isNaN(diffDays) || !isFinite(diffDays)) {
            console.warn("⚠️ [DAYS] Calculated diffDays is NaN or invalid:", diffTime, diffDays);
            daysLeft = null; // Use null to indicate calculation error (date unknown)
          } else {
            daysLeft = diffDays; // Can be negative (past), 0 (today), or positive (future)
            
            // If it ends today (daysLeft === 0), calculate hours left
            if (diffDays === 0 && diffTime > 0) {
              const diffTimeInHours = diffTime / (1000 * 60 * 60);
              hoursLeft = Math.floor(diffTimeInHours);
              console.log("🔵 [DAYS] Ends today - hours left:", hoursLeft, "Diff time (hours):", diffTimeInHours);
            }
            
            console.log("🔵 [DAYS] End date:", endDate.toISOString(), "Now:", now.toISOString());
            console.log("🔵 [DAYS] Diff time (ms):", diffTime, "Diff time (days):", diffTimeInDays, "Diff days (rounded):", diffDays, "Days left:", daysLeft, "Hours left:", hoursLeft);
          }
        }
      } else {
        console.warn("⚠️ [DAYS] No valid timestamp found in end data. End data structure:", proposal.end);
        // Keep as null if we can't parse (date unknown)
        daysLeft = null;
      }
    } else {
      console.warn("⚠️ [DAYS] No end data in proposal");
      // Keep as null if no end data at all
    }

    // Ensure daysLeft is never NaN
    const finalDaysLeft = (daysLeft !== null && daysLeft !== undefined && !isNaN(daysLeft)) ? daysLeft : null;
    console.log("🔵 [DAYS] Final daysLeft value:", finalDaysLeft, "Original:", daysLeft);

    return {
      id: proposal.id,
      onchainId: proposal.onchainId,
      chainId: proposal.chainId,
      title: proposal.metadata?.title || "Untitled Proposal",
      description: proposal.metadata?.description || "",
      status: proposal.status || "unknown",
      quorum: proposal.quorum || null,
      daysLeft: finalDaysLeft,
      hoursLeft: hoursLeft,
      proposer: {
        id: proposal.proposer?.id || null,
        address: proposal.proposer?.address || null,
        name: proposal.proposer?.name || null
      },
      discourseURL: proposal.metadata?.discourseURL || null,
      snapshotURL: proposal.metadata?.snapshotURL || null,
      voteStats: {
        for: {
          count: votesForCount,
          voters: forVotes.votersCount || 0,
          percent: forVotes.percent || 0
        },
        against: {
          count: votesAgainstCount,
          voters: againstVotes.votersCount || 0,
          percent: againstVotes.percent || 0
        },
        abstain: {
          count: votesAbstainCount,
          voters: abstainVotes.votersCount || 0,
          percent: abstainVotes.percent || 0
        },
        total: votesForCount + votesAgainstCount + votesAbstainCount
      }
    };
  }

  function formatVoteAmount(amount) {
    if (!amount || amount === 0) return "0";
    
    // Convert from wei (18 decimals) to tokens - Tally uses wei format
    // Always assume amounts are in wei if they're very large
    let tokens = amount;
    if (amount >= 1000000000000000) {
      // Convert from wei to tokens (divide by 10^18)
      tokens = amount / 1000000000000000000;
    }
    
    // Format like Tally: 1.14M, 0.03, 51.74K, etc.
    if (tokens >= 1000000) {
      const millions = tokens / 1000000;
      // Remove trailing zeros: 1.14M not 1.14M
      return parseFloat(millions.toFixed(2)) + "M";
    }
    if (tokens >= 1000) {
      const thousands = tokens / 1000;
      // Remove trailing zeros: 51.74K not 51.74K
      return parseFloat(thousands.toFixed(2)) + "K";
    }
    // For numbers less than 1000, show 2 decimal places, remove trailing zeros
    const formatted = parseFloat(tokens.toFixed(2));
    return formatted.toString();
  }

  function renderProposalWidget(container, proposalData, originalUrl) {
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
    const displayTitle = proposalData.title || "Tally Proposal";
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
                Vote on Tally
              </a>
            </div>
          ` : `
            <a href="${originalUrl}" target="_blank" rel="noopener" class="vote-button">
              View on Tally
            </a>
          `}
        </div>
      </div>
    `;
  }

  // Render status widget on the right side (outside post box) - like the image
  function renderStatusWidget(proposalData, originalUrl, widgetId, proposalInfo = null) {
    const statusWidgetId = `tally-status-widget-${widgetId}`;
    
    // Removed scroll-based check - we show the first proposal found, regardless of scroll position
    
    // Remove ALL existing widgets first to prevent duplicates
    const allWidgets = document.querySelectorAll('.tally-status-widget-container');
    allWidgets.forEach(widget => {
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
    });
    
    console.log("🔵 [WIDGET] Removed all existing widgets before creating new one");
    
    // Store proposal info for auto-refresh
    if (proposalInfo) {
      window[`tallyWidget_${widgetId}`] = {
        proposalInfo: proposalInfo,
        originalUrl: originalUrl,
        widgetId: widgetId,
        lastUpdate: Date.now()
      };
    }

    const statusWidget = document.createElement("div");
    statusWidget.id = statusWidgetId;
    statusWidget.className = "tally-status-widget-container";
    statusWidget.setAttribute("data-tally-status-id", widgetId);
    statusWidget.setAttribute("data-tally-url", originalUrl);

    // Get exact status from API FIRST (before any processing)
    // Preserve the exact status text from Tally (e.g., "Quorum not reached", "Defeat", etc.)
    const rawStatus = proposalData.status || 'unknown';
    const exactStatus = rawStatus; // Keep original case - don't uppercase, preserve exact text
    const status = rawStatus.toLowerCase().trim();
    
    console.log("🔵 [WIDGET] ========== STATUS DETECTION ==========");
    console.log("🔵 [WIDGET] Raw status from API (EXACT):", JSON.stringify(rawStatus));
    console.log("🔵 [WIDGET] Status length:", rawStatus.length);
    console.log("🔵 [WIDGET] Status char codes:", Array.from(rawStatus).map(c => c.charCodeAt(0)));
    console.log("🔵 [WIDGET] Normalized status (for logic):", JSON.stringify(status));
    console.log("🔵 [WIDGET] Display status (EXACT from Tally):", JSON.stringify(exactStatus));

    // Status detection - check in order of specificity
    // Preserve exact status text from Tally (e.g., "Quorum not reached", "Defeat", etc.)
    // Only use status flags for CSS class determination, not for display text
    const activeStatuses = ["active", "open"];
    const executedStatuses = ["executed", "crosschainexecuted", "completed"];
    const queuedStatuses = ["queued", "queuing"];
    const pendingStatuses = ["pending"];
    const defeatStatuses = ["defeat", "defeated", "rejected"];
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
    
    // Determine display status (match Tally website behavior)
    let displayStatus = exactStatus;
    if (isPendingExecution && status === "queued") {
      displayStatus = "Pending execution";
      console.log("🔵 [WIDGET] Overriding status: 'queued' → 'Pending execution' (proposal passed, like Tally website)");
    } else if (finalIsQuorumNotReached && !isQuorumNotReached) {
      displayStatus = "Quorum not reached";
      console.log("🔵 [WIDGET] Overriding status: 'defeated' → 'Quorum not reached' (quorum not met, like Tally website)");
    } else if (finalIsDefeat && quorumReached) {
      displayStatus = "Defeated";
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
    
    statusWidget.innerHTML = `
      <div class="tally-status-widget">
        <div class="status-badges-row">
          <div class="status-badge ${isPendingExecution ? 'pending' : isActive ? 'active' : isExecuted ? 'executed' : isQueued ? 'queued' : isPending ? 'pending' : finalIsDefeat ? 'defeated' : finalIsQuorumNotReached ? 'quorum-not-reached' : 'inactive'}">
            ${displayStatus}
          </div>
          ${(() => {
            if (proposalData.daysLeft !== null && proposalData.daysLeft !== undefined && !isNaN(proposalData.daysLeft)) {
              let displayText = '';
              if (proposalData.daysLeft < 0) {
                displayText = 'Ended';
              } else if (proposalData.daysLeft === 0 && proposalData.hoursLeft !== null) {
                displayText = proposalData.hoursLeft + ' ' + (proposalData.hoursLeft === 1 ? 'hour' : 'hours') + ' left';
              } else if (proposalData.daysLeft === 0) {
                displayText = 'Ends today';
              } else {
                displayText = proposalData.daysLeft + ' ' + (proposalData.daysLeft === 1 ? 'day' : 'days') + ' left';
              }
              return `<div class="days-left-badge">${displayText}</div>`;
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
        <a href="${originalUrl}" target="_blank" rel="noopener" class="vote-button">
          Vote on Tally
        </a>
      </div>
    `;

    // Position widget next to timeline scroll indicator
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
      console.log("✅ [POST] Status widget positioned below timeline scroll indicator");
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
      console.log("✅ [POST] Status widget rendered on right side (timeline not found)");
    }
  }

  // Track which proposal is currently visible and update widget on scroll
  let currentVisibleProposal = null;
  let scrollUpdateTimeout = null;

  // Get current post number from Discourse timeline (e.g., "3/5" -> 3)
  function getCurrentPostNumber() {
    // Try to find Discourse timeline numbers (e.g., "3/5")
    const timelineContainer = document.querySelector('.topic-timeline-container, .timeline-container, .topic-timeline');
    if (timelineContainer) {
      // Look for numbers like "3/5" in the timeline
      const text = timelineContainer.textContent || '';
      const match = text.match(/(\d+)\/(\d+)/);
      if (match) {
        const currentPost = parseInt(match[1], 10);
        const totalPosts = parseInt(match[2], 10);
        console.log("🔵 [SCROLL] Timeline shows:", currentPost, "/", totalPosts);
        return { current: currentPost, total: totalPosts };
      }
    }
    
    // Fallback: try to find post numbers in other elements
    const allElements = document.querySelectorAll('*');
    for (const elem of allElements) {
      const text = elem.textContent || '';
      const match = text.match(/^(\d+)\/(\d+)$/);
      if (match && elem.offsetWidth < 100 && elem.offsetHeight < 100) {
        // Likely a small number indicator
        const currentPost = parseInt(match[1], 10);
        const totalPosts = parseInt(match[2], 10);
        return { current: currentPost, total: totalPosts };
      }
    }
    
    return null;
  }

  // Find the FIRST Tally proposal URL in the entire topic (any post)
  function findFirstTallyProposalInTopic() {
    console.log("🔍 [TOPIC] Searching for first Tally proposal in topic...");
    
    // Find all posts in the topic
    const allPosts = Array.from(document.querySelectorAll('.topic-post, .post, [data-post-id]'));
    console.log("🔍 [TOPIC] Found", allPosts.length, "posts to search");
    
    // Search through posts in order (first post first)
    for (let i = 0; i < allPosts.length; i++) {
      const post = allPosts[i];
      
      // Find Tally link in this post
      const tallyLink = post.querySelector('a[href*="tally.xyz"], a[href*="tally.so"]');
      if (tallyLink) {
        const url = tallyLink.href;
        console.log("✅ [TOPIC] Found first Tally proposal in post", i + 1, ":", url);
        return url;
      }
    }
    
    console.log("⚠️ [TOPIC] No Tally proposal found in any post");
    return null;
  }

  // Hide widget if no Tally proposal is visible
  function hideWidgetIfNoProposal() {
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
    if (widgetCount > 0) {
      console.log("🔵 [WIDGET] Removed", widgetCount, "widget(s) - no proposal in current post");
    }
    // Reset current visible proposal
    currentVisibleProposal = null;
  }

  // Show widget
  function showWidget() {
    const allWidgets = document.querySelectorAll('.tally-status-widget-container');
    allWidgets.forEach(widget => {
      widget.style.display = '';
      widget.style.visibility = '';
    });
  }

  // Set up widget for the first Tally proposal found in the topic
  // This replaces scroll tracking - we show ONE widget for the FIRST proposal found
  function setupTopicWidget() {
    console.log("🔵 [TOPIC] Setting up widget for first proposal in topic...");
    
    // If widget already exists and is showing the correct proposal, don't recreate
    const existingWidget = document.querySelector('.tally-status-widget-container');
    if (existingWidget && currentVisibleProposal) {
      const widgetUrl = existingWidget.getAttribute('data-tally-url');
      if (widgetUrl === currentVisibleProposal) {
        console.log("✅ [TOPIC] Widget already showing correct proposal, skipping");
        return;
      }
    }
    
    // Find the first Tally proposal in the topic
    const proposalUrl = findFirstTallyProposalInTopic();
    
    if (!proposalUrl) {
      // No proposal found - remove any existing widgets
      console.log("🔵 [TOPIC] No proposal found - removing widgets");
      hideWidgetIfNoProposal();
      return;
    }
    
    // If this is the same proposal we're already showing, don't recreate
    if (proposalUrl === currentVisibleProposal) {
      console.log("✅ [TOPIC] Widget already showing this proposal:", proposalUrl);
      return;
    }
    
    // Extract proposal info
    const proposalInfo = extractProposalInfo(proposalUrl);
    if (!proposalInfo) {
      console.warn("⚠️ [TOPIC] Could not extract proposal info from URL:", proposalUrl);
      hideWidgetIfNoProposal();
      return;
    }
    
    // Create widget ID
    let widgetId = proposalInfo.internalId || proposalInfo.urlProposalNumber;
    if (!widgetId) {
      const urlHash = proposalUrl.split('').reduce((acc, char) => {
        return ((acc << 5) - acc) + char.charCodeAt(0);
      }, 0);
      widgetId = `proposal_${Math.abs(urlHash)}`;
    }
    
    // Set current proposal
    currentVisibleProposal = proposalUrl;
    
    console.log("🔵 [TOPIC] Fetching data for proposal:", proposalUrl);
    
    // Fetch and display proposal data
    const proposalId = proposalInfo.isInternalId ? proposalInfo.internalId : null;
    fetchProposalData(proposalId, proposalUrl, proposalInfo.govId, proposalInfo.urlProposalNumber)
      .then(data => {
        if (data && data.title && data.title !== "Tally Proposal") {
          console.log("✅ [TOPIC] Rendering widget for:", data.title);
          renderStatusWidget(data, proposalUrl, widgetId, proposalInfo);
          showWidget();
          setupAutoRefresh(widgetId, proposalInfo, proposalUrl);
        } else {
          console.warn("⚠️ [TOPIC] Invalid proposal data - hiding widget");
          hideWidgetIfNoProposal();
        }
      })
      .catch(error => {
        console.error("❌ [TOPIC] Error fetching proposal data:", error);
        hideWidgetIfNoProposal();
      });
  }
  
  // Watch for new posts being added to the topic and re-check for proposals
  function setupTopicWatcher() {
    // Watch for new posts being added
    const postObserver = new MutationObserver(() => {
      // If we don't have a widget yet, check again for proposals
      if (!currentVisibleProposal) {
        console.log("🔵 [TOPIC] New posts detected, checking for proposals...");
        setupTopicWidget();
      }
    });

    const postStream = document.querySelector('.post-stream, .topic-body, .posts-wrapper');
    if (postStream) {
      postObserver.observe(postStream, { childList: true, subtree: true });
      console.log("✅ [TOPIC] Watching for new posts in topic");
    }
    
    // Initial setup
    setupTopicWidget();
    
    // Also check after delays to catch late-loading content
    setTimeout(setupTopicWidget, 500);
    setTimeout(setupTopicWidget, 1000);
    setTimeout(setupTopicWidget, 2000);
    
    console.log("✅ [TOPIC] Topic widget setup complete");
  }

  // OLD SCROLL TRACKING - REMOVED
  function updateWidgetForVisibleProposal_OLD() {
    // Clear any pending updates
    if (scrollUpdateTimeout) {
      clearTimeout(scrollUpdateTimeout);
    }

    // Debounce scroll updates
    scrollUpdateTimeout = setTimeout(() => {
      // First, try to get current post number from Discourse timeline
      const postInfo = getCurrentPostNumber();
      
      if (postInfo) {
        // Get the proposal URL for this post number
        const proposalUrl = getProposalLinkFromPostNumber(postInfo.current);
        
        // Always check if current post has a proposal - remove widgets if not
        if (!proposalUrl) {
          // No Tally proposal in this post - remove all widgets immediately
          console.log("🔵 [SCROLL] Post", postInfo.current, "/", postInfo.total, "has no Tally proposal - removing all widgets");
          hideWidgetIfNoProposal();
          return;
        }
        
        // If we have a proposal URL and it's different from current, update widget
        if (proposalUrl && proposalUrl !== currentVisibleProposal) {
          currentVisibleProposal = proposalUrl;
          
          console.log("🔵 [SCROLL] Post", postInfo.current, "/", postInfo.total, "- Proposal URL:", proposalUrl);
          
          // Extract proposal info
          const proposalInfo = extractProposalInfo(proposalUrl);
          if (proposalInfo) {
            // Create widget ID
            let widgetId = proposalInfo.internalId || proposalInfo.urlProposalNumber;
            if (!widgetId) {
              const urlHash = proposalUrl.split('').reduce((acc, char) => {
                return ((acc << 5) - acc) + char.charCodeAt(0);
              }, 0);
              widgetId = `proposal_${Math.abs(urlHash)}`;
            }
            
            // Fetch and display proposal data
            const proposalId = proposalInfo.isInternalId ? proposalInfo.internalId : null;
            fetchProposalData(proposalId, proposalUrl, proposalInfo.govId, proposalInfo.urlProposalNumber)
              .then(data => {
                if (data && data.title && data.title !== "Tally Proposal") {
                  console.log("🔵 [SCROLL] Updating widget for post", postInfo.current, "-", data.title);
                  renderStatusWidget(data, proposalUrl, widgetId, proposalInfo);
                  showWidget(); // Make sure widget is visible
                  setupAutoRefresh(widgetId, proposalInfo, proposalUrl);
                } else {
                  // Invalid data - hide widget
                  console.log("🔵 [SCROLL] Invalid proposal data - hiding widget");
                  hideWidgetIfNoProposal();
                }
              })
              .catch(error => {
                console.error("❌ [SCROLL] Error fetching proposal data:", error);
                hideWidgetIfNoProposal();
              });
          } else {
            // Could not extract proposal info - hide widget
            console.log("🔵 [SCROLL] Could not extract proposal info - hiding widget");
            hideWidgetIfNoProposal();
          }
          return; // Exit early if we found post number
        } else if (proposalUrl === currentVisibleProposal) {
          // Same proposal - widget should already be showing, just ensure it's visible
          showWidget();
          return;
        }
      } else {
        // No post info from timeline - check fallback but hide widget if no proposal found
        console.log("🔵 [SCROLL] No post info from timeline - checking fallback");
      }
      
      // Fallback: Find the link that's most visible in viewport (original logic)
      const allTallyLinks = document.querySelectorAll('a[href*="tally.xyz"], a[href*="tally.so"]');
      
      // If no Tally links found at all, hide widget
      if (allTallyLinks.length === 0) {
        console.log("🔵 [SCROLL] No Tally links found on page - hiding widget");
        hideWidgetIfNoProposal();
        currentVisibleProposal = null;
        return;
      }
      
      let mostVisibleLink = null;
      let maxVisibility = 0;

      allTallyLinks.forEach(link => {
        const rect = link.getBoundingClientRect();
        const viewportHeight = window.innerHeight;
        
        const linkTop = Math.max(0, rect.top);
        const linkBottom = Math.min(viewportHeight, rect.bottom);
        const visibleHeight = Math.max(0, linkBottom - linkTop);
        
        const postElement = link.closest('.topic-post, .post, [data-post-id]');
        if (postElement) {
          const postRect = postElement.getBoundingClientRect();
          const postTop = Math.max(0, postRect.top);
          const postBottom = Math.min(viewportHeight, postRect.bottom);
          const postVisibleHeight = Math.max(0, postBottom - postTop);
          
          if (postVisibleHeight > maxVisibility && visibleHeight > 0) {
            maxVisibility = postVisibleHeight;
            mostVisibleLink = link;
          }
        }
      });

      // If we found a visible proposal link, update the widget
      if (mostVisibleLink && mostVisibleLink.href !== currentVisibleProposal) {
        const url = mostVisibleLink.href;
        currentVisibleProposal = url;
        
        console.log("🔵 [SCROLL] New proposal visible (fallback):", url);
        
        const proposalInfo = extractProposalInfo(url);
        if (proposalInfo) {
          let widgetId = proposalInfo.internalId || proposalInfo.urlProposalNumber;
          if (!widgetId) {
            const urlHash = url.split('').reduce((acc, char) => {
              return ((acc << 5) - acc) + char.charCodeAt(0);
            }, 0);
            widgetId = `proposal_${Math.abs(urlHash)}`;
          }
          
          const proposalId = proposalInfo.isInternalId ? proposalInfo.internalId : null;
          fetchProposalData(proposalId, url, proposalInfo.govId, proposalInfo.urlProposalNumber)
            .then(data => {
              if (data && data.title && data.title !== "Tally Proposal") {
                console.log("🔵 [SCROLL] Updating widget for visible proposal:", data.title);
                renderStatusWidget(data, url, widgetId, proposalInfo);
                showWidget(); // Make sure widget is visible
                setupAutoRefresh(widgetId, proposalInfo, url);
              } else {
                // Invalid data - hide widget
                hideWidgetIfNoProposal();
              }
            })
            .catch(error => {
              console.error("❌ [SCROLL] Error fetching proposal data:", error);
              hideWidgetIfNoProposal();
            });
        } else {
          // Could not extract proposal info - hide widget
          hideWidgetIfNoProposal();
        }
      } else if (!mostVisibleLink) {
        // No visible proposal link found - remove all widgets
        console.log("🔵 [SCROLL] No visible proposal link found - removing all widgets");
        hideWidgetIfNoProposal();
      }
    }, 150); // Debounce scroll events
  }

  // Set up scroll listener to update widget when different proposal becomes visible
  function setupScrollTracking() {
    // Use Intersection Observer for better performance
    const observerOptions = {
      root: null,
      rootMargin: '-20% 0px -20% 0px', // Trigger when post is in middle 60% of viewport
      threshold: [0, 0.25, 0.5, 0.75, 1]
    };

    const observer = new IntersectionObserver((entries) => {
      // Find the entry with highest intersection ratio
      let mostVisible = null;
      let maxRatio = 0;

      entries.forEach(entry => {
        if (entry.intersectionRatio > maxRatio) {
          maxRatio = entry.intersectionRatio;
          mostVisible = entry;
        }
      });

      if (mostVisible && mostVisible.isIntersecting) {
        // First, try to get current post number from Discourse timeline
        const postInfo = getCurrentPostNumber();
        
        let proposalUrl = null;
        
        if (postInfo) {
          // Use the post number from timeline to get the correct proposal
          proposalUrl = getProposalLinkFromPostNumber(postInfo.current);
          console.log("🔵 [SCROLL] IntersectionObserver - Post", postInfo.current, "/", postInfo.total);
          
          // If no proposal in this post, remove all widgets
          if (!proposalUrl) {
            console.log("🔵 [SCROLL] Post", postInfo.current, "/", postInfo.total, "has no Tally proposal - removing all widgets");
            hideWidgetIfNoProposal();
            return;
          }
        }
        
        // Fallback: Find Tally link in this post
        if (!proposalUrl) {
          const postElement = mostVisible.target;
          const tallyLink = postElement.querySelector('a[href*="tally.xyz"], a[href*="tally.so"]');
          if (tallyLink) {
            proposalUrl = tallyLink.href;
          } else {
            // No Tally link in this post - hide widget
            hideWidgetIfNoProposal();
            currentVisibleProposal = null;
            return;
          }
        }
        
        if (proposalUrl && proposalUrl !== currentVisibleProposal) {
          currentVisibleProposal = proposalUrl;
          
          console.log("🔵 [SCROLL] New proposal visible via IntersectionObserver:", proposalUrl);
          
          const proposalInfo = extractProposalInfo(proposalUrl);
          if (proposalInfo) {
            let widgetId = proposalInfo.internalId || proposalInfo.urlProposalNumber;
            if (!widgetId) {
              const urlHash = proposalUrl.split('').reduce((acc, char) => {
                return ((acc << 5) - acc) + char.charCodeAt(0);
              }, 0);
              widgetId = `proposal_${Math.abs(urlHash)}`;
            }
            
            const proposalId = proposalInfo.isInternalId ? proposalInfo.internalId : null;
            fetchProposalData(proposalId, proposalUrl, proposalInfo.govId, proposalInfo.urlProposalNumber)
              .then(data => {
                if (data && data.title && data.title !== "Tally Proposal") {
                  console.log("🔵 [SCROLL] Updating widget for visible proposal:", data.title);
                  renderStatusWidget(data, proposalUrl, widgetId, proposalInfo);
                  showWidget(); // Make sure widget is visible
                  setupAutoRefresh(widgetId, proposalInfo, proposalUrl);
                } else {
                  // Invalid data - hide widget
                  hideWidgetIfNoProposal();
                }
              })
              .catch(error => {
                console.error("❌ [SCROLL] Error fetching proposal data:", error);
                hideWidgetIfNoProposal();
              });
          } else {
            // Could not extract proposal info - hide widget
            hideWidgetIfNoProposal();
          }
        } else {
          // No proposal URL found - remove all widgets
          console.log("🔵 [SCROLL] No proposal URL found - removing all widgets");
          hideWidgetIfNoProposal();
        }
      }
    }, observerOptions);

    // Observe all posts
    const observePosts = () => {
      const posts = document.querySelectorAll('.topic-post, .post, [data-post-id]');
      posts.forEach(post => {
        observer.observe(post);
      });
    };

    // Initial observation
    observePosts();

    // Also observe new posts as they're added
    const postObserver = new MutationObserver(() => {
      observePosts();
    });

    const postStream = document.querySelector('.post-stream, .topic-body');
    if (postStream) {
      postObserver.observe(postStream, { childList: true, subtree: true });
    }

    // Fallback: also use scroll event for posts not yet observed
    window.addEventListener('scroll', updateWidgetForVisibleProposal, { passive: true });
    
      // Initial check: remove all widgets by default, then show only if current post has proposal
      const initialCheck = () => {
        // First, remove all widgets by default
        hideWidgetIfNoProposal();
        
        const postInfo = getCurrentPostNumber();
        if (postInfo) {
          const proposalUrl = getProposalLinkFromPostNumber(postInfo.current);
          if (!proposalUrl) {
            console.log("🔵 [INIT] Initial post", postInfo.current, "/", postInfo.total, "has no Tally proposal - all widgets removed");
            // Widgets already removed above
          } else {
            console.log("🔵 [INIT] Initial post", postInfo.current, "/", postInfo.total, "has proposal - showing widget");
            // Trigger update to show widget for current post
            updateWidgetForVisibleProposal();
          }
        } else {
          // No post info - check if any visible post has proposal
          console.log("🔵 [INIT] No post info from timeline, checking visible posts");
          updateWidgetForVisibleProposal();
        }
      };
      
      // Run immediately
      initialCheck();
      
      // Also run after delays to catch late-loading content
      setTimeout(initialCheck, 500);
      setTimeout(initialCheck, 1000);
      setTimeout(initialCheck, 2000);
    
    console.log("✅ [SCROLL] Scroll tracking set up for widget updates");
  }

  // Auto-refresh widget when Tally data changes
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
      
      if (freshData && freshData.title && freshData.title !== "Tally Proposal") {
        // Update widget with fresh data (status, votes, days left)
        console.log("🔄 [REFRESH] Updating widget with fresh data from Tally");
        renderStatusWidget(freshData, url, widgetId, proposalInfo);
      }
    }, 2 * 60 * 1000); // Refresh every 2 minutes
    
    console.log("✅ [REFRESH] Auto-refresh set up for widget:", widgetId, "(every 2 minutes)");
  }

  // Handle posts (saved content) - Show simple link preview (not full widget)
  api.decorateCookedElement((element) => {
    const text = element.textContent || element.innerHTML || '';
    const matches = Array.from(text.matchAll(TALLY_URL_REGEX));
    if (matches.length === 0) {
      console.log("🔵 [POST] No Tally URLs found in post");
      return;
    }

    console.log("🔵 [POST] Found", matches.length, "Tally URL(s) in saved post");

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

      // Find URL element (link or onebox) - try multiple methods
      let urlElement = null;
      
      // Method 1: Find by href
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
      
      // Method 2: Find onebox
      if (!urlElement) {
        const oneboxes = element.querySelectorAll('.onebox, .onebox-body');
        for (const onebox of oneboxes) {
          if (onebox.textContent && onebox.textContent.includes(url)) {
            urlElement = onebox;
            console.log("✅ [POST] Found URL in onebox");
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
      
      // Insert preview immediately (before fetch completes)
      if (urlElement && urlElement.parentNode) {
        console.log("✅ [POST] Replacing URL element with preview");
        urlElement.parentNode.replaceChild(previewContainer, urlElement);
      } else {
        console.log("✅ [POST] Appending preview to post (URL element not found)");
        element.appendChild(previewContainer);
      }
      
      // Fetch and show preview (title + description + link)
      const proposalId = proposalInfo.isInternalId ? proposalInfo.internalId : null;
      console.log("🔵 [POST] Fetching proposal data for URL:", url, "ID:", proposalId, "govId:", proposalInfo.govId, "urlNumber:", proposalInfo.urlProposalNumber);
      
      fetchProposalData(proposalId, url, proposalInfo.govId, proposalInfo.urlProposalNumber)
        .then(data => {
          console.log("✅ [POST] Proposal data received - Title:", data?.title, "Has description:", !!data?.description, "Description length:", data?.description?.length || 0);
          
          // Ensure consistent rendering for all posts
          if (data && data.title && data.title !== "Tally Proposal") {
            const title = (data.title || 'Tally Proposal').trim();
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
                  <strong>Tally Proposal</strong>
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
                <strong>Tally Proposal</strong>
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
        console.log("🔵 [COMPOSER] Checking text for Tally URLs:", text.substring(0, 100));
        const matches = Array.from(text.matchAll(TALLY_URL_REGEX));
        if (matches.length === 0) {
          // Remove widgets if no URLs
          document.querySelectorAll('[data-composer-widget-id]').forEach(w => w.remove());
          return;
        }
        
        console.log("✅ [COMPOSER] Found", matches.length, "Tally URL(s) in composer");

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
          if (!proposalInfo) continue;

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
          if (existingWidget) continue;

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
              if (data && data.title && data.title !== "Tally Proposal") {
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
          // Retry after a short delay
          setTimeout(setupListeners, 200);
        }
      };

      // Start checking for URLs periodically (more frequent for better detection)
      const intervalId = setInterval(checkForUrls, 500);
      
      // Set up event listeners when textarea is ready
      setupListeners();
      
      // Also observe DOM changes for composer
      const composerObserver = new MutationObserver(() => {
        setupListeners();
        checkForUrls();
      });
      
      const composerContainer = document.querySelector('.composer-popup, .composer-container, .d-editor-container');
      if (composerContainer) {
        composerObserver.observe(composerContainer, { childList: true, subtree: true });
      }
      
      // Cleanup on destroy
      this.element.addEventListener('willDestroyElement', () => {
        clearInterval(intervalId);
        composerObserver.disconnect();
      }, { once: true });
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
        
        if (!composerContainer) return false;
        
        // Check if composer is open (not closed/hidden)
        const isClosed = composerContainer.classList.contains('closed') || 
                        composerContainer.classList.contains('hidden') ||
                        composerContainer.style.display === 'none' ||
                        window.getComputedStyle(composerContainer).display === 'none';
        
        if (isClosed) return false;
        
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
        const matches = Array.from(text.matchAll(TALLY_URL_REGEX));
        
        if (matches.length > 0) {
          console.log("✅ [GLOBAL COMPOSER] Found Tally URL in textarea:", matches.length, "URL(s)");
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
              if (!proposalInfo) continue;

              let widgetId = proposalInfo.internalId || proposalInfo.urlProposalNumber;
              if (!widgetId) {
                const urlHash = url.split('').reduce((acc, char) => {
                  return ((acc << 5) - acc) + char.charCodeAt(0);
                }, 0);
                widgetId = `proposal_${Math.abs(urlHash)}`;
              }
              
              const existingWidget = composerWrapper.querySelector(`[data-composer-widget-id="${widgetId}"]`);
              if (existingWidget) continue;

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
                  if (data && data.title && data.title !== "Tally Proposal") {
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
        
        if (!isVisible) return;
        
        const text = textarea.value || textarea.textContent || textarea.innerText || '';
        const matches = Array.from(text.matchAll(TALLY_URL_REGEX));
        
        if (matches.length > 0) {
          // Check if we already have a widget for this textarea
          const composer = textarea.closest('.d-editor-container, .composer-popup, .composer-container, #reply-control, [class*="composer"]') || textarea.parentElement;
          if (composer) {
            const existingWidget = composer.querySelector('[data-composer-widget-id]');
            if (existingWidget) return; // Already has widget
            
            console.log("✅ [AGGRESSIVE CHECK] Found Tally URL in visible textarea, creating widget");
            // Trigger the main check which will create the widget
            checkAllComposers();
          }
        }
      });
    };
    
    // Check periodically and on DOM changes
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

