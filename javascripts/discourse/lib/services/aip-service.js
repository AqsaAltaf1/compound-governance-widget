// AIP (Aave Improvement Proposal) data fetching service

import { AAVE_GOVERNANCE_PORTAL, AAVE_V3_SUBGRAPH } from "../config/constants";
import { calculateTimeRemaining } from "../utils/date-utils";
import { fetchWithRetry } from "./fetch-service";

/**
 * Get state mapping based on URL source
 * vote.onaave.com uses: 0='created', 1='voting', 2='passed', 3='failed', 4='executed', 5='expired', 6='cancelled', 7='active'
 * app.aave.com uses: 0='null', 1='created', 2='active', 3='queued', 4='executed', 5='failed', 6='cancelled', 7='expired'
 */
export function getStateMapping(urlSource) {
  if (urlSource === 'vote.onaave.com') {
    return {
      0: 'created',
      1: 'voting',
      2: 'passed',
      3: 'failed',
      4: 'executed',
      5: 'expired',
      6: 'cancelled',
      7: 'active',
    };
  } else {
    // Default to app.aave.com (Aave Governance V3) enum mapping
    return {
      0: 'null',
      1: 'created',
      2: 'active',
      3: 'queued',
      4: 'executed',
      5: 'failed',
      6: 'cancelled',
      7: 'expired',
    };
  }
}

/**
 * Parse front-matter from markdown (browser-compatible, no gray-matter needed)
 * Handles YAML front-matter in markdown files
 */
export function parseFrontMatter(text) {
  if (!text || !text.startsWith('---')) {
    return { metadata: {}, markdown: text, raw: text };
  }

  // Find the end of front-matter (second ---)
  const endIndex = text.indexOf('\n---', 4);
  if (endIndex === -1) {
    return { metadata: {}, markdown: text, raw: text };
  }

  // Extract front-matter and content
  const frontMatterText = text.substring(4, endIndex).trim();
  const markdown = text.substring(endIndex + 5).trim();

  // Simple YAML parser for basic key-value pairs
  const metadata = {};
  const lines = frontMatterText.split('\n');
  for (const line of lines) {
    const colonIndex = line.indexOf(':');
    if (colonIndex > 0) {
      const key = line.substring(0, colonIndex).trim();
      let value = line.substring(colonIndex + 1).trim();
      // Remove quotes if present
      if ((value.startsWith('"') && value.endsWith('"')) || 
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      metadata[key] = value;
    }
  }

  return { metadata, markdown, raw: text };
}

/**
 * Transform on-chain proposal data to our expected format
 * Using simplified ABI structure: (id, creator, startTime, endTime, forVotes, againstVotes, state, executed, canceled)
 */
export function transformAIPDataFromOnChain(proposal, state, proposalId, urlSource = 'app.aave.com') {
  // Get the correct state mapping based on URL source
  const stateMap = getStateMapping(urlSource);

  // Use state from parameter or from proposal object
  const proposalState = state || (proposal.state !== undefined ? Number(proposal.state) : 0);
  const status = stateMap[proposalState] || 'unknown';

  // Safely extract values from proposal object
  // The simplified ABI returns: (id, creator, startTime, endTime, forVotes, againstVotes, state, executed, canceled)
  const startTime = proposal.startTime ? Number(proposal.startTime) : null;
  const endTime = proposal.endTime ? Number(proposal.endTime) : null;
  
  // Calculate daysLeft and hoursLeft from startTime and endTime
  // startTime is the votingActivationTimestamp (when voting opens)
  // endTime is when voting ends (startTime + votingDuration)
  let daysLeft = null;
  let hoursLeft = null;
  
  if (endTime && endTime > 0) {
    // endTime is in seconds (Unix timestamp)
    const timeRemaining = calculateTimeRemaining(endTime);
    daysLeft = timeRemaining.daysLeft;
    hoursLeft = timeRemaining.hoursLeft;
    
    console.log("🔵 [AIP] Calculated dates from on-chain - Start:", startTime ? new Date(startTime * 1000).toISOString() : 'N/A', "End:", new Date(endTime * 1000).toISOString(), "Days left:", daysLeft, "Hours left:", hoursLeft);
  }
  
  return {
    id: proposalId.toString(),
    title: `Proposal ${proposalId}`, // On-chain doesn't have title, will be enriched from markdown/subgraph
    description: `Aave Governance Proposal ${proposalId}`, // On-chain doesn't have description, will be enriched
    status,
    forVotes: proposal.forVotes ? proposal.forVotes.toString() : '0',
    againstVotes: proposal.againstVotes ? proposal.againstVotes.toString() : '0',
    abstainVotes: '0', // Aave V3 doesn't have abstain votes
    quorum: null, // Would need to calculate from strategy
    proposer: proposal.creator || null,
    createdAt: startTime ? new Date(startTime * 1000).toISOString() : null,
    executedAt: proposal.executed ? (endTime ? new Date(endTime * 1000).toISOString() : null) : null,
    startTime,
    endTime,
    votingActivationTimestamp: startTime, // startTime is the voting activation timestamp
    canceled: proposal.canceled || false,
    executed: proposal.executed || false,
    daysLeft,
    hoursLeft,
  };
}

/**
 * Transform AIP proposal data to widget format
 */
export function transformAIPData(proposal) {
  // Calculate voting results
  const forVotes = parseInt(proposal.forVotes || "0", 10);
  const againstVotes = parseInt(proposal.againstVotes || "0", 10);
  const abstainVotes = parseInt(proposal.abstainVotes || "0", 10);
  const totalVotes = forVotes + againstVotes + abstainVotes;
  
  const forPercent = totalVotes > 0 ? (forVotes / totalVotes) * 100 : 0;
  const againstPercent = totalVotes > 0 ? (againstVotes / totalVotes) * 100 : 0;
  const abstainPercent = totalVotes > 0 ? (abstainVotes / totalVotes) * 100 : 0;
  
  // Use daysLeft and hoursLeft if already calculated from subgraph (with votingActivationTimestamp)
  // Otherwise, calculate from votingActivationTimestamp + votingDuration
  let daysLeft = proposal.daysLeft !== undefined ? proposal.daysLeft : null;
  let hoursLeft = proposal.hoursLeft !== undefined ? proposal.hoursLeft : null;
  
  // If dates weren't already calculated (from subgraph), try to calculate from available data
  if (daysLeft === null && proposal.votingActivationTimestamp && proposal.votingDuration) {
    // votingActivationTimestamp is in seconds (Unix timestamp)
    const activationTimestamp = Number(proposal.votingActivationTimestamp);
    const votingDuration = Number(proposal.votingDuration); // in seconds
    
    // Calculate end timestamp: activation + duration
    const endTimestamp = activationTimestamp + votingDuration;
    
    const timeRemaining = calculateTimeRemaining(endTimestamp);
    daysLeft = timeRemaining.daysLeft;
    hoursLeft = timeRemaining.hoursLeft;
    
    console.log("🔵 [AIP] Calculated dates in transformAIPData - Activation:", new Date(activationTimestamp * 1000).toISOString(), "End:", new Date(endTimestamp * 1000).toISOString(), "Days left:", daysLeft, "Hours left:", hoursLeft);
  } else if (daysLeft === null && proposal.endTime) {
    // Fallback: use endTime directly if available
    const timeRemaining = calculateTimeRemaining(Number(proposal.endTime));
    daysLeft = timeRemaining.daysLeft;
    hoursLeft = timeRemaining.hoursLeft;
  }
  
  // Determine status
  let status = 'unknown';
  if (proposal.status) {
    const statusLower = proposal.status.toLowerCase();
    if (statusLower === 'active' || statusLower === 'pending') {
      status = 'active';
    } else if (statusLower === 'executed' || statusLower === 'succeeded') {
      status = 'executed';
    } else if (statusLower === 'defeated' || statusLower === 'failed') {
      status = 'defeated';
    } else if (statusLower === 'queued') {
      status = 'queued';
    } else if (statusLower === 'canceled' || statusLower === 'cancelled') {
      status = 'canceled';
    }
  }
  
  return {
    id: proposal.id,
    title: proposal.title || 'Untitled AIP',
    description: proposal.description || '',
    status,
    stage: 'aip',
    quorum: proposal.quorum || null,
    daysLeft,
    hoursLeft,
    voteStats: {
      for: { count: forVotes, voters: 0, percent: forPercent },
      against: { count: againstVotes, voters: 0, percent: againstPercent },
      abstain: { count: abstainVotes, voters: 0, percent: abstainPercent },
      total: totalVotes
    },
    url: `${AAVE_GOVERNANCE_PORTAL}/t/${proposal.id}`,
    type: 'aip'
  };
}

/**
 * Merge on-chain data with markdown and subgraph metadata
 * Priority: markdown > subgraph > on-chain defaults
 * On-chain data is the source of truth for votes/state
 * Subgraph can provide voting data if on-chain is unavailable
 */
export function mergeProposalData(onChainData, markdownData, subgraphMetadata) {
  // Start with on-chain data (source of truth for votes/state)
  const merged = { ...onChainData };

  // Enrich with markdown (richest source for content)
  if (markdownData) {
    merged.title = markdownData.title || merged.title;
    merged.description = markdownData.description || merged.description;
    merged.markdown = markdownData.markdown;
    merged.markdownMetadata = markdownData.metadata;
    merged._contentSource = 'markdown';
  } else if (subgraphMetadata) {
    // Fallback to subgraph if no markdown
    merged.title = subgraphMetadata.title || merged.title;
    merged.description = subgraphMetadata.description || merged.description;
    merged._contentSource = 'subgraph';
    
    // If on-chain votes are missing, use subgraph votes as fallback
    if (!merged.forVotes && subgraphMetadata.forVotes) {
      merged.forVotes = subgraphMetadata.forVotes;
    }
    if (!merged.againstVotes && subgraphMetadata.againstVotes) {
      merged.againstVotes = subgraphMetadata.againstVotes;
    }
    
    // Enrich with additional subgraph data
    if (subgraphMetadata.creator && !merged.creator) {
      merged.creator = subgraphMetadata.creator;
    }
    if (subgraphMetadata.votingDuration && !merged.votingDuration) {
      merged.votingDuration = subgraphMetadata.votingDuration;
    }
    // votingActivationTimestamp comes from on-chain startTime, not subgraph
    if (subgraphMetadata.ipfsHash && !merged.ipfsHash) {
      merged.ipfsHash = subgraphMetadata.ipfsHash;
    }
  }

  // Keep on-chain data for votes/state (source of truth) if available
  if (onChainData.forVotes !== undefined) {
    merged.forVotes = onChainData.forVotes;
  }
  if (onChainData.againstVotes !== undefined) {
    merged.againstVotes = onChainData.againstVotes;
  }
  if (onChainData.status !== undefined) {
    merged.status = onChainData.status; // On-chain state is authoritative
  }
  merged._dataSource = onChainData ? 'on-chain' : (subgraphMetadata ? 'subgraph' : 'unknown');

  return merged;
}

/**
 * Transform JSON data from Aave V3 Data API to our format
 */
export function transformAIPDataFromJSON(jsonData) {
  return {
    id: jsonData.id || jsonData.proposalId || null,
    title: jsonData.title || jsonData.name || "Untitled Proposal",
    description: jsonData.description || jsonData.body || "",
    status: jsonData.status || jsonData.state || "unknown",
    forVotes: jsonData.forVotes || jsonData.for || 0,
    againstVotes: jsonData.againstVotes || jsonData.against || 0,
    abstainVotes: jsonData.abstainVotes || jsonData.abstain || 0,
    quorum: jsonData.quorum || null,
    proposer: jsonData.proposer || null,
    createdAt: jsonData.createdAt || jsonData.created || null,
    executedAt: jsonData.executedAt || jsonData.executed || null,
    startBlock: jsonData.startBlock || null,
    endBlock: jsonData.endBlock || null,
  };
}

/**
 * Fetch proposal markdown from vote.onaave.com
 * This provides rich content: title, description, full markdown body
 * Returns markdown with front-matter parsed
 */
export async function fetchAIPMarkdown(proposalId, handledErrors, aaveVoteSite) {
  try {
    if (!aaveVoteSite) {
      console.debug("🔵 [AIP] AAVE_VOTE_SITE not configured, skipping markdown fetch");
      return null;
    }
    
    const apiUrl = `${aaveVoteSite}?proposalId=${proposalId}`;
    const response = await fetchWithRetry(apiUrl, {
      method: "GET",
      headers: {
        "Content-Type": "text/plain",
      },
    }, 3, 1000, handledErrors);

    if (response.ok) {
      const text = await response.text();
      const parsed = parseFrontMatter(text);
      
      return {
        title: parsed.metadata.title || parsed.metadata.name || null,
        description: parsed.metadata.description || parsed.markdown.substring(0, 200) || null,
        markdown: parsed.markdown,
        metadata: parsed.metadata,
        raw: parsed.raw
      };
    }
    return null;
  } catch (error) {
    console.debug("🔵 [AIP] Markdown fetch error:", error.message);
    return null;
  }
}

/**
 * Fetch Aave proposal from The Graph API (method from ava.mjs)
 */
export async function fetchAIPFromSubgraph(proposalId, handledErrors) {
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

/**
 * Fetch AIP proposal data directly from Ethereum blockchain (source of truth)
 * This is the most reliable method - no CORS, no backend, will never randomly break
 */
export async function fetchAIPFromOnChain(topicId, urlSource, ensureEthersLoaded, ethRpcUrl, aaveGovernanceV3Address, aaveGovernanceV3Abi) {
  try {
    // Ensure ethers.js is loaded
    const ethers = await ensureEthersLoaded();
    if (!ethers) {
      console.error("❌ [AIP] ethers.js not available - on-chain fetch disabled");
      console.error("❌ [AIP] This is the PRIMARY method - ethers.js must be loaded!");
      return null;
    }

    if (!ethRpcUrl || !aaveGovernanceV3Address || !aaveGovernanceV3Abi) {
      console.error("❌ [AIP] On-chain configuration missing - RPC URL, contract address, or ABI not provided");
      return null;
    }

    // Parse proposal ID (should be a number)
    // Handle both string and number inputs, extract numeric part if needed
    let proposalId;
    if (typeof topicId === 'string') {
      // Extract numeric part from string (e.g., "420" or "proposal-420")
      const numericMatch = topicId.match(/\d+/);
      if (numericMatch) {
        proposalId = parseInt(numericMatch[0], 10);
      } else {
        proposalId = parseInt(topicId, 10);
      }
    } else {
      proposalId = parseInt(topicId, 10);
    }
    
    if (isNaN(proposalId) || proposalId <= 0) {
      console.debug("🔵 [AIP] Invalid proposal ID for on-chain fetch:", topicId);
      return null;
    }

    // Create provider and contract
    const provider = new ethers.providers.JsonRpcProvider(ethRpcUrl);
    const governanceContract = new ethers.Contract(
      aaveGovernanceV3Address,
      aaveGovernanceV3Abi,
      provider
    );

    // Fetch proposal data using simplified ABI
    let proposal;
    let state = 0;
    
    try {
      // Call getProposal with simplified return structure
      proposal = await governanceContract.getProposal(proposalId);
      
      // Check if proposal exists (id should match proposalId)
      if (!proposal || !proposal.id || proposal.id.toString() !== proposalId.toString()) {
        console.debug("🔵 [AIP] Proposal does not exist on-chain:", proposalId);
        return null;
      }
      
      // Get proposal state
      try {
        state = await governanceContract.getProposalState(proposalId);
      } catch {
        // Use state from proposal if available, otherwise default to 0
        state = proposal.state || 0;
        console.debug("🔵 [AIP] Using state from proposal data");
      }
    } catch (error) {
      // Enhanced error logging - on-chain is PRIMARY, so log errors clearly
      console.error("❌ [AIP] Error fetching proposal from chain:", error.message);
      if (error.message?.includes("ABI decoding")) {
        console.error("❌ [AIP] ABI decoding error - contract address or ABI may be incorrect");
        console.error("❌ [AIP] Contract:", aaveGovernanceV3Address);
      }
      if (error.message?.includes("network") || error.message?.includes("timeout")) {
        console.error("❌ [AIP] RPC connection error - check ETH_RPC_URL:", ethRpcUrl);
      }
      return null;
    }

    // Transform on-chain data to our format (use URL source for correct state mapping)
    return transformAIPDataFromOnChain(proposal, state, proposalId, urlSource);
  } catch (error) {
    console.error("❌ [AIP] On-chain fetch error (outer catch):", error.message);
    console.error("❌ [AIP] This is the PRIMARY method - errors should be investigated");
    return null;
  }
}

/**
 * Fetch AIP proposal data
 * Main entry point - tries subgraph first, then on-chain as fallback
 */
export async function fetchAIPProposal(proposalId, cacheKey, urlSource, proposalCache, handledErrors, ensureEthersLoaded, config = {}) {
  try {
    console.log("🔵 [AIP] Fetching proposal from The Graph API - proposalId:", proposalId, "URL Source:", urlSource);
    
    const result = await fetchAIPFromSubgraph(proposalId, handledErrors);
    if (result) {
      console.log("✅ [AIP] Successfully fetched from The Graph API");
      result._cachedAt = Date.now();
      result.chain = 'thegraph';
      result.urlSource = urlSource; // Store URL source for state mapping
      proposalCache.set(cacheKey, result);
      return result;
    }
    
    // Try on-chain fetch as fallback
    const onChainResult = await fetchAIPFromOnChain(
      proposalId, 
      urlSource, 
      ensureEthersLoaded,
      config.ethRpcUrl,
      config.aaveGovernanceV3Address,
      config.aaveGovernanceV3Abi
    );
    if (onChainResult) {
      console.log("✅ [AIP] Successfully fetched from on-chain");
      onChainResult._cachedAt = Date.now();
      onChainResult.chain = 'onchain';
      onChainResult.urlSource = urlSource; // Store URL source for state mapping
      proposalCache.set(cacheKey, onChainResult);
      return onChainResult;
    }
    
    console.warn("⚠️ [AIP] Failed to fetch proposal from The Graph API and on-chain");
    return null;
  } catch (error) {
    console.error("❌ [AIP] Error fetching proposal:", error);
    return null;
  }
}

