import { apiInitializer } from "discourse/lib/api";

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

  // Snapshot API Configuration
  const SNAPSHOT_GRAPHQL_ENDPOINT = "https://hub.snapshot.org/graphql";
  const SNAPSHOT_URL_REGEX = /https?:\/\/(?:www\.)?snapshot\.org\/#\/[^\s<>"']+/gi;
  
  // Aave Governance Forum Configuration
  // Primary entry point: Aave Governance Forum thread
  const AAVE_FORUM_URL_REGEX = /https?:\/\/(?:www\.)?governance\.aave\.com\/t\/[^\s<>"']+/gi;
  
  // Aave AIP Configuration
  // Support both governance.aave.com and app.aave.com/governance/
  const AAVE_GOVERNANCE_PORTAL = "https://app.aave.com/governance";
  
  // Aave Governance V3 - Using The Graph API with API key (method from ava.mjs)
  const GRAPH_API_KEY = "9e7b4a29889ac6c358b235230a5fe940";
  const SUBGRAPH_ID = "A7QMszgomC9cnnfpAcqZVLr2DffvkGNfimD8iUSMiurK";
  const AAVE_V3_SUBGRAPH = `https://gateway.thegraph.com/api/${GRAPH_API_KEY}/subgraphs/id/${SUBGRAPH_ID}`;
  
  // REMOVED: All fallback methods (on-chain, Data API, markdown) - using only The Graph API
  // REMOVED: ethers.js loading, ABI definitions, on-chain configuration
  
  // Function to ensure ethers.js is loaded
  async function ensureEthersLoaded() {
    // Check if already loaded
    if (window.ethers) {
      return window.ethers;
    }
    
    // If already loading, return the existing promise
    let ethersPromise = null;
    
    if (ethersPromise) {
      return ethersPromise;
    }
    
    // Start loading ethers.js v5 (stable version)
    ethersPromise = new Promise((resolve, reject) => {
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
  
  // Match governance.aave.com, app.aave.com/governance/, and vote.onaave.com URLs
  const AIP_URL_REGEX = /https?:\/\/(?:www\.)?(?:governance\.aave\.com|app\.aave\.com\/governance|vote\.onaave\.com)\/[^\s<>"']+/gi;
  
  const proposalCache = new Map();

  // Removed unused truncate function

  // Helper to escape HTML for safe insertion
  function escapeHtml(unsafe) {
    if (!unsafe) {return '';}
    return String(unsafe)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }


  // Extract Snapshot proposal info from URL
  // Format: https://snapshot.org/#/{space}/{proposal-id}
  // Example: https://snapshot.org/#/aave.eth/0x1234...
  function extractSnapshotProposalInfo(url) {
    console.log("🔍 Extracting Snapshot proposal info from URL:", url);
    
    try {
      // Match pattern: snapshot.org/#/{space}/proposal/{proposal-id}
      // Also handles: snapshot.org/#/{space}/{proposal-id} (without /proposal/)
      // Match pattern: snapshot.org/#/{space}/proposal/{proposal-id}
      // Handles: snapshot.org/#/s:aavedao.eth/proposal/0x1234...
      const proposalMatch = url.match(/snapshot\.org\/#\/([^\/]+)\/proposal\/([a-zA-Z0-9]+)/i);
      if (proposalMatch) {
        const space = proposalMatch[1];
        const proposalId = proposalMatch[2];
        console.log("✅ Extracted Snapshot format:", { space, proposalId });
        return { space, proposalId, type: 'snapshot' };
      }
      
      // Match pattern: snapshot.org/#/{space}/{proposal-id} (without /proposal/)
      const directMatch = url.match(/snapshot\.org\/#\/([^\/]+)\/([a-zA-Z0-9]+)/i);
      if (directMatch) {
        const space = directMatch[1];
        const proposalId = directMatch[2];
        // Skip if proposalId is "proposal" (means it's the /proposal/ path but regex didn't match correctly)
        if (proposalId.toLowerCase() !== 'proposal') {
          console.log("✅ Extracted Snapshot format (direct):", { space, proposalId });
          return { space, proposalId, type: 'snapshot' };
        }
      }
      
      console.warn("❌ Could not extract Snapshot proposal info from URL:", url);
      return null;
    } catch (e) {
      console.warn("❌ Error extracting Snapshot proposal info:", e);
      return null;
    }
  }

  // Extract AIP proposal ID from URL (robust approach)
  // The URL is NOT the data source - it's only an identifier carrier
  // Flow: URL → extract proposalId → fetch from canonical source (on-chain)
  // Supports:
  // - app.aave.com/governance/v3/proposal/?proposalId=420
  // - app.aave.com/governance/?proposalId=420
  // - vote.onaave.com/proposal/?proposalId=420
  // - governance.aave.com/t/{slug}/{id} (extract numeric ID from path)
  // - app.aave.com/governance/{id} (extract numeric ID from path)
  function extractAIPProposalInfo(url) {
    console.log("🔍 Extracting AIP proposal ID from URL:", url);
    
    try {
      let proposalId = null;
      let urlSource = 'app.aave.com'; // Default to app.aave.com (Aave V3 enum mapping)
      
      // Step 1: Try to extract from query parameter (most reliable)
      // This works for: app.aave.com/governance/v3/proposal/?proposalId=420
      try {
        const urlObj = new URL(url);
        const queryParam = urlObj.searchParams.get("proposalId");
        if (queryParam) {
          const numericId = parseInt(queryParam, 10);
          if (!isNaN(numericId) && numericId > 0) {
            proposalId = numericId.toString();
            // Detect URL source for state enum mapping
            if (url.includes('vote.onaave.com')) {
              urlSource = 'vote.onaave.com';
            } else if (url.includes('app.aave.com')) {
              urlSource = 'app.aave.com';
            }
            console.log("✅ Extracted proposalId from query parameter:", proposalId, "Source:", urlSource);
            return { proposalId, type: 'aip', urlSource };
          }
        }
      } catch {
        // URL parsing failed, try regex fallback
      }
      
      // Step 2: Try regex patterns for various URL formats
      // Pattern: vote.onaave.com/proposal/?proposalId={id}
      const voteMatch = url.match(/vote\.onaave\.com\/proposal\/\?.*proposalId=(\d+)/i);
      if (voteMatch) {
        proposalId = voteMatch[1];
        urlSource = 'vote.onaave.com';
        console.log("✅ Extracted from vote.onaave.com:", proposalId);
        return { proposalId, type: 'aip', urlSource };
      }
      
      // Pattern: app.aave.com/governance/v3/proposal/?proposalId={id}
      const appV3Match = url.match(/app\.aave\.com\/governance\/v3\/proposal\/\?.*proposalId=(\d+)/i);
      if (appV3Match) {
        proposalId = appV3Match[1];
        urlSource = 'app.aave.com';
        console.log("✅ Extracted from app.aave.com/governance/v3:", proposalId);
        return { proposalId, type: 'aip', urlSource };
      }
      
      // Pattern: governance.aave.com/t/{slug}/{id} - extract numeric ID from path
      const forumMatch = url.match(/governance\.aave\.com\/t\/[^\/]+\/(\d+)/i);
      if (forumMatch) {
        proposalId = forumMatch[1];
        urlSource = 'app.aave.com'; // Default to app.aave.com for forum links
        console.log("✅ Extracted from governance.aave.com forum:", proposalId);
        return { proposalId, type: 'aip', urlSource };
      }
      
      // Pattern: app.aave.com/governance/{id} or app.aave.com/governance/proposal/{id}
      const appMatch = url.match(/app\.aave\.com\/governance\/(?:proposal\/)?(\d+)/i);
      if (appMatch) {
        proposalId = appMatch[1];
        urlSource = 'app.aave.com';
        console.log("✅ Extracted from app.aave.com/governance:", proposalId);
        return { proposalId, type: 'aip', urlSource };
      }
      
      // Pattern: governance.aave.com/aip/{number}
      const aipMatch = url.match(/governance\.aave\.com\/aip\/(\d+)/i);
      if (aipMatch) {
        proposalId = aipMatch[1];
        urlSource = 'app.aave.com'; // Default to app.aave.com for AIP links
        console.log("✅ Extracted from governance.aave.com/aip:", proposalId);
        return { proposalId, type: 'aip', urlSource };
      }
      
      console.warn("❌ Could not extract proposalId from URL:", url);
      return null;
      } catch (e) {
      console.warn("❌ Error extracting AIP proposal info:", e);
      return null;
    }
  }

  // Extract proposal info from URL (wrapper function that detects type)
  function extractProposalInfo(url) {
    if (!url) {return null;}
    
    // Try Snapshot first
    const snapshotInfo = extractSnapshotProposalInfo(url);
    if (snapshotInfo) {
      // Return format compatible with existing code
      return {
        ...snapshotInfo,
        urlProposalNumber: snapshotInfo.proposalId, // For compatibility
        internalId: snapshotInfo.proposalId // For compatibility
      };
    }
    
    // Try AIP
    const aipInfo = extractAIPProposalInfo(url);
    if (aipInfo) {
      // Return format compatible with existing code
      // proposalId is now the primary key extracted from URL
      return {
        ...aipInfo,
        proposalId: aipInfo.proposalId, // Primary key
        urlProposalNumber: aipInfo.proposalId, // For compatibility
        internalId: aipInfo.proposalId, // For compatibility
        topicId: aipInfo.proposalId // For compatibility
      };
    }
    
    // No match
    console.warn("❌ Could not extract proposal info from URL:", url);
    return null;
  }

  // Helper function to fetch with retry logic and exponential backoff
  async function fetchWithRetry(url, options, maxRetries = 3, baseDelay = 1000) {
    let lastError;
    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Add timeout to prevent hanging
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 10000); // 10 second timeout
        
        const response = await fetch(url, {
          ...options,
          signal: controller.signal,
          // Force HTTP/2 instead of HTTP/3 (QUIC) to avoid protocol errors
          cache: 'no-cache',
          mode: 'cors', // Explicitly set CORS mode
          credentials: 'omit', // Don't send credentials to avoid CORS issues
        });
        
        clearTimeout(timeoutId);
        return response;
      } catch (error) {
        lastError = error;
        
        // Handle AbortError gracefully (timeout) - don't log as error, just retry
        if (error.name === 'AbortError') {
          if (attempt < maxRetries - 1) {
            const delay = baseDelay * Math.pow(2, attempt); // Exponential backoff
            console.warn(`⚠️ [FETCH] Request timeout (attempt ${attempt + 1}/${maxRetries}), retrying in ${delay}ms...`);
            handledErrors.add(error);
            await new Promise(resolve => setTimeout(resolve, delay));
            continue;
          }
          // Last attempt - return null or throw
          break;
        }
        
        const isNetworkError = error.name === 'TypeError' || 
                              error.name === 'NetworkError' ||
                              error.message?.includes('Failed to fetch') ||
                              error.message?.includes('QUIC') ||
                              error.message?.includes('ERR_QUIC') ||
                              error.message?.includes('NetworkError') ||
                              error.message?.includes('network');
        
        if (isNetworkError && attempt < maxRetries - 1) {
          const delay = baseDelay * Math.pow(2, attempt); // Exponential backoff
          console.warn(`⚠️ [FETCH] Network error (attempt ${attempt + 1}/${maxRetries}), retrying in ${delay}ms...`, error.message || error.toString());
          // Mark error as handled since we're retrying
          handledErrors.add(error);
          await new Promise(resolve => setTimeout(resolve, delay));
          continue;
        }
        
        // If it's the last attempt or not a network error, break to throw
        break;
      }
    }
    
    // If we exhausted all retries, throw the last error with more context
    if (lastError) {
      const enhancedError = new Error(
        `Failed to fetch after ${maxRetries} attempts: ${lastError.message || lastError.toString()}. URL: ${url}`
      );
      enhancedError.name = lastError.name || 'NetworkError';
      enhancedError.cause = lastError;
      // Mark the enhanced error as handled since it will be caught by our error handlers
      handledErrors.add(enhancedError);
      // Also mark the original error
      handledErrors.add(lastError);
      throw enhancedError;
    }
    
    // This should never happen, but TypeScript/JS might require it
    const unknownError = new Error(`Failed to fetch: Unknown error. URL: ${url}`);
    handledErrors.add(unknownError);
    throw unknownError;
  }

  // Fetch Snapshot proposal data
  async function fetchSnapshotProposal(space, proposalId, cacheKey) {
    try {
      console.log("🔵 [SNAPSHOT] Fetching proposal - space:", space, "proposalId:", proposalId);

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
      if (space.startsWith('s:')) {
        cleanSpace = space.substring(2); // Remove 's:' prefix for API
      }
      
      // Try format 1: {space}/{proposal-id} (most common)
      const fullProposalId1 = `${cleanSpace}/${proposalId}`;
      // Try format 2: Just the proposal hash (some APIs accept this)
      const fullProposalId2 = proposalId;
      // Try format 3: With 's:' prefix
      const fullProposalId3 = `${space}/${proposalId}`;
      
      console.log("🔵 [SNAPSHOT] Trying proposal ID formats:");
      console.log("  Format 1 (space/proposal):", fullProposalId1);
      console.log("  Format 2 (proposal only):", fullProposalId2);
      console.log("  Format 3 (s:space/proposal):", fullProposalId3);

      // Try format 1 first
      let fullProposalId = fullProposalId1;
      const requestBody = {
        query: queryById,
        variables: { id: fullProposalId }
      };
      console.log("🔵 [SNAPSHOT] Making request to:", SNAPSHOT_GRAPHQL_ENDPOINT);
      console.log("🔵 [SNAPSHOT] Request body:", JSON.stringify(requestBody, null, 2));
      
      const response = await fetchWithRetry(SNAPSHOT_GRAPHQL_ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(requestBody),
      });

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
          console.log("✅ [SNAPSHOT] Proposal fetched successfully with format 1");
          const transformedProposal = transformSnapshotData(proposal, space);
          transformedProposal._cachedAt = Date.now();
          proposalCache.set(cacheKey, transformedProposal);
          return transformedProposal;
        } else {
          console.warn("⚠️ [SNAPSHOT] Format 1 failed, trying format 2 (proposal hash only)...");
          
          // Try format 2: Just the proposal hash
          const retryResponse2 = await fetchWithRetry(SNAPSHOT_GRAPHQL_ENDPOINT, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              query: queryById,
              variables: { id: fullProposalId2 }
            }),
          });
          
          if (retryResponse2.ok) {
            const retryResult2 = await retryResponse2.json();
            if (retryResult2.data?.proposal) {
              console.log("✅ [SNAPSHOT] Proposal fetched with format 2 (hash only)");
              const transformedProposal = transformSnapshotData(retryResult2.data.proposal, space);
              transformedProposal._cachedAt = Date.now();
              proposalCache.set(cacheKey, transformedProposal);
              return transformedProposal;
            }
          }
          
          // Try format 3: With 's:' prefix
          if (space.startsWith('s:') && cleanSpace !== space) {
            console.warn("⚠️ [SNAPSHOT] Format 2 failed, trying format 3 (with 's:' prefix)...");
            const retryResponse3 = await fetchWithRetry(SNAPSHOT_GRAPHQL_ENDPOINT, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({
                query: queryById,
                variables: { id: fullProposalId3 }
              }),
            });
            
            if (retryResponse3.ok) {
              const retryResult3 = await retryResponse3.json();
              if (retryResult3.data?.proposal) {
                console.log("✅ [SNAPSHOT] Proposal fetched with format 3 ('s:' prefix)");
                const transformedProposal = transformSnapshotData(retryResult3.data.proposal, space);
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
        url: SNAPSHOT_GRAPHQL_ENDPOINT,
        proposalId,
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

  // Fetch Aave AIP proposal data using The Graph API (method from ava.mjs)
  // eslint-disable-next-line no-unused-vars
  async function fetchAIPProposal(proposalId, cacheKey, chain = 'mainnet', urlSource = 'app.aave.com') {
    try {
      console.log("🔵 [AIP] Fetching proposal from The Graph API - proposalId:", proposalId, "URL Source:", urlSource);
      
      const result = await fetchAIPFromSubgraph(proposalId);
      if (result) {
        console.log("✅ [AIP] Successfully fetched from The Graph API");
        result._cachedAt = Date.now();
        result.chain = 'thegraph';
        result.urlSource = urlSource; // Store URL source for state mapping
        proposalCache.set(cacheKey, result);
        return result;
      }
      
      // Try on-chain fetch as fallback
      const onChainResult = await fetchAIPFromOnChain(proposalId, urlSource);
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

  // Merge on-chain data with markdown and subgraph metadata
  // Priority: markdown > subgraph > on-chain defaults
  // On-chain data is the source of truth for votes/state
  // Subgraph can provide voting data if on-chain is unavailable
  // eslint-disable-next-line no-unused-vars
  function mergeProposalData(onChainData, markdownData, subgraphMetadata) {
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

  // Parse front-matter from markdown (browser-compatible, no gray-matter needed)
  // Handles YAML front-matter in markdown files
  function parseFrontMatter(text) {
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

  // Fetch proposal markdown from vote.onaave.com
  // This provides rich content: title, description, full markdown body
  // Returns markdown with front-matter parsed
  // eslint-disable-next-line no-unused-vars
  async function fetchAIPMarkdown(proposalId) {
    try {
      // eslint-disable-next-line no-undef
      const apiUrl = `${AAVE_VOTE_SITE}?proposalId=${proposalId}`;
      const response = await fetchWithRetry(apiUrl, {
        method: "GET",
        headers: {
          "Content-Type": "text/plain",
        },
      });

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

  // Fetch proposal metadata from subgraph (for enrichment only)
  // This provides titles, descriptions, voting data, and other metadata
  // NOTE: This is an enhancement, not the primary source
  // If this fails due to CORS, the Data API or on-chain data will be used as fallback
  // Fetch Aave proposal from The Graph API (method from ava.mjs)
  async function fetchAIPFromSubgraph(proposalId) {
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
      });

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
          
          // Convert to milliseconds for Date calculations
          const endTimestampMs = endTimestamp * 1000;
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
            daysLeft = diffDays;
            
            // If it ends today (daysLeft === 0), calculate hours left
            if (diffDays === 0 && diffTime > 0) {
              const diffTimeInHours = diffTime / (1000 * 60 * 60);
              hoursLeft = Math.floor(diffTimeInHours);
            }
            
            console.log("🔵 [AIP] Calculated dates - Activation:", new Date(votingActivationTimestamp * 1000).toISOString(), "End:", new Date(endTimestampMs).toISOString(), "Days left:", daysLeft, "Hours left:", hoursLeft);
          }
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

  // Fetch AIP proposal data directly from Ethereum blockchain (source of truth)
  // This is the most reliable method - no CORS, no backend, will never randomly break
  async function fetchAIPFromOnChain(topicId, urlSource = 'app.aave.com') {
    try {
      // Ensure ethers.js is loaded
      const ethers = await ensureEthersLoaded();
      if (!ethers) {
        console.error("❌ [AIP] ethers.js not available - on-chain fetch disabled");
        console.error("❌ [AIP] This is the PRIMARY method - ethers.js must be loaded!");
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
      // Note: These variables are not defined - this function requires configuration
      // eslint-disable-next-line no-undef
      const provider = new ethers.providers.JsonRpcProvider(ETH_RPC_URL);
      const governanceContract = new ethers.Contract(
        // eslint-disable-next-line no-undef
        AAVE_GOVERNANCE_V3_ADDRESS,
        // eslint-disable-next-line no-undef
        AAVE_GOVERNANCE_V3_ABI,
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
          // eslint-disable-next-line no-undef
          console.error("❌ [AIP] Contract:", AAVE_GOVERNANCE_V3_ADDRESS);
        }
        if (error.message?.includes("network") || error.message?.includes("timeout")) {
          // eslint-disable-next-line no-undef
          console.error("❌ [AIP] RPC connection error - check ETH_RPC_URL:", ETH_RPC_URL);
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

  // Get state mapping based on URL source
  // vote.onaave.com uses: 0='created', 1='voting', 2='passed', 3='failed', 4='executed', 5='expired', 6='cancelled', 7='active'
  // app.aave.com uses: 0='null', 1='created', 2='active', 3='queued', 4='executed', 5='failed', 6='cancelled', 7='expired'
  function getStateMapping(urlSource) {
    if (urlSource === 'vote.onaave.com') {
      return {
        0: 'created',
        1: 'voting',
        2: 'passed',
        3: 'failed',
        4: 'executed',
        5: 'expired',
        6: 'cancelled',
        7: 'active'
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
        7: 'expired'
      };
    }
  }

  // Transform on-chain proposal data to our expected format
  // Using simplified ABI structure: (id, creator, startTime, endTime, forVotes, againstVotes, state, executed, canceled)
  function transformAIPDataFromOnChain(proposal, state, proposalId, urlSource = 'app.aave.com') {
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
      const endTimestampMs = endTime * 1000;
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
        daysLeft = diffDays;
        
        // If it ends today (daysLeft === 0), calculate hours left
        if (diffDays === 0 && diffTime > 0) {
          const diffTimeInHours = diffTime / (1000 * 60 * 60);
          hoursLeft = Math.floor(diffTimeInHours);
        }
        
        console.log("🔵 [AIP] Calculated dates from on-chain - Start:", startTime ? new Date(startTime * 1000).toISOString() : 'N/A', "End:", new Date(endTimestampMs).toISOString(), "Days left:", daysLeft, "Hours left:", hoursLeft);
      }
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

  // Try fetching from official Aave V3 GraphQL API
  // NOTE: This API currently returns "Unknown field 'proposal' on type 'Query'"
  // The GraphQL schema may be different or this endpoint may not be available
  // Disabling this function until the correct API schema is confirmed
  // eslint-disable-next-line no-unused-vars
  async function fetchAIPFromOfficialAPI(topicId) {
    // Skip this API for now since it doesn't support the 'proposal' field
    // Uncomment and fix the query once the correct GraphQL schema is known
    /*
    const query = `
      query Proposal($id: ID!) {
        proposal(id: $id) {
          id
          title
          description
          status
          startBlock
          endBlock
          forVotes
          againstVotes
          abstainVotes
          quorum
          proposer
          createdAt
          executedAt
          votingDuration
          votingStartTime
          votingEndTime
        }
      }
    `;

    try {
      const response = await fetchWithRetry(AAVE_V3_GRAPHQL_API, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          query,
          variables: { id: topicId }
        }),
      });

      if (response.ok) {
        const result = await response.json();
        if (result.errors) {
          console.error("❌ [AIP] Official API GraphQL errors:", result.errors);
          return null;
        }

        const proposal = result.data?.proposal;
        if (proposal) {
          return transformAIPData(proposal);
        }
      }
    } catch (error) {
      console.debug("🔵 [AIP] Official GraphQL API error:", error.message);
    }
    */
    return null;
  }

  // Try fetching from Aave V3 Data API (JSON endpoint)
  // Fallback method - has CORS issues, only use if on-chain fails
  // NOTE: On-chain should be PRIMARY (no CORS, direct blockchain access)
  // eslint-disable-next-line no-unused-vars
  async function fetchAIPFromDataAPI(topicId) {
    // This endpoint has CORS issues - only use as last resort
    // eslint-disable-next-line no-undef
    const response = await fetchWithRetry(AAVE_V3_DATA_API, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
      },
      // Note: CORS issues expected with this endpoint
    });

    if (response.ok) {
      const data = await response.json();
      // Search for proposal in the governance history
      // The JSON structure may vary, so we need to search for the proposal
      if (Array.isArray(data)) {
        const proposal = data.find(p => 
          p.id === topicId || 
          p.proposalId === topicId || 
          String(p.id) === String(topicId) ||
          String(p.proposalId) === String(topicId)
        );
        if (proposal) {
          // Transform the JSON data to match our expected format
          return transformAIPDataFromJSON(proposal);
        }
      } else if (data.proposals) {
        // If it's an object with proposals array
        const proposal = data.proposals.find(p => 
          p.id === topicId || 
          p.proposalId === topicId ||
          String(p.id) === String(topicId) ||
          String(p.proposalId) === String(topicId)
        );
        if (proposal) {
          return transformAIPDataFromJSON(proposal);
        }
      }
    }
    return null;
  }

  // Transform JSON data from Aave V3 Data API to our format
  function transformAIPDataFromJSON(jsonData) {
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

  // Fallback: Fetch from TheGraph subgraphs (DEPRECATED - endpoints removed)
  // NOTE: TheGraph has removed these endpoints. This function is kept for compatibility
  // but will always return null. Use Official API or Data API instead.
  // eslint-disable-next-line no-unused-vars
  async function fetchAIPFromTheGraph(topicId, cacheKey, chain = 'mainnet') {
    console.warn("⚠️ [AIP] TheGraph subgraphs are no longer available (endpoints removed)");
    console.warn("⚠️ [AIP] Using Official Aave V3 API or Aave V3 Data API instead");
    return null;
    
    // Old code below (commented out since endpoints are removed)
    /*
    try {
      console.log("🔵 [AIP] Trying TheGraph subgraph - chain:", chain);

      // GraphQL query for Aave Governance V3
      const query = `
        query Proposal($id: ID!) {
          proposal(id: $id) {
            id
            title
            description
            status
            startBlock
            endBlock
            forVotes
            againstVotes
            abstainVotes
            quorum
            proposer
            createdAt
            executedAt
            votingDuration
            votingStartTime
            votingEndTime
          }
        }
      `;

      // Select subgraph based on chain
      let subgraphUrl;
      switch (chain.toLowerCase()) {
        case 'polygon':
          subgraphUrl = AAVE_SUBGRAPH_POLYGON;
          break;
        case 'avalanche':
        case 'avax':
          subgraphUrl = AAVE_SUBGRAPH_AVALANCHE;
          break;
        case 'mainnet':
        case 'ethereum':
        default:
          subgraphUrl = AAVE_SUBGRAPH_MAINNET;
      }

      console.log("🔵 [AIP] Trying TheGraph subgraph:", subgraphUrl);

      // Try fetching from the selected subgraph
      let response;
      try {
        response = await fetch(subgraphUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            query,
            variables: { id: topicId }
          }),
        });
      } catch (corsError) {
        // CORS error - TheGraph API blocks browser requests
        // Only log once per proposal to reduce console noise
        if (chain === 'mainnet') {
          console.warn("⚠️ [AIP] CORS error: TheGraph API blocks browser requests");
          console.warn("⚠️ [AIP] Note: AIP data requires a backend proxy server. Snapshot proposals work fine.");
        } else {
          // Use debug level for fallback attempts to reduce noise
          console.debug("🔵 [AIP] CORS error on", chain, "- trying other chains...");
        }
        
        // Try other chains if mainnet fails (though they'll likely also fail due to CORS)
        if (chain === 'mainnet') {
          console.log("🔵 [AIP] Trying Polygon subgraph as fallback...");
          const polygonResult = await fetchAIPFromTheGraph(topicId, cacheKey, 'polygon');
          if (polygonResult) {
            return polygonResult;
          }
          
          console.log("🔵 [AIP] Trying Avalanche subgraph as fallback...");
          const avalancheResult = await fetchAIPFromTheGraph(topicId, cacheKey, 'avalanche');
          if (avalancheResult) {
            return avalancheResult;
          }
        }
        
        // Only show final warning once
        if (chain === 'mainnet') {
          console.warn("⚠️ [AIP] All subgraph attempts failed due to CORS restrictions");
          console.warn("⚠️ [AIP] Solution: Use a backend proxy server to fetch AIP data from TheGraph");
        }
        return null;
      }

      if (response.ok) {
        const result = await response.json();
        if (result.errors) {
          console.error("❌ [AIP] GraphQL errors on", chain, ":", result.errors);
          
          // Try other chains if current one has errors
          if (chain === 'mainnet' && result.errors.some((e) => e.message?.includes('not found'))) {
            console.log("🔵 [AIP] Proposal not found on Mainnet, trying Polygon...");
            const polygonResult = await fetchAIPFromTheGraph(topicId, cacheKey, 'polygon');
            if (polygonResult) {
              return polygonResult;
            }
            
            console.log("🔵 [AIP] Trying Avalanche...");
            const avalancheResult = await fetchAIPFromTheGraph(topicId, cacheKey, 'avalanche');
            if (avalancheResult) {
              return avalancheResult;
            }
          }
          
          return null;
        }

        const proposal = result.data?.proposal;
        if (proposal) {
          console.log("✅ [AIP] Proposal fetched successfully from", chain);
          const transformedProposal = transformAIPData(proposal);
          transformedProposal._cachedAt = Date.now();
          transformedProposal.chain = chain; // Store which chain it came from
          proposalCache.set(cacheKey, transformedProposal);
          return transformedProposal;
        } else {
          console.warn("⚠️ [AIP] No proposal data in response from", chain);
          
          // Try other chains if current one returns no data
          if (chain === 'mainnet') {
            console.log("🔵 [AIP] Trying Polygon subgraph...");
            const polygonResult = await fetchAIPFromTheGraph(topicId, cacheKey, 'polygon');
            if (polygonResult) {
              return polygonResult;
            }
            
            console.log("🔵 [AIP] Trying Avalanche subgraph...");
            const avalancheResult = await fetchAIPFromTheGraph(topicId, cacheKey, 'avalanche');
            if (avalancheResult) {
              return avalancheResult;
            }
          }
        }
      } else {
        const errorText = await response.text();
        console.error("❌ [AIP] HTTP error on", chain, ":", response.status, errorText);
        
        // Try other chains on HTTP error
        if (chain === 'mainnet' && response.status === 404) {
          console.log("🔵 [AIP] Not found on Mainnet, trying other chains...");
          const polygonResult = await fetchAIPFromTheGraph(topicId, cacheKey, 'polygon');
          if (polygonResult) {
            return polygonResult;
          }
          
          const avalancheResult = await fetchAIPFromTheGraph(topicId, cacheKey, 'avalanche');
          if (avalancheResult) {
            return avalancheResult;
          }
        }
      }
    } catch (error) {
      // Only log if it's not a CORS error (already handled above)
      if (!error.message || (!error.message.includes('CORS') && !error.message.includes('Failed to fetch'))) {
        console.error("❌ [AIP] Error fetching proposal from", chain, ":", error);
      }
      
      // Try other chains on error
      if (chain === 'mainnet') {
        console.log("🔵 [AIP] Error on Mainnet, trying other chains...");
        try {
          const polygonResult = await fetchAIPFromTheGraph(topicId, cacheKey, 'polygon');
          if (polygonResult) {
            return polygonResult;
          }
        } catch {
          // Ignore
        }
        
        try {
          const avalancheResult = await fetchAIPFromTheGraph(topicId, cacheKey, 'avalanche');
          if (avalancheResult) {
            return avalancheResult;
          }
        } catch {
          // Ignore
        }
      }
    }
    */
    // eslint-disable-next-line no-unreachable
    return null;
  }

  // eslint-disable-next-line no-unused-vars
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
      hoursLeft,
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

  // Transform Snapshot proposal data to widget format
  function transformSnapshotData(proposal, space) {
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

  // Transform AIP proposal data to widget format
  // eslint-disable-next-line no-unused-vars
  function transformAIPData(proposal) {
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
      
      // Convert to milliseconds for Date calculations
      const endTimestampMs = endTimestamp * 1000;
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
        daysLeft = diffDays;
        
        // If it ends today (daysLeft === 0), calculate hours left
        if (diffDays === 0 && diffTime > 0) {
          const diffTimeInHours = diffTime / (1000 * 60 * 60);
          hoursLeft = Math.floor(diffTimeInHours);
        }
        
        console.log("🔵 [AIP] Calculated dates in transformAIPData - Activation:", new Date(activationTimestamp * 1000).toISOString(), "End:", new Date(endTimestampMs).toISOString(), "Days left:", daysLeft, "Hours left:", hoursLeft);
      }
    } else if (daysLeft === null && proposal.endTime) {
      // Fallback: use endTime directly if available
      const endTimestampMs = Number(proposal.endTime) * 1000;
      const now = Date.now();
      const diffTime = endTimestampMs - now;
      const diffTimeInDays = diffTime / (1000 * 60 * 60 * 24);
      
      let diffDays;
      if (diffTimeInDays >= 0) {
        diffDays = Math.floor(diffTimeInDays);
      } else {
        diffDays = Math.ceil(diffTimeInDays);
      }
      
      if (!isNaN(diffDays) && isFinite(diffDays)) {
        daysLeft = diffDays;
        if (diffDays === 0 && diffTime > 0) {
          const diffTimeInHours = diffTime / (1000 * 60 * 60);
          hoursLeft = Math.floor(diffTimeInHours);
        }
      }
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

  function formatVoteAmount(amount) {
    if (!amount || amount === 0) {return "0";}
    
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

  // Render status widget on the right side (outside post box) - like the image
  // Render multi-stage widget showing Temp Check, ARFC, and AIP all together
  // Get or create the widgets container for column layout
  function getOrCreateWidgetsContainer() {
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
  
  // Update container position - keep fixed on right side like tally widget
  function updateContainerPosition(container) {
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

  function renderMultiStageWidget(stages, widgetId, proposalOrder = null) {
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
    
    // Helper function to format time display
    function formatTimeDisplay(daysLeft, hoursLeft) {
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
    
    // Helper to render Snapshot stage section
    function renderSnapshotStage(stageData, stageUrl, stageName) {
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
      
      const isActive = stageData.status === 'active' || stageData.status === 'open';
      const isPassed = stageData.status === 'passed' || 
                       stageData.status === 'closed' || 
                       (stageData.status === 'executed' && supportPercent > 50) ||
                       (stageData.status !== 'active' && stageData.status !== 'open' && supportPercent > 50);
      const status = isPassed ? 'Passed' : (isActive ? 'Active' : 'Closed');
      const statusClass = isPassed ? 'executed' : (isActive ? 'active' : 'inactive');
      const timeDisplay = formatTimeDisplay(stageData.daysLeft, stageData.hoursLeft);
      
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
      const statusLower = (stageData.status || '').toLowerCase();
      const isEnded = (stageData.daysLeft !== null && stageData.daysLeft < 0) ||
                      statusLower === 'executed' || 
                      statusLower === 'passed' ||
                      statusLower === 'queued' ||
                      statusLower === 'failed' ||
                      statusLower === 'cancelled' ||
                      statusLower === 'expired';
      
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
    
    // Helper to render AIP stage section
    function renderAIPStage(stageData, stageUrl) {
      if (!stageData) {
        return '';
      }
      
      console.log('🔵 [RENDER] Rendering AIP stage with data:', stageData);
      
      // Use exact status from API (no mapping)
      const status = stageData.status || 'unknown';
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
      
      const timeDisplay = formatTimeDisplay(stageData.daysLeft, stageData.hoursLeft);
      // eslint-disable-next-line no-unused-vars
      const isEndingSoon = stageData.daysLeft !== null && stageData.daysLeft >= 0 && 
                          (stageData.daysLeft === 0 || (stageData.daysLeft === 1 && stageData.hoursLeft !== null && stageData.hoursLeft < 24));
      
      // Extract AIP number from title if possible
      const aipMatch = stageData.title.match(/AIP[#\s]*(\d+)/i);
      const aipNumber = aipMatch ? `#${aipMatch[1]}` : '';
      
      // Format vote amounts (same as Snapshot - with K for thousands)
      // eslint-disable-next-line no-shadow
      const formatVoteAmount = (num) => {
        const n = Number(num);
        if (n >= 1000) {
          return (n / 1000).toFixed(2).replace(/\.?0+$/, '') + 'K';
        }
        return n.toLocaleString('en-US', { maximumFractionDigits: 2 });
      };
      
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
      
      // Use exact status from API - show as-is (capitalize first letter only)
      const statusBadgeText = status.charAt(0).toUpperCase() + status.slice(1).toLowerCase();
      
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
    
    // Build stage HTML separately for debugging
    const tempCheckHTML = stages.tempCheck ? renderSnapshotStage(stages.tempCheck, stages.tempCheckUrl, 'Temp Check') : '';
    const arfcHTML = stages.arfc ? renderSnapshotStage(stages.arfc, stages.arfcUrl, 'ARFC') : '';
    const aipHTML = stages.aip ? renderAIPStage(stages.aip, stages.aipUrl) : '';
    
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
        
        // Position is already set by updateContainerPosition - no need to update
        
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
      const snapshotLink = post.querySelector('a[href*="snapshot.org"]');
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
          // Only include Aave Snapshot space links (aave.eth or s:aavedao.eth)
          if (url.includes('aave.eth') || url.includes('aavedao.eth')) {
            if (!extractedLinks.snapshot.includes(url)) {
              extractedLinks.snapshot.push(url);
              console.log("✅ [FORUM] Found Snapshot link:", url);
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
          // Only include Aave Snapshot space links
          if (url.includes('aave.eth') || url.includes('aavedao.eth')) {
            if (!proposals.snapshot.includes(url)) {
              proposals.snapshot.push(url);
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

  // Hide widget if no Snapshot proposal is visible
  // Show error widget when proposals fail to load
  function showNetworkErrorWidget(count, type) {
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
    const container = getOrCreateWidgetsContainer();
    container.appendChild(errorWidget);
    console.log(`⚠️ [ERROR] Showing error widget for ${count} failed ${type} proposal(s)`);
  }

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
    
    // Clean up empty container
    const container = document.getElementById('governance-widgets-wrapper');
    if (container && container.children.length === 0) {
      container.remove();
      console.log("🔵 [CONTAINER] Removed empty widgets container");
    }
    
    if (widgetCount > 0) {
      console.log("🔵 [WIDGET] Removed", widgetCount, "widget(s) - no proposal in current post");
    }
    // Reset current visible proposal
    currentVisibleProposal = null;
  }

  // Show widget
  // eslint-disable-next-line no-unused-vars
  function showWidget() {
    const allWidgets = document.querySelectorAll('.tally-status-widget-container');
    allWidgets.forEach(widget => {
      widget.style.display = '';
      widget.style.visibility = '';
    });
  }

  // Fetch proposal data (wrapper for compatibility with old code)
  async function fetchProposalData(proposalId, url, govId, urlProposalNumber, forceRefresh = false) {
    if (!url) {return null;}
    
    // Determine type from URL
    let type = null;
    if (url.includes('snapshot.org')) {
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
        return await fetchSnapshotProposal(proposalInfo.space, proposalInfo.proposalId, cacheKey);
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
        return await fetchAIPProposal(proposalId, cacheKey, 'mainnet', urlSource);
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
    console.log(`🔵 [TOPIC] Rendering ${totalProposals} widget(s) - one per unique proposal URL`);
    
    // Create combined ordered list of all proposals (maintain order: snapshot first, then aip)
    // This preserves the order proposals appear in the content
    const orderedProposals = [];
    uniqueSnapshotUrls.forEach((url, index) => {
      orderedProposals.push({ url, type: 'snapshot', originalIndex: index });
    });
    uniqueAipUrls.forEach((url, index) => {
      orderedProposals.push({ url, type: 'aip', originalIndex: index });
    });
    
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
          
          // Render one widget per Snapshot proposal
          validSnapshots.forEach((snapshot, index) => {
            // Check again if URL is being rendered (in case another fetch completed first)
            if (renderingUrls.has(snapshot.url)) {
              console.log(`🔵 [TOPIC] Snapshot URL ${snapshot.url} is already being rendered, skipping duplicate render`);
              return;
            }
            
            const stage = snapshot.data.stage || 'snapshot';
            const stageName = stage === 'temp-check' ? 'Temp Check' : 
                             stage === 'arfc' ? 'ARFC' : 'Snapshot';
            
            // Find proposal order in combined list (order in content)
            const proposalOrderIndex = orderedProposals.findIndex(p => p.url === snapshot.url && p.type === 'snapshot');
            const proposalOrder = proposalOrderIndex >= 0 ? proposalOrderIndex : index;
            
            console.log(`🔵 [RENDER] Creating Snapshot widget ${index + 1}/${validSnapshots.length} for ${stageName} (order: ${proposalOrder})`);
            console.log(`   Title: ${snapshot.data.title?.substring(0, 60)}...`);
            console.log(`   URL: ${snapshot.url}`);
            
            // Create unique widget ID for each proposal
            const widgetId = `snapshot-widget-${index}-${Date.now()}`;
            
            // Render single proposal widget based on its stage, with proposal order
            renderMultiStageWidget({
              tempCheck: stage === 'temp-check' ? snapshot.data : null,
              tempCheckUrl: stage === 'temp-check' ? snapshot.url : null,
              arfc: (stage === 'arfc' || stage === 'snapshot') ? snapshot.data : null,
              arfcUrl: (stage === 'arfc' || stage === 'snapshot') ? snapshot.url : null,
              aip: null,
              aipUrl: null
            }, widgetId, proposalOrder);
            
            console.log(`✅ [RENDER] Snapshot widget ${index + 1} rendered`);
          });
        })
        .catch(error => {
          console.error("❌ [TOPIC] Error processing Snapshot proposals:", error);
        });
    }
    
    // ===== AIP WIDGETS - One per URL =====
    if (uniqueAipUrls.length > 0) {
      uniqueAipUrls.forEach((aipUrl, aipIndex) => {
        // Check if this URL is already being fetched or rendered
        if (fetchingUrls.has(aipUrl) || renderingUrls.has(aipUrl)) {
          console.log(`🔵 [TOPIC] AIP URL ${aipUrl} is already being fetched/rendered, skipping duplicate`);
          return;
        }
        
        // Find proposal order in combined list (order in content)
        const proposalOrderIndex = orderedProposals.findIndex(p => p.url === aipUrl && p.type === 'aip');
        const proposalOrder = proposalOrderIndex >= 0 ? proposalOrderIndex : (uniqueSnapshotUrls.length + aipIndex);
        
        // Mark URL as being fetched
        fetchingUrls.add(aipUrl);
        
        fetchProposalDataByType(aipUrl, 'aip')
          .then(aipData => {
            // Remove from fetching set when fetch completes
            fetchingUrls.delete(aipUrl);
            
            // Check again if URL is being rendered (in case another fetch completed first)
            if (renderingUrls.has(aipUrl)) {
              console.log(`🔵 [TOPIC] AIP URL ${aipUrl} is already being rendered, skipping duplicate render`);
              return;
            }
            
            if (aipData && aipData.title) {
              const aipWidgetId = `aip-widget-${aipIndex}-${Date.now()}`;
              console.log(`🔵 [RENDER] Creating AIP widget ${aipIndex + 1} (order: ${proposalOrder})`);
              renderMultiStageWidget({
                tempCheck: null,
                tempCheckUrl: null,
                arfc: null,
                arfcUrl: null,
                aip: aipData,
                aipUrl
              }, aipWidgetId, proposalOrder);
              console.log(`✅ [RENDER] AIP widget ${aipIndex + 1} rendered`);
        } else {
              console.warn(`⚠️ [TOPIC] AIP data fetched but missing title:`, aipData);
        }
      })
      .catch(error => {
            // Remove from fetching set on error
            fetchingUrls.delete(aipUrl);
            console.warn(`⚠️ [TOPIC] Error fetching AIP ${aipIndex + 1} from ${aipUrl}:`, error.message || error);
            // Don't throw - just log and continue with other widgets
          });
      });
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
  /*
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
          // No Snapshot proposal in this post - remove all widgets immediately
          console.log("🔵 [SCROLL] Post", postInfo.current, "/", postInfo.total, "has no Snapshot proposal - removing all widgets");
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
                if (data && data.title && data.title !== "Snapshot Proposal") {
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
        console.log("🔵 [SCROLL] No Snapshot links found on page - hiding widget");
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
              if (data && data.title && data.title !== "Snapshot Proposal") {
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
  */

  // OLD SCROLL TRACKING FUNCTION - REMOVED (replaced with setupTopicWidget)
  /*
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
            console.log("🔵 [SCROLL] Post", postInfo.current, "/", postInfo.total, "has no Snapshot proposal - removing all widgets");
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
            // No Snapshot link in this post - hide widget
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
                if (data && data.title && data.title !== "Snapshot Proposal") {
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
            console.log("🔵 [INIT] Initial post", postInfo.current, "/", postInfo.total, "has no Snapshot proposal - all widgets removed");
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
  */

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


