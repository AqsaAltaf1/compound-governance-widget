// Snapshot proposal data fetching service

import { fetchWithRetry } from "./fetch-service";
import { SNAPSHOT_GRAPHQL_ENDPOINT, SNAPSHOT_TESTNET_GRAPHQL_ENDPOINT } from "../config/constants";
import { calculateTimeRemaining } from "../utils/date-utils";

/**
 * Transform Snapshot proposal data to widget format
 */
export function transformSnapshotData(proposal, space) {
  console.log("🔵 [TRANSFORM] Raw proposal data from API:", JSON.stringify(proposal, null, 2));
  
  // Determine proposal stage (Temp Check or ARFC) based on title/tags
  let stage = 'snapshot';
  const title = proposal.title || '';
  const body = proposal.body || '';
  const titleLower = title.toLowerCase();
  const bodyLower = body.toLowerCase();
  
  // Check for Temp Check (various formats)
  if (titleLower.includes('temp check') || 
      titleLower.includes('tempcheck') ||
      bodyLower.includes('temp check') || 
      bodyLower.includes('tempcheck') ||
      titleLower.includes('[temp check]') ||
      titleLower.startsWith('temp check')) {
    stage = 'temp-check';
    console.log("🔵 [TRANSFORM] Detected stage: Temp Check");
  } 
  // Check for ARFC (various formats)
  else if (titleLower.includes('arfc') || 
           bodyLower.includes('arfc') ||
           titleLower.includes('[arfc]')) {
    stage = 'arfc';
    console.log("🔵 [TRANSFORM] Detected stage: ARFC");
  } else {
    console.log("🔵 [TRANSFORM] Stage not detected, defaulting to 'snapshot'");
  }
  
  // Calculate voting results
  const choices = proposal.choices || [];
  const scores = proposal.scores || [];
  const scoresTotal = proposal.scores_total || 0;
  
  console.log("🔵 [TRANSFORM] Choices:", choices);
  console.log("🔵 [TRANSFORM] Scores:", scores);
  console.log("🔵 [TRANSFORM] Scores Total:", scoresTotal);
  
  // Snapshot can have various choice formats:
  // - "For" / "Against"
  // - "Yes" / "No"
  // - "YAE" / "NAY" (Aave format)
  // - "For" / "Against" / "Abstain"
  let forVotes = 0;
  let againstVotes = 0;
  let abstainVotes = 0;
  
  if (choices.length > 0 && scores.length > 0) {
    // Try to find "For" or "Yes" or "YAE" (various formats)
    const forIndex = choices.findIndex(c => {
      const lower = c.toLowerCase();
      return lower.includes('for') || lower.includes('yes') || lower === 'yae' || lower.includes('yae');
    });
    
    // Try to find "Against" or "No" or "NAY"
    const againstIndex = choices.findIndex(c => {
      const lower = c.toLowerCase();
      return lower.includes('against') || lower.includes('no') || lower === 'nay' || lower.includes('nay');
    });
    
    // Try to find "Abstain"
    const abstainIndex = choices.findIndex(c => {
      const lower = c.toLowerCase();
      return lower.includes('abstain');
    });
    
    console.log("🔵 [TRANSFORM] Found indices - For:", forIndex, "Against:", againstIndex, "Abstain:", abstainIndex);
    
    if (forIndex >= 0 && forIndex < scores.length) {
      forVotes = Number(scores[forIndex]) || 0;
    }
    if (againstIndex >= 0 && againstIndex < scores.length) {
      againstVotes = Number(scores[againstIndex]) || 0;
    }
    if (abstainIndex >= 0 && abstainIndex < scores.length) {
      abstainVotes = Number(scores[abstainIndex]) || 0;
    }
    
    // If we didn't find specific choices, use first two as For/Against
    if (forIndex < 0 && againstIndex < 0 && scores.length >= 2) {
      console.log("🔵 [TRANSFORM] No matching choices found, using first two scores as For/Against");
      forVotes = Number(scores[0]) || 0;
      againstVotes = Number(scores[1]) || 0;
    }
  } else if (scores.length >= 2) {
    // Fallback: assume first is For, second is Against
    console.log("🔵 [TRANSFORM] No choices array, using first two scores as For/Against");
    forVotes = Number(scores[0]) || 0;
    againstVotes = Number(scores[1]) || 0;
  }
  
  // Calculate total votes (sum of all scores if scoresTotal is 0 or missing)
  const calculatedTotal = scores.reduce((sum, score) => sum + (Number(score) || 0), 0);
  const totalVotes = scoresTotal > 0 ? scoresTotal : calculatedTotal;
  
  console.log("🔵 [TRANSFORM] Vote counts - For:", forVotes, "Against:", againstVotes, "Abstain:", abstainVotes, "Total:", totalVotes);
  
  const forPercent = totalVotes > 0 ? (forVotes / totalVotes) * 100 : 0;
  const againstPercent = totalVotes > 0 ? (againstVotes / totalVotes) * 100 : 0;
  const abstainPercent = totalVotes > 0 ? (abstainVotes / totalVotes) * 100 : 0;
  
  console.log("🔵 [TRANSFORM] Percentages - For:", forPercent, "Against:", againstPercent, "Abstain:", abstainPercent);
  
  // Calculate time remaining
  let daysLeft = null;
  let hoursLeft = null;
  const now = Date.now() / 1000; // Snapshot uses Unix timestamp in seconds
  const endTime = proposal.end || 0;
  
  if (endTime > 0) {
    const diffTime = endTime - now;
    const diffDays = diffTime / (24 * 60 * 60);
    
    if (diffDays >= 0) {
      daysLeft = Math.floor(diffDays);
      if (daysLeft === 0 && diffTime > 0) {
        hoursLeft = Math.floor(diffTime / (60 * 60));
      }
    } else {
      daysLeft = Math.ceil(diffDays); // Negative for past dates
    }
  }
  
  // Determine status
  let status = 'unknown';
  if (proposal.state === 'active' || proposal.state === 'open') {
    status = 'active';
  } else if (proposal.state === 'closed') {
    // For closed proposals, determine if it passed based on votes
    // A proposal passes if For votes > Against votes
    if (forVotes > againstVotes && totalVotes > 0) {
      status = 'passed';
    } else {
      status = 'closed';
    }
  } else if (proposal.state === 'pending') {
    status = 'pending';
  } else {
    // Fallback: use state as-is if it's a valid status
    status = proposal.state || 'unknown';
  }
  
  console.log("🔵 [TRANSFORM] Proposal state:", proposal.state, "→ Final status:", status);
  
  // Calculate support percentage (For votes / Total votes)
  const supportPercent = totalVotes > 0 ? (forVotes / totalVotes) * 100 : 0;
  
  console.log("🔵 [TRANSFORM] Final support percent:", supportPercent);
  
  return {
    id: proposal.id,
    title: proposal.title || 'Untitled Proposal',
    description: proposal.body || '', // Used for display
    body: proposal.body || '', // Preserve raw body for cascading search
    status,
    stage,
    space,
    daysLeft,
    hoursLeft,
    endTime,
    supportPercent, // Add support percentage for easy access
    voteStats: {
      for: { count: forVotes, voters: 0, percent: forPercent },
      against: { count: againstVotes, voters: 0, percent: againstPercent },
      abstain: { count: abstainVotes, voters: 0, percent: abstainPercent },
      total: totalVotes
    },
    url: `https://snapshot.org/#/${space}/${proposal.id.split('/')[1]}`,
    type: 'snapshot',
    _rawProposal: proposal // Preserve raw API response for cascading search
  };
}

/**
 * Fetch Snapshot proposal data
 * @param {string} space - Snapshot space identifier
 * @param {string} proposalId - Proposal ID
 * @param {string} cacheKey - Cache key for storing result
 * @param {boolean} isTestnet - Whether this is a testnet proposal
 * @param {Map} proposalCache - Shared cache instance
 * @param {WeakSet} handledErrors - Shared error tracking
 */
export async function fetchSnapshotProposal(space, proposalId, cacheKey, isTestnet = false, proposalCache, handledErrors) {
  const endpoint = isTestnet ? SNAPSHOT_TESTNET_GRAPHQL_ENDPOINT : SNAPSHOT_GRAPHQL_ENDPOINT;
  
  try {
    console.log("🔵 [SNAPSHOT] Fetching proposal - space:", space, "proposalId:", proposalId, "isTestnet:", isTestnet);
    console.log("🔵 [SNAPSHOT] Using endpoint:", endpoint);

    // Query by full ID
    const queryById = `
      query Proposal($id: String!) {
        proposal(id: $id) {
          id
          title
          body
          choices
          start
          end
          snapshot
          state
          author
          created
          space {
            id
            name
          }
          scores
          scores_by_strategy
          scores_total
          scores_updated
          votes
          plugins
          network
          type
          strategies {
            name
            network
            params
          }
          validation {
            name
            params
          }
          flagged
        }
      }
    `;

    // Snapshot proposal ID format: {space}/{proposal-id}
    // Try multiple formats as Snapshot API can be inconsistent
    let cleanSpace = space;
    if (space.startsWith('s:') && !isTestnet) {
      cleanSpace = space.substring(2); // Remove 's:' prefix for API (mainnet only)
    }
    let spaceWithoutPrefix = space;
    if (isTestnet && space.startsWith('s-tn:')) {
      spaceWithoutPrefix = space.substring(5); // Remove 's-tn:' prefix for testnet alternative format
    }
    
    // Generate all possible proposal ID formats
    const fullProposalId1 = `${cleanSpace}/${proposalId}`;
    const fullProposalId2 = proposalId; // Just the proposal hash (works for testnet)
    const fullProposalId3 = `${space}/${proposalId}`;
    const fullProposalId4 = isTestnet ? `${spaceWithoutPrefix}/${proposalId}` : null;
    
    // For testnet, try proposal hash first
    // For mainnet, try space/proposal format first
    const formatOrder = isTestnet 
      ? [fullProposalId2, fullProposalId1, fullProposalId3, fullProposalId4].filter(Boolean)
      : [fullProposalId1, fullProposalId2, fullProposalId3].filter(Boolean);
    
    console.log("🔵 [SNAPSHOT] Trying proposal ID formats (testnet:", isTestnet, "):");
    formatOrder.forEach((fmt, idx) => {
      console.log(`  Format ${idx + 1}:`, fmt);
    });

    // Try formats in order
    let fullProposalId = formatOrder[0];
    const requestBody = {
      query: queryById,
      variables: { id: fullProposalId }
    };
    console.log("🔵 [SNAPSHOT] Making request to:", endpoint);
    console.log("🔵 [SNAPSHOT] Request body:", JSON.stringify(requestBody, null, 2));
    
    const response = await fetchWithRetry(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(requestBody),
    }, 3, 1000, handledErrors);

    console.log("🔵 [SNAPSHOT] Response status:", response.status, response.statusText);
    console.log("🔵 [SNAPSHOT] Response ok:", response.ok);

    if (response.ok) {
      const result = await response.json();
      console.log("🔵 [SNAPSHOT] API Response:", JSON.stringify(result, null, 2));
      
      if (result.errors) {
        console.error("❌ [SNAPSHOT] GraphQL errors:", result.errors);
        return null;
      }

      const proposal = result.data?.proposal;
      if (proposal) {
        console.log("✅ [SNAPSHOT] Proposal fetched successfully with format:", formatOrder[0]);
        const transformedProposal = transformSnapshotData(proposal, space);
        transformedProposal._cachedAt = Date.now();
        proposalCache.set(cacheKey, transformedProposal);
        return transformedProposal;
      } else {
        // Try remaining formats in order
        for (let i = 1; i < formatOrder.length; i++) {
          const formatId = formatOrder[i];
          console.warn(`⚠️ [SNAPSHOT] Format ${i} failed, trying format ${i + 1}...`);
          
          const retryResponse = await fetchWithRetry(endpoint, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              query: queryById,
              variables: { id: formatId }
            }),
          }, 3, 1000, handledErrors);
          
          if (retryResponse.ok) {
            const retryResult = await retryResponse.json();
            if (retryResult.data?.proposal) {
              console.log(`✅ [SNAPSHOT] Proposal fetched with format ${i + 1}:`, formatId);
              const transformedProposal = transformSnapshotData(retryResult.data.proposal, space);
              transformedProposal._cachedAt = Date.now();
              proposalCache.set(cacheKey, transformedProposal);
              return transformedProposal;
            }
          }
        }
        
        console.error("❌ [SNAPSHOT] All proposal ID formats failed. Last response:", result.data);
      }
    } else {
      const errorText = await response.text();
      console.error("❌ [SNAPSHOT] HTTP error:", response.status, errorText);
    }
  } catch (error) {
    // Enhanced error logging with more context
    const errorMessage = error.message || error.toString();
    const errorName = error.name || 'UnknownError';
    
    console.error("❌ [SNAPSHOT] Error fetching proposal:", {
      name: errorName,
      message: errorMessage,
      url: endpoint,
      proposalId,
      isTestnet,
      fullError: error
    });
    
    // Provide specific guidance based on error type
    if (errorName === 'AbortError' || errorMessage.includes('aborted')) {
      console.error("❌ [SNAPSHOT] Request timed out after 10 seconds. The Snapshot API may be slow or unavailable.");
    } else if (errorName === 'TypeError' || errorMessage.includes('Failed to fetch')) {
      console.error("❌ [SNAPSHOT] Network error - possible causes:");
      console.error("   - CORS policy blocking the request");
      console.error("   - Network connectivity issues");
      console.error("   - Snapshot API is temporarily unavailable");
      console.error("   - Browser security restrictions");
      if (error.cause) {
        console.error("   - Original error:", error.cause);
      }
    } else if (errorMessage.includes('QUIC') || errorMessage.includes('ERR_QUIC')) {
      console.error("❌ [SNAPSHOT] Network protocol error (QUIC) - this may be a temporary issue. Please try again later.");
    } else {
      console.error("❌ [SNAPSHOT] Unexpected error occurred. Please check the console for details.");
    }
  }
  return null;
}

