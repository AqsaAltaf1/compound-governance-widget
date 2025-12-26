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
  // CRITICAL: Force scroll to top (0, 0) on page load
  // User wants to stay at top, no auto-scroll to proposals
  // This prevents Discourse from auto-scrolling to posts/proposals
  let initialScrollX = 0;
  let initialScrollY = 0;
  
  // Immediately force scroll to top
  window.scrollTo(0, 0);
  document.documentElement.scrollLeft = 0;
  document.documentElement.scrollTop = 0;
  document.body.scrollLeft = 0;
  document.body.scrollTop = 0;
  
  // Lock scroll position during initial widget setup to prevent auto-scrolling
  let scrollLocked = true;
  let widgetsInserting = false; // Track when widgets are being inserted
  
  const restoreScroll = () => {
    if (scrollLocked || widgetsInserting) {
      // Always restore to top (0, 0) - user wants to stay at top
      window.scrollTo(0, 0);
      document.documentElement.scrollLeft = 0;
      document.documentElement.scrollTop = 0;
      document.body.scrollLeft = 0;
      document.body.scrollTop = 0;
    }
  };
  
  const lockScrollUntilWidgetsReady = () => {
    // Stop locking after widgets are ready (reduced to 500ms to allow immediate scrolling)
    // Note: We rely on MutationObserver and scroll event listener instead of fixed intervals
    setTimeout(() => {
      scrollLocked = false;
      // Final restore to top
      restoreScroll();
    }, 500);
  };
  
  // Start scroll locking immediately
  lockScrollUntilWidgetsReady();
  
  // CRITICAL: Aggressively restore scroll position on any scroll event during lock/insertion
  // This prevents Discourse or browser from auto-scrolling to widgets or posts
  const aggressiveScrollRestore = (e) => {
    if (scrollLocked || widgetsInserting) {
      // Prevent default scroll behavior and force to top
      if (e) {
        e.preventDefault();
        e.stopPropagation();
      }
      restoreScroll();
    }
  };
  
  // Listen for scroll events and restore position if locked (non-passive to allow preventDefault)
  window.addEventListener('scroll', aggressiveScrollRestore, { passive: false, capture: true });
  
  // Also restore on any DOM mutations that might trigger scrolling
  const scrollRestoreOnMutation = () => {
    if (scrollLocked || widgetsInserting) {
      // Use multiple methods to ensure scroll is restored
      requestAnimationFrame(() => {
        restoreScroll();
        setTimeout(() => restoreScroll(), 0);
        setTimeout(() => restoreScroll(), 10);
        setTimeout(() => restoreScroll(), 50);
      });
    }
  };
  
  // CRITICAL: Also prevent scrolling when widgets are added to DOM via MutationObserver
  // This catches any scroll events triggered by DOM changes
  const scrollPreventionObserver = new MutationObserver((mutations) => {
    // Check if widgets are being added
    const hasWidgetAddition = mutations.some(mutation => {
      return Array.from(mutation.addedNodes).some(node => {
        if (node.nodeType === 1) { // Element node
          return node.classList?.contains('tally-status-widget-container') ||
                 node.classList?.contains('governance-widgets-wrapper') ||
                 node.querySelector?.('.tally-status-widget-container') ||
                 node.querySelector?.('.governance-widgets-wrapper');
        }
        return false;
      });
    });
    
    if (hasWidgetAddition) {
      widgetsInserting = true;
      scrollRestoreOnMutation();
      // Keep preventing scroll for 500ms after widget insertion
      setTimeout(() => {
        widgetsInserting = false;
      }, 500);
    }
    
    if (scrollLocked || widgetsInserting) {
      scrollRestoreOnMutation();
    }
  });
  
  // Observe document body for widget additions
  if (document.body) {
    scrollPreventionObserver.observe(document.body, {
      childList: true,
      subtree: true
    });
  }
  
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
  // Support both production (snapshot.org) and testnet (testnet.snapshot.box) domains
  const SNAPSHOT_GRAPHQL_ENDPOINT = "https://hub.snapshot.org/graphql";
  const SNAPSHOT_TESTNET_GRAPHQL_ENDPOINT = "https://testnet.hub.snapshot.org/graphql";
  // Match both snapshot.org and testnet.snapshot.box URLs
  const SNAPSHOT_URL_REGEX = /https?:\/\/(?:www\.)?(?:snapshot\.org|testnet\.snapshot\.box)\/#\/[^\s<>"']+/gi;
  
  // Aave Governance Forum Configuration
  // Primary entry point: Aave Governance Forum thread
  // Matches governance.aave.com specifically (for backward compatibility)
  const AAVE_FORUM_URL_REGEX = /https?:\/\/(?:www\.)?governance\.aave\.com\/t\/[^\s<>"']+/gi;
  
  // Discourse Forum URL Pattern - matches any Discourse forum URL (works for any Discourse instance)
  // Pattern: https://[domain]/t/[slug]/[topicId]
  const DISCOURSE_FORUM_URL_REGEX = /https?:\/\/[^\s<>"']+\/t\/[^\/\s<>"']+\/\d+/gi;
  
  // Aave AIP Configuration
  // Support both governance.aave.com and app.aave.com/governance/
  const AAVE_GOVERNANCE_PORTAL = "https://app.aave.com/governance";
  
  // Aave Governance V3 - Using The Graph API with API key (method from ava.mjs)
  const GRAPH_API_KEY = "9e7b4a29889ac6c358b235230a5fe940";
  const SUBGRAPH_ID = "A7QMszgomC9cnnfpAcqZVLr2DffvkGNfimD8iUSMiurK";
  const AAVE_V3_SUBGRAPH = `https://gateway.thegraph.com/api/${GRAPH_API_KEY}/subgraphs/id/${SUBGRAPH_ID}`;
  
  // On-chain fallback configuration (used when The Graph API is unavailable)
  // Aave Governance V3 Contract Address (Ethereum Mainnet)
  const AAVE_GOVERNANCE_V3_ADDRESS = "0xEC568fffba86c094cf06b22134B23074DFE2252c";
  
  // Simplified ABI for getProposal - returns: (id, creator, startTime, endTime, forVotes, againstVotes, state, executed, canceled)
  const AAVE_GOVERNANCE_V3_ABI = [
    "function getProposal(uint256 proposalId) view returns (uint256 id, address creator, uint40 startTime, uint40 endTime, uint256 forVotes, uint256 againstVotes, uint8 state, bool executed, bool canceled)",
    "function getProposalState(uint256 proposalId) view returns (uint8)"
  ];
  
  // Ethereum RPC endpoint for on-chain fallback
  // Using a public RPC endpoint - can be overridden via environment variable if needed
  const ETH_RPC_URL = "https://eth.llamarpc.com";
  
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
  // NOTE: Exclude forum topic URLs (governance.aave.com/t/) - those are NOT AIP proposal URLs
  // Only match:
  // - governance.aave.com/aip/{id} (AIP pages)
  // - app.aave.com/governance (governance portal)
  // - vote.onaave.com (voting portal)
  // Note: [^\s<>"']+ matches any character except whitespace, <, >, ", or '
  // This should match URLs even with HTML-encoded entities like &amp;
  const AIP_URL_REGEX = /https?:\/\/(?:www\.)?(?:governance\.aave\.com\/(?!t\/)[^\s<>"']+|app\.aave\.com\/governance[^\s<>"']+|vote\.onaave\.com[^\s<>"']+)/gi;
  
  const proposalCache = new Map();
  
  // localStorage-based persistent cache for proposal data
  const STORAGE_PREFIX = 'compound_gov_widget_';
  const CACHE_EXPIRY = 1 * 60 * 60 * 1000; // 1 hour (allows fresh data while still caching)
  
  // Helper functions for localStorage caching
  function getCachedProposalData(url) {
    try {
      const cacheKey = STORAGE_PREFIX + btoa(url).replace(/[+/=]/g, '');
      const cached = localStorage.getItem(cacheKey);
      if (cached) {
        const data = JSON.parse(cached);
        const cacheAge = Date.now() - (data._cachedAt || 0);
        if (cacheAge < CACHE_EXPIRY) {
          console.log("💾 [STORAGE] Returning cached data from localStorage (age:", Math.round(cacheAge / 1000 / 60), "minutes)");
          return data;
        } else {
          // Expired, remove it
          localStorage.removeItem(cacheKey);
        }
      }
    } catch (error) {
      console.warn("⚠️ [STORAGE] Error reading from localStorage:", error);
    }
    return null;
  }
  
  function setCachedProposalData(url, data) {
    try {
      const cacheKey = STORAGE_PREFIX + btoa(url).replace(/[+/=]/g, '');
      const dataToStore = { ...data, _cachedAt: Date.now() };
      localStorage.setItem(cacheKey, JSON.stringify(dataToStore));
      console.log("💾 [STORAGE] Cached proposal data to localStorage");
    } catch (error) {
      console.warn("⚠️ [STORAGE] Error writing to localStorage:", error);
      // If quota exceeded, try to clear old entries
      if (error.name === 'QuotaExceededError') {
        clearOldCacheEntries();
      }
    }
  }
  
  function clearOldCacheEntries() {
    try {
      const keys = Object.keys(localStorage);
      const now = Date.now();
      let cleared = 0;
      keys.forEach(key => {
        if (key.startsWith(STORAGE_PREFIX)) {
          try {
            const data = JSON.parse(localStorage.getItem(key));
            if (data._cachedAt && (now - data._cachedAt) > CACHE_EXPIRY) {
              localStorage.removeItem(key);
              cleared++;
            }
          } catch {
            // Invalid entry, remove it
            localStorage.removeItem(key);
            cleared++;
          }
        }
      });
      if (cleared > 0) {
        console.log(`🧹 [STORAGE] Cleared ${cleared} expired cache entries`);
      }
    } catch (error) {
      console.warn("⚠️ [STORAGE] Error clearing old cache entries:", error);
    }
  }
  
  // Track which topics have had widgets shown (to prevent disappearing on scroll)
  function getTopicKey() {
    const path = window.location.pathname;
    const topicMatch = path.match(/\/t\/([^\/]+)\/(\d+)/);
    if (topicMatch) {
      return `topic_${topicMatch[2]}`; // Use topic ID as key
    }
    return `page_${path}`; // Fallback to full path
  }
  
  function hasWidgetBeenShown() {
    try {
      const topicKey = getTopicKey();
      const shownKey = STORAGE_PREFIX + 'shown_' + topicKey;
      return localStorage.getItem(shownKey) === 'true';
    } catch {
      return false;
    }
  }
  
  function markWidgetAsShown() {
    try {
      const topicKey = getTopicKey();
      const shownKey = STORAGE_PREFIX + 'shown_' + topicKey;
      localStorage.setItem(shownKey, 'true');
      console.log("✅ [STORAGE] Marked widget as shown for topic:", topicKey);
    } catch (error) {
      console.warn("⚠️ [STORAGE] Error marking widget as shown:", error);
    }
  }

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
  // Format: https://snapshot.org/#/{space}/{proposal-id} or https://testnet.snapshot.box/#/{space}/{proposal-id}
  // Example: https://snapshot.org/#/aave.eth/0x1234...
  // Example: https://testnet.snapshot.box/#/s-tn:sepolia-testnet-123.eth/proposal/0x1234...
  function extractSnapshotProposalInfo(url) {
    console.log("🔍 Extracting Snapshot proposal info from URL:", url);
    
    try {
      // Match pattern for both production and testnet: {domain}/#/{space}/proposal/{proposal-id}
      // Handles: snapshot.org/#/s:aavedao.eth/proposal/0x1234...
      // Handles: testnet.snapshot.box/#/s-tn:sepolia-testnet-123.eth/proposal/0x1234...
      const proposalMatch = url.match(/(?:snapshot\.org|testnet\.snapshot\.box)\/#\/([^\/]+)\/proposal\/([a-zA-Z0-9]+)/i);
      if (proposalMatch) {
        const space = proposalMatch[1];
        const proposalId = proposalMatch[2];
        const isTestnet = url.includes('testnet.snapshot.box');
        console.log("✅ Extracted Snapshot format:", { space, proposalId, isTestnet });
        return { space, proposalId, type: 'snapshot', isTestnet };
      }
      
      // Match pattern: {domain}/#/{space}/{proposal-id} (without /proposal/)
      const directMatch = url.match(/(?:snapshot\.org|testnet\.snapshot\.box)\/#\/([^\/]+)\/([a-zA-Z0-9]+)/i);
      if (directMatch) {
        const space = directMatch[1];
        const proposalId = directMatch[2];
        // Skip if proposalId is "proposal" (means it's the /proposal/ path but regex didn't match correctly)
        if (proposalId.toLowerCase() !== 'proposal') {
          const isTestnet = url.includes('testnet.snapshot.box');
          console.log("✅ Extracted Snapshot format (direct):", { space, proposalId, isTestnet });
          return { space, proposalId, type: 'snapshot', isTestnet };
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
      
      // REMOVED: governance.aave.com/t/{slug}/{id} pattern
      // Forum topic URLs are NOT AIP proposal URLs - they should not be parsed as proposals
      // This was causing errors where forum topic IDs were being treated as AIP proposal IDs
      
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
  // NOTE: This function extracts identifiers but does NOT determine the final type.
  // The type should be determined by fetching from the API (see fetchProposalTypeFromAPI)
  function extractProposalInfo(url) {
    if (!url) {return null;}
    
    // Try Snapshot first
    const snapshotInfo = extractSnapshotProposalInfo(url);
    if (snapshotInfo) {
      // Return format compatible with existing code
      // Type will be determined by API fetch, not URL pattern
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
      // Type will be determined by API fetch, not URL pattern
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

  // Validate that a Snapshot proposal is a valid Aave governance proposal
  // Validate proposal is from Aave space - uses space from API response (authoritative source)
  function isValidAaveGovernanceProposal(proposal, space, isTestnet = false) {
    if (!proposal) {
      return false;
    }
    
    // Handle testnet spaces differently - allow testnet spaces for testing
    if (isTestnet) {
      console.log("🔵 [VALIDATE] Testnet proposal detected - allowing testnet space");
      console.log("✅ [VALIDATE] Testnet proposal is valid (skipping space validation)");
      return true;
    }
    
    // Use space from API response (authoritative source) - fallback to URL-extracted space
    const apiSpaceId = proposal.space?.id || proposal.space?.name;
    const spaceToCheck = apiSpaceId || space;
    
    // Clean space for comparison (handle prefixes like 's:' or 's-tn:')
    let cleanSpace = spaceToCheck;
    if (spaceToCheck.startsWith('s:')) {
      cleanSpace = spaceToCheck.substring(2);
    } else if (spaceToCheck.startsWith('s-tn:')) {
      cleanSpace = spaceToCheck.substring(5);
    }
    
    // Verify space is from Aave (aave.eth or aavedao.eth)
    const isAaveSpace = cleanSpace === 'aave.eth' || 
                       cleanSpace === 'aavedao.eth' ||
                       spaceToCheck === 'aave.eth' ||
                       spaceToCheck === 'aavedao.eth' ||
                       spaceToCheck === 's:aave.eth' ||
                       spaceToCheck === 's:aavedao.eth';
    
    if (!isAaveSpace) {
      console.log("❌ [VALIDATE] Proposal space is not Aave:", cleanSpace, "(from API:", apiSpaceId, ")");
      return false;
    }
    
    console.log("✅ [VALIDATE] Proposal is valid Aave governance proposal (space:", cleanSpace, ")");
    return true;
  }

  // Fetch Snapshot proposal data
  async function fetchSnapshotProposal(space, proposalId, cacheKey, isTestnet = false) {
    // Use testnet endpoint if isTestnet is true (defined outside try block for error handling)
    const graphqlEndpoint = isTestnet ? SNAPSHOT_TESTNET_GRAPHQL_ENDPOINT : SNAPSHOT_GRAPHQL_ENDPOINT;
    
    try {
      console.log("🔵 [SNAPSHOT] Fetching proposal - space:", space, "proposalId:", proposalId, "isTestnet:", isTestnet);

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
            discussion
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
      // Handle testnet space format: s-tn:sepolia-testnet-123.eth
      if (space.startsWith('s-tn:')) {
        cleanSpace = space.substring(5); // Remove 's-tn:' prefix for API
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
      console.log("🔵 [SNAPSHOT] Making request to:", graphqlEndpoint);
      console.log("🔵 [SNAPSHOT] Request body:", JSON.stringify(requestBody, null, 2));
      
      const response = await fetchWithRetry(graphqlEndpoint, {
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
          
          // Validate that this is a valid Aave governance proposal (check space from API)
          if (!isValidAaveGovernanceProposal(proposal, space, isTestnet)) {
            console.warn("❌ [SNAPSHOT] Proposal is not from an Aave space - skipping");
            return null;
          }
          
          const transformedProposal = transformSnapshotData(proposal, space);
          transformedProposal._cachedAt = Date.now();
          proposalCache.set(cacheKey, transformedProposal);
          setCachedProposalData(cacheKey, transformedProposal); // Save to localStorage
          return transformedProposal;
        } else {
          console.warn("⚠️ [SNAPSHOT] Format 1 failed, trying format 2 (proposal hash only)...");
          
          // Try format 2: Just the proposal hash
          const retryResponse2 = await fetchWithRetry(graphqlEndpoint, {
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
              
              // Validate that this is a valid Aave governance proposal (check space from API)
              if (!isValidAaveGovernanceProposal(retryResult2.data.proposal, space, isTestnet)) {
                console.warn("❌ [SNAPSHOT] Proposal is not from an Aave space - skipping");
                return null;
              }
              
              const transformedProposal = transformSnapshotData(retryResult2.data.proposal, space);
              transformedProposal._cachedAt = Date.now();
              proposalCache.set(cacheKey, transformedProposal);
              return transformedProposal;
            }
          }
          
          // Try format 3: With 's:' prefix
          if (space.startsWith('s:') && cleanSpace !== space) {
            console.warn("⚠️ [SNAPSHOT] Format 2 failed, trying format 3 (with 's:' prefix)...");
            const retryResponse3 = await fetchWithRetry(graphqlEndpoint, {
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
                
                // Validate that this is a valid Aave governance proposal (check space from API)
                if (!isValidAaveGovernanceProposal(retryResult3.data.proposal, space, isTestnet)) {
                  console.warn("❌ [SNAPSHOT] Proposal is not from an Aave space - skipping");
                  return null;
                }
                
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
        url: graphqlEndpoint,
        proposalId,
        isTestnet,
        fullError: error
      });
      
      // Provide specific guidance based on error type
      if (errorName === 'AbortError' || errorMessage.includes('aborted')) {
        console.error("❌ [SNAPSHOT] Request timed out after 10 seconds. The Snapshot API may be slow or unavailable.");
      } else if (errorName === 'TypeError' || errorMessage.includes('Failed to fetch')) {
        const isLocalhost = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';
        const isCorsError = errorMessage.includes('CORS') || errorMessage.includes('preflight') || 
                           errorMessage.includes('blocked');
        const currentOrigin = window.location.origin;
        
        console.error("❌ [SNAPSHOT] Network error - possible causes:");
        if (isCorsError && isTestnet) {
          console.error("   🔴 CORS policy blocking request to testnet.hub.snapshot.org");
          console.error(`   📝 Request origin: ${currentOrigin}`);
          console.error("   📝 This happens because:");
          console.error("      - testnet.hub.snapshot.org has restrictive CORS policies");
          console.error("      - It only allows requests from specific whitelisted domains");
          console.error("      - Custom Discourse domains are not whitelisted");
          console.error("   💡 Solutions:");
          if (isLocalhost) {
            console.error("      1. Use a CORS browser extension (e.g., 'CORS Unblock' for Chrome)");
            console.error("      2. Launch Chrome with: --disable-web-security --user-data-dir=/tmp/chrome_dev");
          }
          console.error("      3. Use production Snapshot proposals (snapshot.org) instead of testnet");
          console.error("      4. Contact Snapshot team to whitelist your domain");
          console.error("      5. Set up a backend proxy server to fetch Snapshot data");
        } else if (isLocalhost && (isCorsError || isTestnet)) {
          console.error("   🔴 CORS policy blocking request from localhost (common in local development)");
          console.error("   📝 This happens because:");
          console.error("      - Browser blocks cross-origin requests from localhost");
          console.error("      - testnet.hub.snapshot.org doesn't allow requests from localhost");
          console.error("      - This is a browser security feature, not a code bug");
          console.error("   💡 Solutions for local development:");
          console.error("      1. Use a CORS browser extension (e.g., 'CORS Unblock' for Chrome)");
          console.error("      2. Launch Chrome with: --disable-web-security --user-data-dir=/tmp/chrome_dev");
          console.error("      3. Test with production Snapshot proposals (snapshot.org) instead of testnet");
          console.error("      4. Set up a local CORS proxy server");
        } else {
          console.error("   - CORS policy blocking the request");
          console.error("   - Network connectivity issues");
          console.error("   - Snapshot API is temporarily unavailable");
          console.error("   - Browser security restrictions");
        }
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
        setCachedProposalData(cacheKey, result); // Save to localStorage
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
        setCachedProposalData(cacheKey, onChainResult); // Save to localStorage
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
      // Preserve rawContent from subgraph for discussion URL extraction
      if (subgraphMetadata.rawContent && !merged.rawContent) {
        merged.rawContent = subgraphMetadata.rawContent;
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
              rawContent
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
        } else if (p.transactions?.created?.timestamp) {
          // For "created" status, calculate: created timestamp + cooldown period = activation timestamp
          // This allows us to calculate the end date even before voting starts
          const createdTimestamp = Number(p.transactions.created.timestamp);
          const cooldown = p.votingConfig?.cooldownBeforeVotingStart ? Number(p.votingConfig.cooldownBeforeVotingStart) : 0;
          votingActivationTimestamp = createdTimestamp + cooldown;
          console.log("🔵 [AIP] Calculated votingActivationTimestamp from created: created (", createdTimestamp, ") + cooldown (", cooldown, ") =", votingActivationTimestamp);
        }
        
        // Calculate end date: votingActivationTimestamp + votingDuration
        // Then calculate daysLeft and hoursLeft
        // Use votingDuration from proposal or votingConfig as fallback
        const votingDuration = p.votingDuration || p.votingConfig?.votingDuration;
        
        if (votingActivationTimestamp && votingDuration) {
          const votingDurationNum = Number(votingDuration);
          const endTimestamp = votingActivationTimestamp + votingDurationNum;
          
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
          console.log("   votingActivationTimestamp:", votingActivationTimestamp, "votingDuration:", votingDuration, "p.votingDuration:", p.votingDuration, "p.votingConfig?.votingDuration:", p.votingConfig?.votingDuration);
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
          rawContent: p.proposalMetadata?.rawContent || null,
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
      const provider = new ethers.providers.JsonRpcProvider(ETH_RPC_URL);
      const governanceContract = new ethers.Contract(
        AAVE_GOVERNANCE_V3_ADDRESS,
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
          console.error("❌ [AIP] Contract:", AAVE_GOVERNANCE_V3_ADDRESS);
        }
        if (error.message?.includes("network") || error.message?.includes("timeout")) {
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
          setCachedProposalData(cacheKey, transformedProposal); // Save to localStorage
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
    // NOTE: Snapshot API doesn't provide a direct "result" field (Passed/Rejected)
    // We must calculate it from votes, matching Snapshot's frontend logic exactly:
    // - Closed with 0 votes → Rejected
    // - Closed with forVotes > againstVotes → Passed
    // - Closed with againstVotes >= forVotes → Rejected
    let status = 'unknown';
    if (proposal.state === 'active' || proposal.state === 'open') {
      status = 'active';
    } else if (proposal.state === 'closed') {
      // For closed proposals, determine result from votes (matches Snapshot website calculation)
      if (totalVotes === 0) {
        // Closed with 0 votes = Rejected (no one voted for it, like Snapshot website)
        status = 'rejected';
      } else if (forVotes > againstVotes) {
        // Majority support = Passed
        status = 'passed';
      } else {
        // Against votes >= For votes, or equal votes = Rejected
        status = 'rejected';
      }
    } else if (proposal.state === 'pending') {
      status = 'pending';
    } else {
      // Fallback: use state as-is if it's a valid status
      status = proposal.state || 'unknown';
    }
    
    console.log("🔵 [TRANSFORM] Proposal state:", proposal.state, "→ Final status:", status, "(calculated from votes:", { forVotes, againstVotes, totalVotes }, ")");
    
    // Calculate support percentage (For votes / Total votes)
    const supportPercent = totalVotes > 0 ? (forVotes / totalVotes) * 100 : 0;
    
    console.log("🔵 [TRANSFORM] Final support percent:", supportPercent);
    
    return {
      id: proposal.id,
      title: proposal.title || 'Untitled Proposal',
      description: proposal.body || '', // Used for display
      body: proposal.body || '', // Preserve raw body for cascading search
      discussion: proposal.discussion || null, // Discussion/reference link
      plugins: proposal.plugins || null, // Plugins (may contain discourse link)
      status,
      stage,
      space,
      daysLeft,
      hoursLeft,
      endTime,
      startTime: proposal.start || null, // Add start time for "pending" status (when voting hasn't started yet)
      supportPercent, // Add support percentage for easy access
      voteStats: {
        for: { count: forVotes, voters: 0, percent: forPercent },
        against: { count: againstVotes, voters: 0, percent: againstPercent },
        abstain: { count: abstainVotes, voters: 0, percent: abstainPercent },
        total: totalVotes
      },
      url: `https://snapshot.org/#/${space}/${proposal.id.split('/')[1]}`,
      type: 'snapshot', // Source type (snapshot vs aip)
      apiType: proposal.type || null, // Voting mechanism type from API (e.g., 'single-choice', 'approval', etc.)
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
      votingActivationTimestamp: proposal.votingActivationTimestamp || null, // Add for "created" status time calculation
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
            <strong>${isActive ? 'ACTIVE' : isExecuted ? 'EXECUTED' : 'INACTIVE'}</strong>
          </div>
          ${(() => {
            const statusLower = (proposalData.status || '').toLowerCase();
            const isPending = statusLower === 'pending';
            const isCreated = statusLower === 'created';
            const showVoteButton = totalVotes > 0 && !isPending && !isCreated;
            // If active, show "Vote", otherwise show "View"
            const buttonText = isActive ? 'Vote on Snapshot' : 'View on Snapshot';
            
            if (showVoteButton) {
              return `
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
                    ${buttonText}
                  </a>
                </div>
              `;
            } else {
              return `
                <a href="${originalUrl}" target="_blank" rel="noopener" class="vote-button">
                  View on Snapshot
                </a>
              `;
            }
          })()}
        </div>
      </div>
    `;
  }


  // Render status widget on the right side (outside post box) - like the image
  // Render multi-stage widget showing Temp Check, ARFC, and AIP all together
  // Get or create the widgets container for column layout
  // Detect if Discourse sidebar is collapsed
  function isSidebarCollapsed() {
    // Check common Discourse sidebar indicators
    const sidebar = document.querySelector('.sidebar-wrapper, .d-sidebar, .sidebar, nav.sidebar, .navigation-container');
    if (sidebar) {
      const computedStyle = window.getComputedStyle(sidebar);
      // Check if sidebar is hidden or collapsed
      if (computedStyle.display === 'none' || 
          computedStyle.visibility === 'hidden' ||
          computedStyle.width === '0px' ||
          sidebar.classList.contains('collapsed') ||
          sidebar.classList.contains('hidden') ||
          sidebar.hasAttribute('hidden')) {
        return true;
      }
      // Check body classes
      if (document.body.classList.contains('sidebar-collapsed') ||
          document.body.classList.contains('no-sidebar')) {
        return true;
      }
    } else {
      // No sidebar element found - assume collapsed
      return true;
    }
    return false;
  }

  // Determine if widget should be inline (top) or fixed (right side)
  function shouldShowWidgetInline() {
    const width = window.innerWidth;
    
    // Less than 1480px: always inline (top)
    if (width < 1480) {
      return true;
    }
    
    // Greater than 1780px: always fixed (right side)
    if (width > 1780) {
      return false;
    }
    
    // Between 1480px and 1780px: check sidebar state
    // If sidebar is collapsed: show on right side (fixed)
    // If sidebar is expanded: show on top (inline)
    const sidebarCollapsed = isSidebarCollapsed();
    return !sidebarCollapsed; // If sidebar is expanded, show inline; if collapsed, show fixed
  }

  // Returns container for large screens (fixed positioning), null for mobile (inline positioning)
  function getOrCreateWidgetsContainer() {
    // Check if widget should be inline or fixed based on screen width and sidebar state
    const shouldInline = shouldShowWidgetInline();
    if (shouldInline) {
      console.log("🔵 [CONTAINER] Inline positioning detected - skipping container creation");
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
      container.style.setProperty('position', 'fixed', 'important');
      container.style.setProperty('z-index', '500', 'important');
      container.style.setProperty('width', '320px', 'important');
      container.style.setProperty('max-width', '320px', 'important');
      container.style.setProperty('max-height', 'calc(100vh - 100px)', 'important');
      container.style.setProperty('overflow-y', 'auto', 'important');
      // Ensure container stays visible and fixed during scroll
      container.style.setProperty('visibility', 'visible', 'important');
      container.style.setProperty('opacity', '1', 'important');
      container.style.setProperty('display', 'flex', 'important');
      // Optimize for fixed positioning
      container.style.setProperty('will-change', 'transform', 'important');
      container.style.setProperty('backface-visibility', 'hidden', 'important');
      container.style.setProperty('transform', 'translateZ(0)', 'important');
      
      // Position container like tally widget - fixed on right side
      updateContainerPosition(container);
      
      // CRITICAL: Preserve scroll position when adding container to prevent auto-scrolling
      preserveScrollPosition(() => {
        document.body.appendChild(container);
      });
      console.log("✅ [CONTAINER] Created widgets container for column layout");
      
      // Update position on resize - handles desktop to mobile transitions
      let updateTimeout;
      const updatePosition = () => {
        clearTimeout(updateTimeout);
        updateTimeout = setTimeout(() => {
          if (container) {
            // Ensure container is still in DOM (re-append if needed)
            if (!container.parentNode) {
              console.log("🔵 [RESIZE] Container removed from DOM, re-appending...");
              document.body.appendChild(container);
            }
            
            // Always update position on resize (handles desktop ↔ mobile transitions)
            // This ensures widget stays visible when switching between screen sizes
            updateContainerPosition(container);
            
            // Also force visibility to prevent disappearing
            // Use a small delay to ensure DOM is ready after resize
            setTimeout(() => {
              ensureAllWidgetsVisible();
            }, 50);
          }
        }, 100);
      };
      
      // Update on resize to handle screen size changes (desktop ↔ mobile)
      window.addEventListener('resize', updatePosition);
      
      // Initial position update after a short delay to ensure DOM is ready
      setTimeout(() => updateContainerPosition(container), 100);
    }
    return container;
  }
  
  // Update container position - fixed on desktop, relative on mobile/tablet
  // CRITICAL: Only updates position/width when screen size or sidebar state changes, not on every call
  let lastScreenWidth = window.innerWidth;
  let lastSidebarCollapsed = null;
  function updateContainerPosition(container) {
    if (!container || !container.parentNode) {
      console.warn("⚠️ [POSITION] Container not in DOM, skipping position update");
      return;
    }
    
    const currentScreenWidth = window.innerWidth;
    const shouldInline = shouldShowWidgetInline();
    const currentSidebarCollapsed = isSidebarCollapsed();
    
    // Only update if screen size category or sidebar state changed to prevent width flickering
    const wasInline = lastScreenWidth < 1480 || (lastScreenWidth <= 1780 && lastSidebarCollapsed === false);
    if (shouldInline === wasInline && currentScreenWidth === lastScreenWidth && currentSidebarCollapsed === lastSidebarCollapsed) {
      // Screen size and sidebar state haven't changed, skip position update to prevent width changes
      return;
    }
    
    lastScreenWidth = currentScreenWidth;
    lastSidebarCollapsed = currentSidebarCollapsed;
    
    // Get all widgets from the container
    const widgets = Array.from(container.querySelectorAll('.tally-status-widget-container'));
    
    if (shouldInline) {
      // Mobile/Tablet: Move widgets from container to topic body (inline before first post)
      if (widgets.length > 0) {
        console.log(`🔵 [RESIZE] Moving ${widgets.length} widget(s) from container to topic body (mobile)`);
        
        const allPosts = Array.from(document.querySelectorAll('.topic-post, .post, [data-post-id], article[data-post-id]'));
        const firstPost = allPosts.length > 0 ? allPosts[0] : null;
        const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream, .topic-post-stream');
        
        // Sort widgets by order attribute to maintain correct order
        widgets.sort((a, b) => {
          const orderA = parseInt(a.getAttribute("data-proposal-order") || a.getAttribute("data-stage-order") || "999", 10);
          const orderB = parseInt(b.getAttribute("data-proposal-order") || b.getAttribute("data-stage-order") || "999", 10);
          return orderA - orderB;
        });
        
        // Move each widget to topic body (before first post)
        widgets.forEach((widget) => {
          // Update widget styles for mobile (inline positioning)
          widget.style.setProperty('position', 'relative', 'important');
          widget.style.setProperty('left', 'auto', 'important');
          widget.style.setProperty('right', 'auto', 'important');
          widget.style.setProperty('top', 'auto', 'important');
          widget.style.setProperty('width', '100%', 'important');
          widget.style.setProperty('max-width', '100%', 'important');
          widget.style.setProperty('margin-bottom', '20px', 'important');
          
          // Remove widget from container
          widget.remove();
          
          // Insert before first post
          if (firstPost && firstPost.parentNode) {
            // Find last widget before first post
            const siblings = Array.from(firstPost.parentNode.children);
            let insertBefore = firstPost;
            for (let i = siblings.indexOf(firstPost) - 1; i >= 0; i--) {
              if (siblings[i].classList.contains('tally-status-widget-container')) {
                insertBefore = siblings[i].nextSibling || firstPost;
                break;
              }
            }
            firstPost.parentNode.insertBefore(widget, insertBefore);
          } else if (topicBody) {
            // Fallback: append to topic body
            const widgetsInBody = Array.from(topicBody.querySelectorAll('.tally-status-widget-container'));
            if (widgetsInBody.length > 0) {
              const lastWidget = widgetsInBody[widgetsInBody.length - 1];
              if (lastWidget.nextSibling) {
                topicBody.insertBefore(widget, lastWidget.nextSibling);
              } else {
                topicBody.appendChild(widget);
              }
            } else {
              if (topicBody.firstChild) {
                topicBody.insertBefore(widget, topicBody.firstChild);
              } else {
                topicBody.appendChild(widget);
              }
            }
          }
        });
        
        console.log(`✅ [RESIZE] Moved ${widgets.length} widget(s) to topic body`);
      }
      
      // Hide/remove container on mobile (widgets are now inline)
      container.style.setProperty('display', 'none', 'important');
    } else {
      // Desktop: Move widgets from topic body back to container (fixed positioning)
      if (container.parentNode === document.body) {
        // Container is already in body, just ensure it's visible
        container.style.setProperty('display', 'flex', 'important');
      } else {
        // Container not in body, re-append it
        document.body.appendChild(container);
        container.style.setProperty('display', 'flex', 'important');
      }
      
      // Find widgets in topic body that should be in container
      const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream, .topic-post-stream');
      const firstPost = document.querySelector('.topic-post, .post, [data-post-id], article[data-post-id]');
      
      if (topicBody || firstPost) {
        // Get all widgets that are currently in topic body
        const widgetsInTopic = Array.from(document.querySelectorAll('.tally-status-widget-container'));
        const widgetsToMove = widgetsInTopic.filter(widget => {
          // Check if widget is in topic body (not in container)
          const parent = widget.parentNode;
          return parent && parent !== container && 
                 (parent === topicBody || 
                  (firstPost && parent.contains(firstPost)) ||
                  parent.classList.contains('posts-wrapper') ||
                  parent.classList.contains('post-stream') ||
                  parent.classList.contains('topic-post-stream'));
        });
        
        if (widgetsToMove.length > 0) {
          console.log(`🔵 [RESIZE] Moving ${widgetsToMove.length} widget(s) from topic body to container (desktop)`);
          
          // Sort widgets by order attribute to maintain correct order
          widgetsToMove.sort((a, b) => {
            const orderA = parseInt(a.getAttribute("data-proposal-order") || a.getAttribute("data-stage-order") || "999", 10);
            const orderB = parseInt(b.getAttribute("data-proposal-order") || b.getAttribute("data-stage-order") || "999", 10);
            return orderA - orderB;
          });
          
          // Move each widget to container
          widgetsToMove.forEach(widget => {
            // Update widget styles for desktop (fixed positioning in container)
            widget.style.setProperty('position', 'relative', 'important');
            widget.style.setProperty('left', 'auto', 'important');
            widget.style.setProperty('right', 'auto', 'important');
            widget.style.setProperty('top', 'auto', 'important');
            widget.style.setProperty('width', '100%', 'important');
            widget.style.setProperty('max-width', '100%', 'important');
            widget.style.setProperty('margin-bottom', '12px', 'important');
            
            widget.remove();
            container.appendChild(widget);
          });
          
          console.log(`✅ [RESIZE] Moved ${widgetsToMove.length} widget(s) to container`);
        }
      }
      
      // Desktop: Use fixed positioning (right side) - percentage-based like Tally widget
      container.style.setProperty('position', 'fixed', 'important');
      container.style.setProperty('z-index', '500', 'important');
      container.style.setProperty('right', '2%', 'important'); // Percentage-based distance from right edge
      container.style.setProperty('left', 'auto', 'important');
      container.style.setProperty('top', '180px', 'important');
      // CRITICAL: Keep width fixed at 320px to prevent width changes on scroll
      container.style.setProperty('width', '320px', 'important');
      container.style.setProperty('max-width', '320px', 'important');
      // Optimize for fixed positioning (prevent flickering during scroll)
      container.style.setProperty('will-change', 'transform', 'important');
      container.style.setProperty('backface-visibility', 'hidden', 'important');
      container.style.setProperty('transform', 'translateZ(0)', 'important');
    }
    
    // Always ensure visibility for widgets
    container.style.setProperty('visibility', 'visible', 'important');
    container.style.setProperty('opacity', '1', 'important');
    container.classList.remove('hidden', 'd-none', 'is-hidden');
    
    // Log position data for debugging
    const rect = container.getBoundingClientRect();
    console.log("📍 [POSITION DATA] Container position:", {
      shouldInline,
      widgetsInContainer: container.querySelectorAll('.tally-status-widget-container').length,
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

  // eslint-disable-next-line no-unused-vars
  function renderMultiStageWidget(stages, widgetId, proposalOrder = null, discussionLink = null, isRelated = true) {
    const statusWidgetId = `aave-governance-widget-${widgetId}`;
    
    // Determine widget type - if all stages are present, use 'combined', otherwise use specific type
    const hasSnapshotStages = stages.tempCheck || stages.arfc;
    const hasAllStages = hasSnapshotStages && stages.aip;
    const widgetType = hasAllStages ? 'combined' : (stages.aip ? 'aip' : 'snapshot');
    
    // Get the URL from stages to check for duplicates by URL (more reliable than ID)
    const proposalUrl = stages.aipUrl || stages.arfcUrl || stages.tempCheckUrl || null;
    
    // CRITICAL: Remove loading placeholder if it exists (replace with actual widget)
    // Remove by URL (more reliable than ID since widgetId might differ)
    // Use normalized URL comparison to catch variations
    if (proposalUrl) {
      const normalizeUrlForComparison = (urlToNormalize) => {
        if (!urlToNormalize) {
          return '';
        }
        return urlToNormalize.trim()
          .replace(/\/+$/, '')
          .split('?')[0]
          .split('#')[0]
          .toLowerCase();
      };
      
      const normalizedProposalUrl = normalizeUrlForComparison(proposalUrl);
      
      // Find and remove all placeholders that match this URL (exact or normalized)
      const allPlaceholders = document.querySelectorAll('.loading-placeholder[data-tally-url]');
      let removedCount = 0;
      allPlaceholders.forEach(placeholder => {
        const placeholderUrl = placeholder.getAttribute('data-tally-url');
        if (!placeholderUrl) {
          return;
        }
        
        const normalizedPlaceholderUrl = normalizeUrlForComparison(placeholderUrl);
        
        // Check if URLs match (exact match or normalized match)
        if (placeholderUrl === proposalUrl || normalizedPlaceholderUrl === normalizedProposalUrl) {
          console.log(`✅ [LOADING] Removing loading placeholder for ${proposalUrl} (found: ${placeholderUrl})`);
          placeholder.remove();
          removedCount++;
        }
      });
      
      // Also try removing by widgetId as fallback
      const placeholderById = document.getElementById(`loading-placeholder-${widgetId}`);
      if (placeholderById && placeholderById.classList.contains('loading-placeholder')) {
        console.log(`✅ [LOADING] Removing loading placeholder by ID for ${widgetId}`);
        placeholderById.remove();
        removedCount++;
      }
      
      if (removedCount === 0) {
        console.log(`🔵 [LOADING] No loading placeholder found to remove for ${proposalUrl}`);
      }
    }
    
    // Check for existing widgets with the same URL to prevent duplicates
    // This allows multiple proposals of the same type (e.g., 2 AIP proposals) to be shown separately
    // Only widgets with the same URL are considered duplicates, not all widgets of the same type
    if (proposalUrl) {
      const existingWidgetsByUrl = document.querySelectorAll(`.tally-status-widget-container[data-tally-url="${proposalUrl}"]:not(.loading-placeholder)`);
      if (existingWidgetsByUrl.length > 0) {
        console.log(`🔵 [RENDER] Found ${existingWidgetsByUrl.length} existing widget(s) with same URL, skipping duplicate render`);
        // Clean up tracking for these widgets
        existingWidgetsByUrl.forEach(widget => {
          const widgetUrl = widget.getAttribute('data-tally-url');
          if (widgetUrl) {
            renderingUrls.delete(widgetUrl);
            fetchingUrls.delete(widgetUrl);
          }
        });
        return;
      }
    }
    
    // CRITICAL: Check if this URL is already being rendered (race condition prevention)
    if (proposalUrl && renderingUrls.has(proposalUrl)) {
      console.log(`🔵 [RENDER] URL ${proposalUrl} is already being rendered, skipping duplicate render`);
      return;
    }
    
    // Mark this URL as being rendered (both normalized and original for compatibility)
    if (proposalUrl) {
      const normalizedUrl = normalizeAIPUrl(proposalUrl);
      renderingUrls.add(normalizedUrl);
      renderingUrls.add(proposalUrl); // Also add original for backward compatibility
    }
    
    // CRITICAL: Check for existing widget by URL first (more reliable than ID)
    // This prevents duplicate widgets when the same URL is rendered multiple times
    let statusWidget = null;
    let isUpdatingInPlace = false;
    
    if (proposalUrl) {
      const normalizedUrl = normalizeAIPUrl(proposalUrl);
      const existingWidgetByUrl = document.querySelector(`.tally-status-widget-container[data-tally-url="${proposalUrl}"], .tally-status-widget-container[data-tally-url="${normalizedUrl}"]`);
      if (existingWidgetByUrl) {
        // CRITICAL: Always update in place when URL matches (even if ID differs)
        // This prevents blinking by updating existing widget instead of removing/recreating
        // The ID might differ if widget was created with different ID format, but URL match is what matters
        statusWidget = existingWidgetByUrl;
        isUpdatingInPlace = true;
        
        // Update the widget's ID to match the expected ID (for consistency)
        if (existingWidgetByUrl.id !== statusWidgetId) {
          console.log(`🔵 [RENDER] Widget found by URL with different ID (${existingWidgetByUrl.id} vs ${statusWidgetId}), updating ID and content in place to prevent blinking`);
          existingWidgetByUrl.id = statusWidgetId;
        } else {
          console.log(`🔵 [RENDER] Widget ${statusWidgetId} already exists, updating in place to prevent blinking`);
        }
      }
    }
    
    // Check if widget already exists by ID (fallback check)
    if (!statusWidget) {
      const existingWidget = document.getElementById(statusWidgetId);
      if (existingWidget) {
        // Also check if URL matches (to prevent re-rendering same widget)
        const existingUrl = existingWidget.getAttribute('data-tally-url');
        const normalizedExistingUrl = existingUrl ? normalizeAIPUrl(existingUrl) : null;
        const normalizedProposalUrl = proposalUrl ? normalizeAIPUrl(proposalUrl) : null;
        const urlMatches = !proposalUrl || existingUrl === proposalUrl || normalizedExistingUrl === normalizedProposalUrl;
        
        // Update in place if URL matches (prevents blinking)
        if (urlMatches && existingWidget.parentNode) {
          statusWidget = existingWidget;
          isUpdatingInPlace = true;
          console.log(`🔵 [RENDER] Widget ${statusWidgetId} already exists, updating in place to prevent blinking`);
        } else {
          // URL or order changed - need to remove and recreate
          existingWidget.remove();
          console.log(`🔵 [RENDER] Removed existing widget with ID: ${statusWidgetId} (order or URL changed)`);
        }
      }
    }
    
    console.log(`🔵 [RENDER] Rendering ${widgetType} widget with stages:`, {
      tempCheck: !!stages.tempCheck,
      arfc: !!stages.arfc,
      aip: !!stages.aip,
      isUpdatingInPlace
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
    
    // Only create new widget if we're not updating in place
    if (!statusWidget) {
      statusWidget = document.createElement("div");
      statusWidget.id = statusWidgetId;
      statusWidget.className = "tally-status-widget-container";
    }
    
    // Set/update attributes for both new and existing widgets
    statusWidget.setAttribute("data-widget-id", widgetId);
    statusWidget.setAttribute("data-widget-type", widgetType); // Mark widget type
    
    // CRITICAL: Prevent Discourse's viewport tracker from hiding this widget
    // Discourse uses data-cloak and other attributes to hide elements on scroll
    // Exclude widget from viewport tracking entirely
    statusWidget.setAttribute("data-cloak", "false"); // Disable cloaking
    statusWidget.setAttribute("data-skip-cloak", "true"); // Alternative attribute
    statusWidget.setAttribute("data-no-cloak", "true"); // Another alternative
    statusWidget.setAttribute("data-viewport", "false"); // Exclude from viewport tracking
    statusWidget.setAttribute("data-exclude-viewport", "true"); // Explicit exclusion
    // Add class to exclude from viewport tracking via CSS
    statusWidget.classList.add("no-viewport-track");
    
    // Add URL attribute for duplicate detection
    if (proposalUrl) {
      statusWidget.setAttribute("data-tally-url", proposalUrl);
      // Mark testnet widgets explicitly to ensure same treatment as production
      if (proposalUrl.includes('testnet.snapshot.box')) {
        statusWidget.setAttribute("data-is-testnet", "true");
      }
    }
    // Add proposal type for filtering
    const proposalType = stages.aip ? 'aip' : 'snapshot';
    statusWidget.setAttribute("data-proposal-type", proposalType);
    
    // CRITICAL: Force immediate visibility for all widgets (including testnet)
    // Same behavior as production - no scroll-based lazy loading
    statusWidget.style.display = 'block';
    statusWidget.style.visibility = 'visible';
    statusWidget.style.opacity = '1';
    
    // CRITICAL: Mark widget as visible in cache immediately when created
    // This prevents unnecessary visibility checks during scroll
    markWidgetAsVisibleInCache(statusWidget);
    
    // Use proposal order (order in content) for positioning, fallback to stage order
    // Proposal order takes precedence - widgets appear in the order proposals appear in content
    const orderValue = proposalOrder !== null ? proposalOrder : 
      (hasAllStages ? 3 : (stages.tempCheck && !stages.arfc && !stages.aip ? 1 : 
      (stages.arfc && !stages.aip ? 2 : 3)));
    
    // Set both attributes for compatibility
    statusWidget.setAttribute("data-proposal-order", orderValue);
    statusWidget.setAttribute("data-stage-order", orderValue); // Keep for backward compatibility
    
    // Set CSS order property to ensure consistent ordering across all screen sizes
    // This ensures widgets appear in the same order (first proposal first, second second, etc.)
    // regardless of screen size (mobile, tablet, desktop)
    statusWidget.style.order = orderValue;
    statusWidget.style.setProperty('--proposal-order', orderValue);
    
    // Helper function to format time display
    function formatTimeDisplay(daysLeft, hoursLeft, status = null, endTimestamp = null) {
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
        // Check if hoursLeft is negative (proposal has ended)
        if (hoursLeft < 0) {
          return 'Ended Today';
        }
        // If hoursLeft is 0, show exact time instead of "Ends in 0 hours"
        if (hoursLeft === 0 && endTimestamp) {
          const endDate = new Date(endTimestamp);
          if (!isNaN(endDate.getTime())) {
            const exactTime = endDate.toLocaleTimeString('en-US', {
              hour: 'numeric',
              minute: '2-digit',
              hour12: true
            });
            return `Ends at ${exactTime}`;
          }
        }
        return `Ends in ${hoursLeft} ${hoursLeft === 1 ? 'hour' : 'hours'}!`;
      }
      if (daysLeft === 0) {
        // If daysLeft is 0 but we don't have hoursLeft, check status to determine if ended
        const statusLower = (status || '').toLowerCase();
        const endedStatuses = ['closed', 'ended', 'passed', 'executed', 'rejected', 'defeated', 'failed', 'cancelled', 'expired'];
        if (endedStatuses.includes(statusLower)) {
          return 'Ended Today';
        }
        // If status indicates it's still active, show "Ends today"
        const activeStatuses = ['active', 'open', 'pending', 'created'];
        if (activeStatuses.includes(statusLower)) {
          return 'Ends today';
        }
        // Default to "Ended Today" to be safe (avoids confusion)
        return 'Ended Today';
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
    
    // Helper function to format "Voting starts in X" for created proposals
    // Returns object with relative time and exact date/time
    // Only shows exact time when minutes are included in the relative text
    function formatVotingStartTime(votingActivationTimestamp) {
      if (!votingActivationTimestamp) {
        return { relative: '', exact: null, showExact: false };
      }
      
      const now = Date.now() / 1000; // Current time in seconds
      const activationTime = Number(votingActivationTimestamp); // Activation time in seconds
      const diffTime = activationTime - now; // Time until activation in seconds
      
      // Format exact date/time
      const activationDate = new Date(activationTime * 1000);
      const exactDate = activationDate.toLocaleDateString('en-US', { 
        month: 'short', 
        day: 'numeric', 
        year: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true
      });
      
      if (diffTime <= 0) {
        return { relative: '', exact: exactDate, showExact: false };
      }
      
      const diffTimeMs = diffTime * 1000; // Convert to milliseconds
      const diffTimeInDays = diffTimeMs / (1000 * 60 * 60 * 24);
      const diffTimeInHours = diffTimeMs / (1000 * 60 * 60);
      const diffTimeInMinutes = diffTimeMs / (1000 * 60);
      
      let relativeText;
      let showExact = false; // Only show exact time when minutes are shown
      
      // If less than 1 hour, show minutes - show exact time
      if (diffTimeInHours < 1) {
        const minutes = Math.floor(diffTimeInMinutes);
        relativeText = `Voting starts in ${minutes} ${minutes === 1 ? 'minute' : 'minutes'}`;
        showExact = true; // Show exact time when showing minutes
      }
      // If less than 24 hours, show hours AND minutes - show exact time
      else if (diffTimeInDays < 1) {
        const hours = Math.floor(diffTimeInHours);
        const remainingMinutes = Math.floor((diffTimeInHours - hours) * 60);
        if (remainingMinutes > 0) {
          relativeText = `Voting starts in ${hours} ${hours === 1 ? 'hour' : 'hours'} ${remainingMinutes} ${remainingMinutes === 1 ? 'minute' : 'minutes'}`;
        } else {
          relativeText = `Voting starts in ${hours} ${hours === 1 ? 'hour' : 'hours'}`;
        }
        showExact = true; // Always show exact time when showing hours (with or without minutes)
      }
      // If less than 30 days, show days (and hours if applicable, and minutes if less than a day)
      else if (diffTimeInDays < 30) {
        const days = Math.floor(diffTimeInDays);
        const remainingHours = Math.floor((diffTimeInDays - days) * 24);
        const remainingMinutes = Math.floor(((diffTimeInDays - days) * 24 - remainingHours) * 60);
        
        if (remainingHours > 0 && days === 0) {
          // Less than 1 day, show hours and minutes
          if (remainingMinutes > 0) {
            relativeText = `Voting starts in ${remainingHours} ${remainingHours === 1 ? 'hour' : 'hours'} ${remainingMinutes} ${remainingMinutes === 1 ? 'minute' : 'minutes'}`;
          } else {
            relativeText = `Voting starts in ${remainingHours} ${remainingHours === 1 ? 'hour' : 'hours'}`;
          }
          showExact = true; // Show exact time when showing hours/minutes
        } else if (remainingHours > 0) {
          // Multiple days with hours
          relativeText = `Voting starts in ${days} ${days === 1 ? 'day' : 'days'}, ${remainingHours} ${remainingHours === 1 ? 'hour' : 'hours'}`;
          showExact = false; // Don't show exact time for days + hours
        } else {
          relativeText = `Voting starts in ${days} ${days === 1 ? 'day' : 'days'}`;
          showExact = false; // Don't show exact time for days only
        }
      }
      // If 30+ days, show months
      else {
        const months = Math.floor(diffTimeInDays / 30);
        const remainingDays = Math.floor(diffTimeInDays % 30);
        if (remainingDays > 0) {
          relativeText = `Voting starts in ${months} ${months === 1 ? 'month' : 'months'}, ${remainingDays} ${remainingDays === 1 ? 'day' : 'days'}`;
        } else {
          relativeText = `Voting starts in ${months} ${months === 1 ? 'month' : 'months'}`;
        }
        showExact = false; // Don't show exact time for months/days
      }
      
      return { relative: relativeText, exact: exactDate, showExact };
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
      
      // Use case-insensitive comparison for all status checks
      const statusLower = (stageData.status || '').toLowerCase();
      
      const isActive = statusLower === 'active' || statusLower === 'open';
      const isPending = statusLower === 'pending';
      const isCreated = statusLower === 'created';
      const isPassed = statusLower === 'passed' || 
                       statusLower === 'closed' || 
                       (statusLower === 'executed' && supportPercent > 50) ||
                       (statusLower !== 'active' && statusLower !== 'open' && statusLower !== 'pending' && supportPercent > 50);
      
      // Determine if ended - includes passed, closed, executed, and other ended statuses, or daysLeft < 0
      // Use case-insensitive comparison for status
      const isEnded = (stageData.daysLeft !== null && stageData.daysLeft < 0) ||
                      statusLower === 'executed' || 
                      statusLower === 'passed' ||
                      statusLower === 'closed' ||
                      statusLower === 'queued' ||
                      statusLower === 'failed' ||
                      statusLower === 'cancelled' ||
                      statusLower === 'expired';
      
      // For ended proposals, show result status (Passed/Rejected/Defeated) instead of generic "Closed" or "Ended"
      // since we're already showing "Ended today/X days ago" in the time display
      let statusBadgeText;
      if (isEnded) {
        // Check for explicit result statuses first
        if (statusLower === 'rejected' || statusLower === 'defeated') {
          statusBadgeText = 'Rejected';
        } else if (statusLower === 'passed') {
          statusBadgeText = 'Passed';
        } else if (statusLower === 'closed' || (stageData.daysLeft !== null && stageData.daysLeft < 0)) {
          // For "closed" or time-ended proposals, determine result from votes (like Snapshot website)
          if (totalVotes > 0 && forVotes > againstVotes) {
            statusBadgeText = 'Passed';
          } else if (totalVotes > 0 && againstVotes >= forVotes) {
            statusBadgeText = 'Rejected';
          } else if (totalVotes === 0) {
            // Closed with 0 votes = Rejected (no one voted for it, like Snapshot website)
            statusBadgeText = 'Rejected';
          } else {
            // Can't determine - show "Closed"
            statusBadgeText = 'Closed';
          }
        } else {
          // For other ended statuses (executed, queued, failed, cancelled, expired), show the status
          statusBadgeText = stageData.status 
            ? (stageData.status.charAt(0).toUpperCase() + stageData.status.slice(1).toLowerCase())
            : 'Ended';
        }
      } else {
        // For non-ended proposals, show exact status from API
        statusBadgeText = stageData.status 
          ? (stageData.status.charAt(0).toUpperCase() + stageData.status.slice(1).toLowerCase())
          : 'Unknown';
      }
      
      // Determine statusClass for styling - handle rejected/failed/defeated to show red color
      const isRejectedOrDefeated = statusLower === 'rejected' || statusLower === 'defeated' || statusLower === 'failed' || statusBadgeText === 'Rejected';
      const statusClass = isPassed ? 'executed' : 
                         (isRejectedOrDefeated ? 'rejected' : 
                         (isActive ? 'active' : 
                         (isPending ? 'pending' : 
                         (isCreated ? 'created' : 'inactive'))));
      
      // For "pending" status, show time until voting starts instead of time until voting ends
      let timeDisplay;
      if (isPending && stageData.startTime) {
        const startTimeInfo = formatVotingStartTime(stageData.startTime);
        timeDisplay = startTimeInfo.relative;
      } else {
        // Calculate end timestamp if needed (for showing exact time when hoursLeft === 0)
        let endTimestamp = stageData.endTimestamp || stageData.endTime || null;
        if (!endTimestamp && stageData.daysLeft !== null && stageData.hoursLeft !== null) {
          // Calculate approximate end timestamp from current time + daysLeft + hoursLeft
          const now = Date.now();
          const endTimeMs = now + (stageData.daysLeft * 24 * 60 * 60 * 1000) + (stageData.hoursLeft * 60 * 60 * 1000);
          endTimestamp = endTimeMs;
        }
        timeDisplay = formatTimeDisplay(stageData.daysLeft, stageData.hoursLeft, stageData.status, endTimestamp);
      }
      
      // Calculate percentages for progress bar
      const forPercent = totalVotes > 0 ? (forVotes / totalVotes) * 100 : 0;
      const againstPercent = totalVotes > 0 ? (againstVotes / totalVotes) * 100 : 0;
      const abstainPercent = totalVotes > 0 ? (abstainVotes / totalVotes) * 100 : 0;
      
      // For cancelled and failed proposals, voting never happened - don't show vote data or progress bar
      const isCancelledOrFailed = statusLower === 'cancelled' || statusLower === 'failed';
      
      // Progress bar HTML - always show, even if 0 votes
      // EXCEPT: cancelled/failed - don't show progress bar
      const progressBarHtml = !isCancelledOrFailed ? `
        <div class="progress-bar-container" style="margin-top: 8px; margin-bottom: 8px;">
          <div class="progress-bar">
            ${forPercent > 0 ? `<div class="progress-segment progress-for" style="width: ${forPercent}%"></div>` : ''}
            ${againstPercent > 0 ? `<div class="progress-segment progress-against" style="width: ${againstPercent}%"></div>` : ''}
            ${abstainPercent > 0 ? `<div class="progress-segment progress-abstain" style="width: ${abstainPercent}%"></div>` : ''}
          </div>
        </div>
      ` : '';
      
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
      // Always show vote data for all statuses (created, active, ended, passed, etc.), even if 0 votes
      // EXCEPT: cancelled/failed - don't show vote data
      // Show "0" for For/Against/Abstain when there are no votes
      const displayFor = totalVotes > 0 ? formatVoteAmount(forVotes) : '0';
      const displayAgainst = totalVotes > 0 ? formatVoteAmount(againstVotes) : '0';
      const displayAbstain = totalVotes > 0 ? formatVoteAmount(abstainVotes) : '0';
      const shouldShowVoteCounts = !isPending && !isCreated && !isCancelledOrFailed; // Show vote counts for all statuses except pending/created/cancelled/failed
      const collapsedContent = isEnded ? `
        <div class="stage-collapsed-content" id="${stageId}-content" style="display: none;">
          ${progressBarHtml}
          ${shouldShowVoteCounts ? `
            <div style="margin-top: 4px; margin-bottom: 8px; font-size: 0.85em; line-height: 1.5; color: #6b7280;">
              <strong style="color: #10b981;">For: ${displayFor}</strong> | 
              <strong style="color: #ef4444;">Against: ${displayAgainst}</strong> | 
              <strong style="color: #6b7280;">Abstain: ${displayAbstain}</strong>
            </div>
          ` : (isCreated && !isEnded) ? `
            <div style="margin-top: 4px; margin-bottom: 8px; font-size: 0.85em; line-height: 1.5; color: #6b7280;">
              Voting Starting Soon
            </div>
          ` : ''}
        <a href="${stageUrl}" target="_blank" rel="noopener" class="vote-button" style="display: block; width: 100%; min-width: 100%; max-width: 100%; padding: 8px 12px; margin-top: 10px; margin-left: 0; margin-right: 0; box-sizing: border-box; border: none; border-radius: 4px; background-color: #e5e7eb !important; font-size: 0.85em; font-weight: 600; text-align: center; text-decoration: none; color: #6b7280 !important;">
            View on Snapshot
          </a>
        </div>
      ` : `
        ${progressBarHtml}
        ${shouldShowVoteCounts ? `
          <div style="margin-top: 4px; margin-bottom: 8px; font-size: 0.85em; line-height: 1.5; color: #6b7280;">
            <strong style="color: #10b981;">For: ${displayFor}</strong> | 
            <strong style="color: #ef4444;">Against: ${displayAgainst}</strong> | 
            <strong style="color: #6b7280;">Abstain: ${displayAbstain}</strong>
          </div>
        ` : (isCreated && !isEnded) ? `
          <div style="margin-top: 4px; margin-bottom: 8px; font-size: 0.85em; line-height: 1.5; color: #6b7280;">
            Voting Starting Soon
          </div>
        ` : ''}
        <a href="${stageUrl}" target="_blank" rel="noopener" class="vote-button" style="display: block; width: 100%; min-width: 100%; max-width: 100%; padding: 8px 12px; margin-top: 10px; margin-left: 0; margin-right: 0; box-sizing: border-box; border: none; border-radius: 4px; background-color: var(--d-button-primary-bg-color, #2563eb) !important; font-size: 0.85em; font-weight: 600; text-align: center; text-decoration: none; color: var(--d-button-primary-text-color, white) !important;">
          ${isPending || isCreated ? 'View on Snapshot' : 'Vote on Snapshot'}
        </a>
      `;
      
      return `
        <div class="governance-stage ${isEnded ? 'stage-ended' : ''}">
          <div style="display: flex; justify-content: space-between; align-items: center; padding-right: 32px; margin-bottom: 8px; font-size: 0.9em; font-weight: 600; color: #111827;">
            <span>${stageName} (Snapshot)</span>
            <div style="display: flex; align-items: center; gap: 8px;">
              <div class="status-badge ${statusClass}">
                <strong>${statusBadgeText}</strong>
              </div>
            </div>
          </div>
          ${endedText || (!isEnded && timeDisplay) ? `
            <div style="margin-bottom: 12px;">
              <div class="days-left-badge" style="padding: 4px 10px 4px 0; border-radius: 4px; font-size: 0.7em; font-weight: 600; white-space: nowrap; color: #6b7280;">
                ${endedText || timeDisplay}
              </div>
            </div>
          ` : ''}
          ${isEnded ? `
            <div id="${stageId}-collapse-container" style="display: flex; align-items: center; gap: 4px; margin-bottom: 8px; font-size: 0.8em; font-style: italic; line-height: 1.4; color: #9ca3af;">
              <button class="stage-toggle-btn" data-stage-id="${stageId}" style="display: flex; align-items: center; justify-content: center; flex-shrink: 0; width: 18px; height: 18px; padding: 0; margin: 0; border: none; border-radius: 4px; background: transparent; cursor: pointer; transition: all 0.2s; font-size: 14px; color: #6b7280;" title="Click to expand">
                <span id="${stageId}-icon">▶</span>
              </button>
              <span id="${stageId}-collapsed-text" style="flex: 1;">View Result</span>
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
      // Use case-insensitive comparison for status checks
      const statusLower = (stageData.status || '').toLowerCase();
      
      // Map status to CSS class for styling (use case-insensitive comparison)
      // "passed" means proposal passed voting but hasn't been executed yet (different from "executed")
      const statusClass = statusLower === 'active' ? 'active' : 
                         statusLower === 'created' ? 'created' :
                         statusLower === 'executed' ? 'executed' :
                         statusLower === 'passed' ? 'passed' :
                         statusLower === 'queued' ? 'queued' :
                         (statusLower === 'rejected' || statusLower === 'defeated') ? 'rejected' :
                         statusLower === 'failed' ? 'failed' :
                         statusLower === 'cancelled' ? 'cancelled' :
                         statusLower === 'expired' ? 'expired' : 'inactive';
      
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
      
      // For "created" status, show time until voting starts instead of time until voting ends
      let timeDisplay;
      if (status === 'created' && stageData.votingActivationTimestamp) {
        const startTimeInfo = formatVotingStartTime(stageData.votingActivationTimestamp);
        timeDisplay = startTimeInfo.relative;
      } else {
        // Calculate end timestamp if needed (for showing exact time when hoursLeft === 0)
        let endTimestamp = stageData.endTimestamp || stageData.endTime || null;
        if (!endTimestamp && stageData.daysLeft !== null && stageData.hoursLeft !== null) {
          // Calculate approximate end timestamp from current time + daysLeft + hoursLeft
          const now = Date.now();
          const endTimeMs = now + (stageData.daysLeft * 24 * 60 * 60 * 1000) + (stageData.hoursLeft * 60 * 60 * 1000);
          endTimestamp = endTimeMs;
        }
        timeDisplay = formatTimeDisplay(stageData.daysLeft, stageData.hoursLeft, stageData.status, endTimestamp);
      }
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
      // Use case-insensitive comparison for status (statusLower already declared at line 3370)
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
      
      // For ended AIP proposals, show result status (Passed/Rejected/Defeated/Executed/Queued) instead of generic "Ended"
      // since we're already showing "Ended today/X days ago" in the time display
      let statusBadgeText;
      if (isEnded) {
        // For ended proposals, show the actual status (Passed, Executed, Queued, Failed, Cancelled, etc.)
        // Don't show generic "Ended" since we show "Ended today/X days ago" in time display
        if (statusLower === 'rejected' || statusLower === 'defeated') {
          statusBadgeText = 'Rejected';
        } else {
          // For passed, executed, queued, failed, cancelled, expired - show the status as-is
          statusBadgeText = status.charAt(0).toUpperCase() + status.slice(1).toLowerCase();
        }
      } else {
        // For non-ended proposals, show exact status from API
        statusBadgeText = status.charAt(0).toUpperCase() + status.slice(1).toLowerCase();
      }
      
      // For cancelled and failed proposals, voting never happened - don't show vote data or progress bar
      const isCancelledOrFailed = statusLower === 'cancelled' || statusLower === 'failed';
      
      // Define status flags for button text logic (use case-insensitive comparison)
      // Must be declared before use in shouldShowVoteCounts
      const isActive = statusLower === 'active' || statusLower === 'open';
      const isPending = statusLower === 'pending';
      const isCreated = statusLower === 'created';
      
      // Always show vote data for all statuses (created, active, ended, passed, etc.), even if 0 votes
      // EXCEPT: cancelled/failed - don't show vote data or progress bar
      // Show "0" for For/Against when there are no votes
      const displayForAIP = totalVotes > 0 ? formatVoteAmount(forVotes) : '0';
      const displayAgainstAIP = totalVotes > 0 ? formatVoteAmount(againstVotes) : '0';
      const shouldShowVoteCounts = !isPending && !isCreated && !isCancelledOrFailed; // Show vote counts for all statuses except pending/created/cancelled/failed
      
      // Progress bar HTML - For AIP: show For/Against votes, no abstain
      // Always show progress bar, even if 0 votes
      // EXCEPT: cancelled/failed - don't show progress bar
      const progressBarHtml = !isCancelledOrFailed ? `
        <div class="progress-bar-container" style="margin-top: 8px; margin-bottom: 8px;">
          <div class="progress-bar">
            ${forPercent > 0 ? `<div class="progress-segment progress-for" style="width: ${forPercent}%"></div>` : ''}
            ${againstPercent > 0 ? `<div class="progress-segment progress-against" style="width: ${againstPercent}%"></div>` : ''}
          </div>
        </div>
      ` : '';
      
      // Quorum display for AIP (instead of abstain)
      // Show quorum if available and votes exist (or for ended/passed proposals)
      const quorumHtml = (quorum > 0 && shouldShowVoteCounts) ? `
        <div style="padding: 8px; margin-top: 8px; margin-bottom: 8px; border-left: 3px solid ${quorumReached ? '#10b981' : '#ef4444'}; border-radius: 4px; background: ${quorumReached ? '#f0fdf4' : '#fef2f2'}; font-size: 0.85em; color: #6b7280;">
          <strong style="color: #111827;">Quorum:</strong> ${formatVoteAmount(totalVotes)} / ${formatVoteAmount(quorum)} AAVE 
          <span style="font-weight: 600; color: ${quorumReached ? '#10b981' : '#ef4444'};">
            (${Math.round(quorumPercent)}% - ${quorumReached ? '✓ Reached' : '✗ Not Reached'})
          </span>
        </div>
      ` : '';
      
      // For ended proposals, wrap in collapsible container
      const stageId = `stage-aip-${Date.now()}`;
      const collapsedContent = isEnded ? `
        <div class="stage-collapsed-content" id="${stageId}-content" style="display: none;">
          ${progressBarHtml}
          ${shouldShowVoteCounts ? `
            <div style="font-size: 0.85em; color: #6b7280; margin-top: 4px; margin-bottom: 8px; line-height: 1.5;">
              <strong style="color: #10b981;">For: ${displayForAIP}</strong> | 
              <strong style="color: #ef4444;">Against: ${displayAgainstAIP}</strong>
            </div>
          ` : (stageData.status === 'active' && !votesAvailable) ? `
            <div style="font-size: 0.85em; color: #6b7280; margin-top: 4px; margin-bottom: 8px; line-height: 1.5;">
              Data will be available soon
            </div>
          ` : `
            <div style="font-size: 0.85em; color: #9ca3af; margin-top: 4px; margin-bottom: 8px; line-height: 1.5; font-style: italic;">
              Vote data not available from subgraph
            </div>
          `}
          ${quorumHtml}
          <a href="${stageUrl}" target="_blank" rel="noopener" class="vote-button" style="display: block; width: 100%; min-width: 100%; max-width: 100%; padding: 8px 12px; margin-top: 10px; margin-left: 0; margin-right: 0; box-sizing: border-box; border: none; border-radius: 4px; background-color: #e5e7eb !important; font-size: 0.85em; font-weight: 600; text-align: center; text-decoration: none; color: #6b7280 !important;">
            View on Aave
          </a>
        </div>
      ` : `
        ${progressBarHtml}
        ${shouldShowVoteCounts ? `
          <div style="font-size: 0.85em; color: #6b7280; margin-top: 4px; margin-bottom: 8px; line-height: 1.5;">
            <strong style="color: #10b981;">For: ${displayForAIP}</strong> | 
            <strong style="color: #ef4444;">Against: ${displayAgainstAIP}</strong>
          </div>
        ` : (stageData.status === 'active' && !votesAvailable) ? `
          <div style="font-size: 0.85em; color: #6b7280; margin-top: 4px; margin-bottom: 8px; line-height: 1.5;">
            Data will be available soon
          </div>
        ` : `
          <div style="font-size: 0.85em; color: #9ca3af; margin-top: 4px; margin-bottom: 8px; line-height: 1.5; font-style: italic;">
            Vote data not available from subgraph
          </div>
        `}
        ${quorumHtml}
        <a href="${stageUrl}" target="_blank" rel="noopener" class="vote-button" style="display: block; width: 100%; min-width: 100%; max-width: 100%; padding: 8px 12px; margin-top: 10px; margin-left: 0; margin-right: 0; box-sizing: border-box; border: none; border-radius: 4px; background-color: var(--d-button-primary-bg-color, #2563eb) !important; font-size: 0.85em; font-weight: 600; text-align: center; text-decoration: none; color: var(--d-button-primary-text-color, white) !important;">
          ${isActive && !isPending && !isCreated ? 'Vote on Aave' : 'View on Aave'}
        </a>
      `;
      
      return `
        <div class="governance-stage ${isEnded ? 'stage-ended' : ''}">
          <div style="display: flex; justify-content: space-between; align-items: center; padding-right: 32px; margin-bottom: 8px; font-size: 0.9em; font-weight: 600; color: #111827;">
            <span>AIP (On-Chain) ${aipNumber}</span>
            <div style="display: flex; align-items: center; gap: 8px;">
              <div class="status-badge ${statusClass}">
                <strong>${statusBadgeText}</strong>
              </div>
            </div>
          </div>
          ${(endDateText && endDateText !== 'Ended') || (!isEnded && timeDisplay) ? `
            <div style="margin-bottom: 12px;">
              <div class="days-left-badge" style="padding: 4px 10px 4px 0; border-radius: 4px; font-size: 0.7em; font-weight: 600; color: #6b7280; white-space: nowrap;">
                ${endDateText && endDateText !== 'Ended' ? endDateText : timeDisplay}
              </div>
            </div>
          ` : ''}
          ${isEnded ? `
            <div id="${stageId}-collapse-container" style="display: flex; align-items: center; gap: 4px; margin-bottom: 8px; font-size: 0.8em; font-style: italic; line-height: 1.4; color: #9ca3af;">
              <button class="stage-toggle-btn" data-stage-id="${stageId}" style="display: flex; align-items: center; justify-content: center; flex-shrink: 0; width: 18px; height: 18px; padding: 0; margin: 0; border: none; border-radius: 4px; background: transparent; cursor: pointer; transition: all 0.2s; font-size: 14px; color: #6b7280;" title="Click to expand">
                <span id="${stageId}-icon">▶</span>
              </button>
              <span id="${stageId}-collapsed-text" style="flex: 1;">View Result</span>
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
    
    // Discussion link notice removed - user doesn't want to show the yellow box with discussion URL
    const discussionLinkHTML = '';
    
    const widgetHTML = `
      <div class="tally-status-widget" style="position: relative; width: 100%; max-width: 100%; padding: 16px; box-sizing: border-box; border: 1px solid #e5e7eb; border-radius: 8px; background: #fff; ${widgetOpacity}">
        <button class="widget-close-btn" style="position: absolute; top: 8px; right: 8px; z-index: 100; display: flex; align-items: center; justify-content: center; width: 24px; height: 24px; border: none; border-radius: 4px; background: transparent; cursor: pointer; transition: all 0.2s; font-size: 18px; color: #6b7280;" title="Close widget" onmouseover="this.style.background='#f3f4f6'; this.style.color='#111827';" onmouseout="this.style.background='transparent'; this.style.color='#6b7280';">
          ×
        </button>
        ${tempCheckHTML}
        ${arfcHTML}
        ${aipHTML}
        ${discussionLinkHTML}
      </div>
    `;
    
    // CRITICAL: Update content atomically to prevent visual flash
    // When updating in place, use DocumentFragment for smooth replacement
    if (isUpdatingInPlace && statusWidget.parentNode) {
      // Find the inner widget container to replace only that part
      const existingInnerWidget = statusWidget.querySelector('.tally-status-widget');
      if (existingInnerWidget) {
        // Create new content in a temporary container
        const tempContainer = document.createElement('div');
        tempContainer.innerHTML = widgetHTML;
        const newInnerWidget = tempContainer.firstElementChild;
        
        // Atomically replace the inner widget (no flash)
        existingInnerWidget.parentNode.replaceChild(newInnerWidget, existingInnerWidget);
      } else {
        // Fallback: update innerHTML but ensure visibility is maintained
        const wasVisible = statusWidget.style.display !== 'none' && 
                          statusWidget.style.visibility !== 'hidden';
        statusWidget.innerHTML = widgetHTML;
        if (wasVisible) {
          statusWidget.style.display = 'block';
          statusWidget.style.visibility = 'visible';
          statusWidget.style.opacity = '1';
        }
      }
    } else {
      // New widget - set innerHTML directly
      statusWidget.innerHTML = widgetHTML;
    }
    
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
    
    // Position widget - use fixed positioning on right for large screens, inline (top) for smaller screens
    // Check screen width and sidebar state to determine positioning
    const shouldInline = shouldShowWidgetInline();
    
    console.log(`🔵 [WIDGET] Detection - window.innerWidth: ${window.innerWidth}, shouldInline: ${shouldInline}, sidebarCollapsed: ${isSidebarCollapsed()}`);
    
    if (shouldInline) {
      // Mobile/small screens: inline positioning at top of proposal
      // CRITICAL: Set visibility immediately, not in requestAnimationFrame (causes delay)
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
      // Force immediate reflow to ensure visibility
      void statusWidget.offsetHeight;
    }
    
    // CRITICAL: If updating in place, skip DOM insertion to prevent blinking
    if (isUpdatingInPlace && statusWidget.parentNode) {
      console.log("✅ [WIDGET] Widget updated in place, skipping DOM insertion to prevent blinking");
      // Ensure widget is visible
      statusWidget.style.display = 'block';
      statusWidget.style.visibility = 'visible';
      statusWidget.style.opacity = '1';
      markWidgetAsVisibleInCache(statusWidget);
      // Remove URL from rendering set now that widget is confirmed in DOM
      if (proposalUrl) {
        renderingUrls.delete(proposalUrl);
        renderingUrls.delete(normalizeAIPUrl(proposalUrl));
      }
      return; // Exit early - widget updated in place
    }
    
    // Use inline positioning for mobile/small screens (insert before first post)
    if (shouldInline) {
      // On mobile, check if widget is already in the correct position to prevent re-insertion
      // But allow re-rendering if content needs to be updated
      if (statusWidget.parentNode) {
        // Widget is already in DOM - check if it's in a valid location
        const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream, .topic-post-stream');
        const firstPost = document.querySelector('.topic-post, .post, [data-post-id], article[data-post-id]');
        
        // Check if widget is already in a valid location
        const isInValidLocation = topicBody && (topicBody.contains(statusWidget) || 
            (firstPost && firstPost.parentNode && firstPost.parentNode.contains(statusWidget)));
        
        if (isInValidLocation) {
          // Widget is in correct position - check if URL and order match to prevent unnecessary re-insertion
          const widgetUrl = statusWidget.getAttribute('data-tally-url');
          const widgetOrder = parseInt(statusWidget.getAttribute("data-proposal-order") || statusWidget.getAttribute("data-stage-order") || "999", 10);
          const expectedOrder = proposalOrder !== null ? proposalOrder : (hasAllStages ? 3 : (stages.tempCheck && !stages.arfc && !stages.aip ? 1 : (stages.arfc && !stages.aip ? 2 : 3)));
          
          // Only skip if URL matches AND order matches (prevent unnecessary re-insertion that causes blinking)
          if (widgetUrl === proposalUrl && widgetOrder === expectedOrder) {
            console.log("✅ [WIDGET] Widget already in correct position with same URL and order, skipping re-insertion to prevent blinking");
            // Remove URL from rendering set now that widget is confirmed in DOM
            if (proposalUrl) {
              renderingUrls.delete(proposalUrl);
              renderingUrls.delete(normalizeAIPUrl(proposalUrl));
            }
            return; // Exit early - widget is already positioned correctly with same content
          }
          // If URL or order is different, continue to update/replace the widget
        }
      }
      
      // CRITICAL: Prepare widget fully BEFORE insertion to prevent blinking
      // Set all styles and content before DOM insertion to avoid layout shift
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
      
      // Insert widget in correct order based on stage (temp-check -> arfc -> aip)
      // Widgets appear at top of proposal, before first post
      // CRITICAL: Use requestAnimationFrame to batch DOM insertion and prevent blinking
      requestAnimationFrame(() => {
        preserveScrollPosition(() => {
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
              // Sort existing widgets by proposal order to ensure correct positioning
              const sortedWidgets = [...existingWidgets].sort((a, b) => {
                const orderA = parseInt(a.getAttribute("data-proposal-order") || a.getAttribute("data-stage-order") || "999", 10);
                const orderB = parseInt(b.getAttribute("data-proposal-order") || b.getAttribute("data-stage-order") || "999", 10);
                return orderA - orderB; // Ascending order (0, 1, 2, ...)
              });
              
              // Find the correct position to insert based on proposal order (order in content)
              let insertBefore = null;
              
              // Find first widget with higher proposal order
              for (const widget of sortedWidgets) {
                const widgetProposalOrder = parseInt(widget.getAttribute("data-proposal-order") || widget.getAttribute("data-stage-order") || "999", 10);
                if (widgetProposalOrder > thisProposalOrder) {
                  insertBefore = widget;
                  break;
                }
              }
              
              if (insertBefore) {
                widgetsContainer.insertBefore(statusWidget, insertBefore);
                console.log(`✅ [WIDGET] Widget inserted in correct order (proposal order: ${thisProposalOrder}, before widget with order: ${insertBefore.getAttribute("data-proposal-order")})`);
              } else {
                // No widget with higher order, insert at end (after all existing widgets, before first post)
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
                console.log(`✅ [WIDGET] Widget appended at end (proposal order: ${thisProposalOrder}) - highest order widget`);
              }
            } else {
              // No existing widgets, insert before first post or at beginning
              if (firstPost && firstPost.parentNode) {
                firstPost.parentNode.insertBefore(statusWidget, firstPost);
                console.log("✅ [WIDGET] Widget inserted before first post (first widget)");
              } else if (topicBody) {
                if (topicBody.firstChild) {
                  topicBody.insertBefore(statusWidget, topicBody.firstChild);
                } else {
                  topicBody.appendChild(statusWidget);
                }
                console.log("✅ [WIDGET] Widget inserted in topic body (first widget)");
              } else {
                const mainContent = document.querySelector('main, .topic-body, .posts-wrapper, [role="main"]');
                if (mainContent) {
                  if (mainContent.firstChild) {
                    mainContent.insertBefore(statusWidget, mainContent.firstChild);
                  } else {
                    mainContent.appendChild(statusWidget);
                  }
                  console.log("✅ [WIDGET] Widget inserted in main content (first widget)");
                } else {
                  const bodyFirstChild = document.body.firstElementChild || document.body.firstChild;
                  if (bodyFirstChild) {
                    document.body.insertBefore(statusWidget, bodyFirstChild);
                  } else {
                    document.body.appendChild(statusWidget);
                  }
                  console.log("✅ [WIDGET] Widget inserted in body (first widget)");
                }
              }
            }
          
            // CRITICAL: Widget is already fully styled and visible before insertion
            // Just ensure it stays visible after DOM insertion
            if (statusWidget && statusWidget.parentNode) {
              // Force immediate reflow to ensure smooth rendering
              void statusWidget.offsetHeight;
              // CRITICAL: Mark as visible in cache immediately to prevent scroll flickering
              markWidgetAsVisibleInCache(statusWidget);
            }
          } catch (error) {
            console.error("❌ [WIDGET] Error inserting widget:", error);
            // Remove URL from rendering set on error
            if (proposalUrl) {
              renderingUrls.delete(proposalUrl);
            }
            // Fallback: try to append to a safe location (preserve scroll during fallback too)
            preserveScrollPosition(() => {
              const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream, main');
              if (topicBody) {
                topicBody.appendChild(statusWidget);
              } else {
                document.body.appendChild(statusWidget);
              }
            });
          }
          
          // Remove URL from rendering set now that widget is in DOM
          if (proposalUrl) {
            renderingUrls.delete(proposalUrl);
          }
        });
      });
    } else {
      // Desktop/Large screens: Use fixed positioning on right side
      const widgetsContainer = getOrCreateWidgetsContainer();
      if (widgetsContainer) {
        // Get proposal order for this widget (order in content, not stage order)
        const thisProposalOrder = parseInt(statusWidget.getAttribute("data-proposal-order") || statusWidget.getAttribute("data-stage-order") || "999", 10);
        
        // Find the correct position to insert based on proposal order
        const existingWidgets = Array.from(widgetsContainer.children);
        let insertBefore = null;
        
        // Find first widget with higher proposal order
        for (const widget of existingWidgets) {
          const widgetProposalOrder = parseInt(widget.getAttribute("data-proposal-order") || widget.getAttribute("data-stage-order") || "999", 10);
          if (widgetProposalOrder > thisProposalOrder) {
            insertBefore = widget;
            break;
          }
        }
        
        // CRITICAL: Preserve scroll position during desktop widget insertion
        preserveScrollPosition(() => {
          if (insertBefore) {
            widgetsContainer.insertBefore(statusWidget, insertBefore);
            console.log(`✅ [DESKTOP] Widget inserted in correct order (proposal order: ${thisProposalOrder})`);
          } else {
            // No widget with higher order, append at end
            widgetsContainer.appendChild(statusWidget);
            console.log(`✅ [DESKTOP] Widget appended at end (proposal order: ${thisProposalOrder})`);
          }
        });
        
        // CRITICAL: Force immediate visibility RIGHT AFTER insertion
        if (statusWidget && statusWidget.parentNode) {
          statusWidget.style.setProperty('display', 'block', 'important');
          statusWidget.style.setProperty('visibility', 'visible', 'important');
          statusWidget.style.setProperty('opacity', '1', 'important');
          statusWidget.classList.remove('hidden', 'd-none', 'is-hidden');
          void statusWidget.offsetHeight;
          // CRITICAL: Mark as visible in cache immediately to prevent scroll flickering
          markWidgetAsVisibleInCache(statusWidget);
        }
        
        // Also force visibility in next frame
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            if (statusWidget && statusWidget.parentNode) {
              statusWidget.style.setProperty('display', 'block', 'important');
              statusWidget.style.setProperty('visibility', 'visible', 'important');
              statusWidget.style.setProperty('opacity', '1', 'important');
              statusWidget.classList.remove('hidden', 'd-none', 'is-hidden');
              void statusWidget.offsetHeight;
              
              const computedStyle = window.getComputedStyle(statusWidget);
              if (computedStyle.display === 'none' || computedStyle.visibility === 'hidden' || computedStyle.opacity === '0') {
                console.warn(`⚠️ [DESKTOP] Widget hidden after insertion, forcing visibility again`);
                statusWidget.style.setProperty('display', 'block', 'important');
                statusWidget.style.setProperty('visibility', 'visible', 'important');
                statusWidget.style.setProperty('opacity', '1', 'important');
                void statusWidget.offsetHeight;
              } else {
                console.log(`✅ [DESKTOP] Widget visible after insertion`);
              }
            }
          });
        });
        
        // Remove URL from rendering set now that widget is in DOM
        if (proposalUrl) {
          renderingUrls.delete(proposalUrl);
        }
      } else {
        // Fallback: if container creation failed, insert inline
        console.warn("⚠️ [DESKTOP] Container not available, inserting inline");
        // CRITICAL: Preserve scroll position during fallback insertion
        preserveScrollPosition(() => {
          const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream');
          if (topicBody) {
            const firstPost = document.querySelector('.topic-post, .post, [data-post-id]');
            if (firstPost && firstPost.parentNode) {
              firstPost.parentNode.insertBefore(statusWidget, firstPost);
            } else {
              topicBody.insertBefore(statusWidget, topicBody.firstChild);
            }
          }
        });
        
        // Force visibility for fallback insertion too
        requestAnimationFrame(() => {
          if (statusWidget && statusWidget.parentNode) {
            statusWidget.style.setProperty('display', 'block', 'important');
            statusWidget.style.setProperty('visibility', 'visible', 'important');
            statusWidget.style.setProperty('opacity', '1', 'important');
            void statusWidget.offsetHeight;
            // CRITICAL: Mark as visible in cache immediately to prevent scroll flickering
            markWidgetAsVisibleInCache(statusWidget);
          }
        });
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
    
    // CRITICAL FIX FOR MOBILE: AIP widgets render asynchronously (in Promise callback) 
    // while Snapshot widgets render synchronously. This causes AIP widgets to be inserted
    // later, after Discourse may have applied lazy loading CSS. Force immediate visibility.
    const shouldInlineMobile = shouldShowWidgetInline();
    if (shouldInlineMobile && widgetType === 'aip' && statusWidget && statusWidget.parentNode) {
      // AIP widget was just inserted - force visibility immediately
      console.log(`🔵 [MOBILE] AIP widget just rendered, forcing immediate visibility`);
      statusWidget.style.setProperty('display', 'block', 'important');
      statusWidget.style.setProperty('visibility', 'visible', 'important');
      statusWidget.style.setProperty('opacity', '1', 'important');
      statusWidget.classList.remove('hidden', 'd-none', 'is-hidden');
      
      // CRITICAL: Mark as visible in cache immediately to prevent scroll flickering
      markWidgetAsVisibleInCache(statusWidget);
      
      // Use double requestAnimationFrame to catch it after DOM insertion
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          if (statusWidget && statusWidget.parentNode) {
            const computedStyle = window.getComputedStyle(statusWidget);
            if (computedStyle.display === 'none' || computedStyle.visibility === 'hidden' || computedStyle.opacity === '0') {
              console.warn(`⚠️ [MOBILE] AIP widget hidden after renderMultiStageWidget, forcing again`);
              statusWidget.style.setProperty('display', 'block', 'important');
              statusWidget.style.setProperty('visibility', 'visible', 'important');
              statusWidget.style.setProperty('opacity', '1', 'important');
              void statusWidget.offsetHeight; // Force reflow
            } else {
              console.log(`✅ [MOBILE] AIP widget visible after renderMultiStageWidget`);
            }
          }
        });
      });
    }
    
    // Set up auto-refresh for active proposals to fetch new vote data
    if (proposalUrl) {
      const isActive = stages.aip?.status === 'active' || 
                      stages.tempCheck?.status === 'active' || 
                      stages.arfc?.status === 'active';
      
      if (isActive) {
        // Clear any existing refresh interval for this widget
        const refreshKey = `multi_stage_refresh_${widgetId}`;
        if (window[refreshKey]) {
          clearInterval(window[refreshKey]);
        }
        
        // Store original stages and URLs for refresh
        const originalStages = { ...stages };
        const originalUrls = {
          aipUrl: stages.aipUrl,
          tempCheckUrl: stages.tempCheckUrl,
          arfcUrl: stages.arfcUrl
        };
        
        // Refresh every 2 minutes to check for vote updates
        window[refreshKey] = setInterval(async () => {
          console.log("🔄 [REFRESH] Checking for updates for multi-stage widget:", widgetId);
          
          try {
            // Determine proposal type and fetch fresh data (bypass cache)
            let freshData = null;
            if (originalStages.aip && originalUrls.aipUrl) {
              freshData = await fetchProposalDataByType(originalUrls.aipUrl, 'aip', true);
            } else if ((originalStages.tempCheck || originalStages.arfc) && (originalUrls.tempCheckUrl || originalUrls.arfcUrl)) {
              const snapshotUrl = originalUrls.tempCheckUrl || originalUrls.arfcUrl;
              freshData = await fetchProposalDataByType(snapshotUrl, 'snapshot', true);
            }
            
            if (freshData && freshData.title) {
              console.log("🔄 [REFRESH] Updating multi-stage widget with fresh data");
              
              // Re-render widget with fresh data
              const updatedStages = {
                tempCheck: originalUrls.tempCheckUrl ? (freshData.stage === 'temp-check' ? freshData : originalStages.tempCheck) : null,
                tempCheckUrl: originalUrls.tempCheckUrl,
                arfc: originalUrls.arfcUrl ? (freshData.stage === 'arfc' || freshData.stage === 'snapshot' ? freshData : originalStages.arfc) : null,
                arfcUrl: originalUrls.arfcUrl,
                aip: originalUrls.aipUrl ? (freshData.type === 'aip' ? freshData : originalStages.aip) : null,
                aipUrl: originalUrls.aipUrl
              };
              
              // Get validation info again (in case discussion link changed)
              const currentForumUrl = getCurrentForumTopicUrl();
              let validation = { isRelated: true, discussionLink: null };
              if (freshData.type === 'aip') {
                validation = await validateAIPProposalForForum({ data: freshData, url: originalUrls.aipUrl }, currentForumUrl);
              } else if (freshData.type === 'snapshot') {
                validation = validateSnapshotProposalForForum({ data: freshData, url: originalUrls.tempCheckUrl || originalUrls.arfcUrl }, currentForumUrl);
              }
              
              renderMultiStageWidget(updatedStages, widgetId, proposalOrder, validation.discussionLink, validation.isRelated);
            }
          } catch (error) {
            console.error("❌ [REFRESH] Error refreshing multi-stage widget:", error);
          }
        }, 2 * 60 * 1000); // Refresh every 2 minutes
        
        console.log("✅ [REFRESH] Auto-refresh set up for active multi-stage widget:", widgetId, "(every 2 minutes)");
      }
    }
  }

  function renderStatusWidget(proposalData, originalUrl, widgetId, proposalInfo = null) {
    const statusWidgetId = `aave-status-widget-${widgetId}`;
    const proposalType = proposalData.type || 'snapshot'; // 'snapshot' or 'aip'
    
    // Check if mobile to determine update strategy
    // Use screen width only - don't rely on user agent as tablets/desktops may have mobile-like user agents
    const isMobile = window.innerWidth <= 1400;
    
    // CRITICAL: Check if data is incomplete - show loader instead of empty widget
    // On mobile, if time data (daysLeft/hoursLeft) is missing, show loader
    const hasTitle = proposalData.title && proposalData.title !== "Snapshot Proposal";
    const hasTimeData = proposalData.daysLeft !== null && proposalData.daysLeft !== undefined;
    const isDataIncomplete = !hasTitle || (isMobile && !hasTimeData);
    
    if (isDataIncomplete) {
      console.log(`🔵 [WIDGET] Data incomplete - showing loader instead of empty widget (mobile: ${isMobile}, hasTitle: ${hasTitle}, hasTimeData: ${hasTimeData})`);
      
      // Check if loading placeholder already exists for this URL
      const existingPlaceholder = document.querySelector(`.loading-placeholder[data-tally-url="${originalUrl}"]`);
      if (existingPlaceholder) {
        console.log(`🔵 [WIDGET] Loading placeholder already exists for ${originalUrl}, keeping it`);
        return; // Don't create duplicate loader
      }
      
      // Check if a real widget already exists (not a placeholder)
      const existingWidget = document.querySelector(`.tally-status-widget-container[data-tally-url="${originalUrl}"]:not(.loading-placeholder)`);
      if (existingWidget) {
        // Replace existing widget with loader if data is incomplete
        console.log(`🔵 [WIDGET] Replacing incomplete widget with loader for ${originalUrl}`);
        existingWidget.remove();
      }
      
      // Loaders disabled - don't show anything if data is incomplete
      return; // Don't render widget with incomplete data
    }
    
    // CRITICAL: Remove loading placeholder if it exists (replace with actual widget)
    // Use normalized URL comparison to catch variations
    const normalizeUrlForComparison = (urlToNormalize) => {
      if (!urlToNormalize) {
        return '';
      }
      return urlToNormalize.trim()
        .replace(/\/+$/, '')
        .split('?')[0]
        .split('#')[0]
        .toLowerCase();
    };
    
    const normalizedOriginalUrl = normalizeUrlForComparison(originalUrl);
    
    // Find and remove all placeholders that match this URL (exact or normalized)
    const allPlaceholders = document.querySelectorAll('.loading-placeholder[data-tally-url]');
    let removedCount = 0;
    allPlaceholders.forEach(placeholder => {
      const placeholderUrl = placeholder.getAttribute('data-tally-url');
      if (!placeholderUrl) {
        return;
      }
      
      const normalizedPlaceholderUrl = normalizeUrlForComparison(placeholderUrl);
      
      // Check if URLs match (exact match or normalized match)
      if (placeholderUrl === originalUrl || normalizedPlaceholderUrl === normalizedOriginalUrl) {
        console.log(`✅ [LOADING] Removing loading placeholder for ${originalUrl} (found: ${placeholderUrl})`);
        placeholder.remove();
        removedCount++;
      }
    });
    
    // Also try removing by widgetId as fallback
    const placeholderById = document.getElementById(`loading-placeholder-${widgetId}`);
    if (placeholderById && placeholderById.classList.contains('loading-placeholder')) {
      console.log(`✅ [LOADING] Removing loading placeholder by ID for ${widgetId}`);
      placeholderById.remove();
      removedCount++;
    }
    
    if (removedCount === 0) {
      console.log(`🔵 [LOADING] No loading placeholder found to remove for ${originalUrl}`);
    }
    
    // CRITICAL: Check for existing widget by URL first (more reliable than ID)
    // This enables in-place updates to prevent blinking (same as Tally widgets)
    // URL match is what matters, not ID match
    let existingWidgetByUrl = null;
    if (originalUrl) {
      // Use normalizeAIPUrl if available (it's defined later in the file, but function declarations are hoisted)
      let normalizedUrl = originalUrl;
      try {
        if (typeof normalizeAIPUrl === 'function') {
          normalizedUrl = normalizeAIPUrl(originalUrl);
        }
      } catch {
        // Fallback to original URL if normalizeAIPUrl not available
        normalizedUrl = originalUrl;
      }
      existingWidgetByUrl = document.querySelector(`.tally-status-widget-container[data-tally-url="${originalUrl}"], .tally-status-widget-container[data-tally-url="${normalizedUrl}"]`);
    }
    
    // Check if widget with same ID already exists (for in-place updates during auto-refresh)
    const existingWidgetById = document.getElementById(statusWidgetId);
    
    // CRITICAL: If widget exists by URL, always update in place (even if ID differs)
    // This prevents blinking by updating existing widget instead of removing/recreating
    if (existingWidgetByUrl) {
      // Widget found by URL - update in place to prevent blinking
      if (existingWidgetByUrl.id !== statusWidgetId) {
        console.log(`🔵 [WIDGET] Widget found by URL with different ID (${existingWidgetByUrl.id} vs ${statusWidgetId}), updating ID and content in place to prevent blinking`);
        existingWidgetByUrl.id = statusWidgetId; // Update ID for consistency
      } else {
        console.log(`🔵 [WIDGET] Updating existing widget in place (ID: ${statusWidgetId}) to prevent flickering`);
      }
      // Continue with the rest of the function to generate the HTML, then update in place
      // (We'll handle this after generating the HTML)
    } else if (existingWidgetById && existingWidgetById.getAttribute('data-tally-url') === originalUrl) {
      // Widget exists with same ID and URL - update in place (especially important on mobile to prevent flickering)
      console.log(`🔵 [WIDGET] Updating existing widget in place (ID: ${statusWidgetId}) to prevent flickering`);
      
      // Update the widget content in place
      // We'll generate the HTML and update innerHTML, but keep the container element
      // This prevents the widget from disappearing/reappearing on mobile
      
      // Continue with the rest of the function to generate the HTML, then update in place
      // (We'll handle this after generating the HTML)
    } else {
      // Widget doesn't exist - remove duplicates and create new
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
    // CRITICAL: Prefer widget found by URL (more reliable) over widget found by ID
    let statusWidget = existingWidgetByUrl || existingWidgetById;
    const isUpdatingInPlace = statusWidget && statusWidget.getAttribute('data-tally-url') === originalUrl;
    
    if (!statusWidget) {
      // Create new widget element
      statusWidget = document.createElement("div");
      statusWidget.id = statusWidgetId;
      statusWidget.className = "tally-status-widget-container";
      statusWidget.setAttribute("data-tally-status-id", widgetId);
      statusWidget.setAttribute("data-tally-url", originalUrl);
      statusWidget.setAttribute("data-proposal-type", proposalType); // Mark widget type
      
      // CRITICAL: Prevent Discourse's viewport tracker from hiding this widget
      // Completely exclude from viewport tracking
      statusWidget.setAttribute("data-cloak", "false");
      statusWidget.setAttribute("data-skip-cloak", "true");
      statusWidget.setAttribute("data-no-cloak", "true");
      statusWidget.setAttribute("data-viewport", "false");
      statusWidget.setAttribute("data-exclude-viewport", "true");
      statusWidget.setAttribute("data-no-viewport-track", "true");
      statusWidget.classList.add("no-viewport-track");
      
      // CRITICAL: Mark widget as visible in cache immediately when created
      markWidgetAsVisibleInCache(statusWidget);
    } else {
      // Update existing widget attributes (in case they changed)
      statusWidget.setAttribute("data-tally-status-id", widgetId);
      statusWidget.setAttribute("data-tally-url", originalUrl);
      statusWidget.setAttribute("data-proposal-type", proposalType);
      console.log(`🔵 [WIDGET] Updating widget in place (ID: ${statusWidgetId}) to prevent flickering`);
      // Ensure existing widget is marked as visible in cache
      markWidgetAsVisibleInCache(statusWidget);
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
    // Also check if "closed" status with 0 votes should be treated as defeat (Rejected)
    // Only match standalone "defeat" status, not if it's part of "quorum not reached"
    const isDefeat = !isQuorumNotReached && defeatStatuses.some(s => {
      const defeatWord = s.toLowerCase();
      const matches = status === defeatWord || (status.includes(defeatWord) && !status.includes("quorum"));
      if (matches) {
        console.log("🔵 [WIDGET] Defeat match found for word:", defeatWord);
      }
      return matches;
    });
    
    // Also treat "closed" with 0 votes as defeat (Rejected) - will be checked after we calculate totalVotes
    const isClosedWithNoVotes = status === "closed";
    
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
    // Also treat "closed" with 0 votes or majority against as defeat (Rejected) - matches Snapshot website behavior
    const isClosedAsRejected = isClosedWithNoVotes && (totalVotes === 0 || (totalVotes > 0 && votesAgainstNum >= votesForNum));
    const finalIsDefeat = (isDefeat && !finalIsQuorumNotReached && quorumReached) || isClosedAsRejected;
    
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
    } else if (status === "closed") {
      // For "closed" status, determine result from votes (like Snapshot website does)
      if (totalVotes > 0 && votesForNum > votesAgainstNum) {
        displayStatus = "Passed";
        console.log("🔵 [WIDGET] Overriding status: 'closed' → 'Passed' (majority support)");
      } else if (totalVotes > 0 && votesAgainstNum >= votesForNum) {
        displayStatus = "Rejected";
        console.log("🔵 [WIDGET] Overriding status: 'closed' → 'Rejected' (majority against)");
      } else if (totalVotes === 0) {
        // Closed with 0 votes = Rejected (no one voted for it, like Snapshot website)
        displayStatus = "Rejected";
        console.log("🔵 [WIDGET] Overriding status: 'closed' → 'Rejected' (0 votes, like Snapshot website)");
      } else {
        // Keep "Closed" if we can't determine
        displayStatus = "Closed";
      }
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
    const isCreated = status === 'created';
    const isExecuted = !isPendingExecution && !finalIsDefeat && !finalIsQuorumNotReached && executedStatuses.includes(status);
    const isQueued = !isPendingExecution && !finalIsDefeat && !finalIsQuorumNotReached && queuedStatuses.includes(status);
    const isPending = !isPendingExecution && !finalIsDefeat && !finalIsQuorumNotReached && !isQueued && (pendingStatuses.includes(status) || (status.includes("pending") && !isPendingExecution));
    
    console.log("🔵 [WIDGET] Status flags:", { isPendingExecution, isActive, isCreated, isExecuted, isQueued, isPending, isDefeat: finalIsDefeat, isQuorumNotReached: finalIsQuorumNotReached });
    console.log("🔵 [WIDGET] Display status:", displayStatus, "(Raw from API:", exactStatus, ")");
    
    // Determine stage label and button text based on proposal type
    let stageLabel = '';
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
    
    let buttonText = 'View Proposal';
    
    // Simple rule: If active, show "Vote", otherwise show "View"
    // This applies to all proposal types (Snapshot, AIP, etc.)
    const shouldShowVote = isActive;
    
    if (proposalData.type === 'snapshot') {
      if (proposalData.stage === 'temp-check') {
        stageLabel = 'Temp Check';
        buttonText = shouldShowVote ? 'Vote on Snapshot' : 'View on Snapshot';
      } else if (proposalData.stage === 'arfc') {
        stageLabel = 'ARFC';
        buttonText = shouldShowVote ? 'Vote on Snapshot' : 'View on Snapshot';
      } else {
        stageLabel = 'Snapshot';
        buttonText = shouldShowVote ? 'Vote on Snapshot' : 'View on Snapshot';
      }
    } else if (proposalData.type === 'aip') {
      stageLabel = 'AIP (On-Chain)';
      buttonText = shouldShowVote ? 'Vote on Aave' : 'View on Aave';
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
    const endedOpacity = hasPassed && !isEndingSoon ? 'opacity: 0.6;' : '';
    
    const widgetHTML = `
      <div class="tally-status-widget ${urgencyClass}" style="position: relative; ${urgencyStyle} background: #fff; ${endedOpacity}">
        <button class="widget-close-btn" style="position: absolute; top: 8px; right: 8px; z-index: 10; display: flex; align-items: center; justify-content: center; width: 24px; height: 24px; border: none; border-radius: 4px; background: transparent; cursor: pointer; transition: all 0.2s; font-size: 18px; color: #6b7280;" title="Close widget" onmouseover="this.style.background='#f3f4f6'; this.style.color='#111827';" onmouseout="this.style.background='transparent'; this.style.color='#6b7280';">
          ×
        </button>
        ${stageLabel ? `<div class="stage-label" style="margin-bottom: 8px; font-size: 0.75em; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; color: #6b7280;">${stageLabel}</div>` : ''}
        ${isEndingSoon ? `<div class="urgency-alert" style="padding: 8px; margin-bottom: 12px; border-radius: 4px; background: #fee2e2; font-size: 0.85em; font-weight: 600; text-align: center; color: #dc2626;">⚠️ Ending Soon!</div>` : ''}
        <div class="status-badges-row">
          <div class="status-badge ${isPendingExecution ? 'pending' : isActive ? 'active' : isCreated ? 'created' : isExecuted ? 'executed' : isQueued ? 'queued' : isPending ? 'pending' : (displayStatus === 'Rejected' || status === 'rejected') ? 'rejected' : finalIsDefeat ? 'defeated' : finalIsQuorumNotReached ? 'quorum-not-reached' : status === 'failed' ? 'failed' : 'inactive'}">
            <strong>${displayStatus}</strong>
          </div>
          ${(() => {
            if (proposalData.daysLeft !== null && proposalData.daysLeft !== undefined && !isNaN(proposalData.daysLeft)) {
              let displayText = '';
              let badgeStyle = '';
              if (proposalData.daysLeft < 0) {
                displayText = 'Ended';
              } else if (proposalData.daysLeft === 0 && proposalData.hoursLeft !== null) {
                // Check if hoursLeft is negative (proposal has ended)
                if (proposalData.hoursLeft < 0) {
                  displayText = 'Ended Today';
                } else if (proposalData.hoursLeft === 0) {
                  // Show exact time when hoursLeft is 0
                  let endTimestamp = null;
                  if (proposalData.endTimestamp) {
                    endTimestamp = proposalData.endTimestamp;
                  } else if (proposalData.end && proposalData.end.timestamp) {
                    endTimestamp = typeof proposalData.end.timestamp === 'number' 
                      ? (proposalData.end.timestamp > 946684800000 ? proposalData.end.timestamp : proposalData.end.timestamp * 1000)
                      : Date.parse(proposalData.end.timestamp);
                  } else if (proposalData.end && proposalData.end.ts) {
                    endTimestamp = typeof proposalData.end.ts === 'number'
                      ? (proposalData.end.ts > 946684800000 ? proposalData.end.ts : proposalData.end.ts * 1000)
                      : Date.parse(proposalData.end.ts);
                  } else if (proposalData.endTime) {
                    endTimestamp = Number(proposalData.endTime) * 1000;
                  }
                  
                  if (endTimestamp && !isNaN(endTimestamp)) {
                    const endDate = new Date(endTimestamp);
                    if (!isNaN(endDate.getTime())) {
                      const exactTime = endDate.toLocaleTimeString('en-US', {
                        hour: 'numeric',
                        minute: '2-digit',
                        hour12: true
                      });
                      displayText = `Ends at ${exactTime}`;
                    } else {
                      displayText = 'Ends today';
                    }
                  } else {
                    displayText = 'Ends today';
                  }
                  if (isEndingSoon) {
                    badgeStyle = 'background: #fee2e2; color: #dc2626; border-color: #fca5a5; font-weight: 700;';
                  }
                } else {
                  displayText = proposalData.hoursLeft + ' ' + (proposalData.hoursLeft === 1 ? 'hour' : 'hours') + ' left';
                  if (isEndingSoon) {
                    badgeStyle = 'background: #fee2e2; color: #dc2626; border-color: #fca5a5; font-weight: 700;';
                  }
                }
              } else if (proposalData.daysLeft === 0) {
                // If daysLeft is 0 but we don't have hoursLeft, check status to determine if ended
                const proposalStatus = (proposalData.status || status || '').toLowerCase();
                const endedStatuses = ['closed', 'ended', 'passed', 'executed', 'rejected', 'defeated', 'failed', 'cancelled', 'expired'];
                if (endedStatuses.includes(proposalStatus)) {
                  displayText = 'Ended Today';
                } else {
                  // If status indicates it's still active, show "Ends today"
                  const stillActiveStatuses = ['active', 'open', 'pending', 'created'];
                  if (stillActiveStatuses.includes(proposalStatus)) {
                    displayText = 'Ends today';
                    if (isEndingSoon) {
                      badgeStyle = 'background: #fee2e2; color: #dc2626; border-color: #fca5a5; font-weight: 700;';
                    }
                  } else {
                    // Default to "Ended Today" to be safe (avoids confusion)
                    displayText = 'Ended Today';
                  }
                }
              } else {
                displayText = proposalData.daysLeft + ' ' + (proposalData.daysLeft === 1 ? 'day' : 'days') + ' left';
                if (isEndingSoon) {
                  badgeStyle = 'background: #fef3c7; color: #92400e; border-color: #fde68a; font-weight: 700;';
              }
              }
              const finalStyle = badgeStyle ? `${badgeStyle} padding: 4px 10px 4px 0;` : 'padding: 4px 10px 4px 0;';
              return `<div class="days-left-badge" style="${finalStyle}">${displayText}</div>`;
            } else if (proposalData.daysLeft === null) {
              return '<div class="days-left-badge" style="padding: 4px 10px 4px 0;">Date unknown</div>';
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
          
          // Progress bar - always show, even if 0 votes
          const progressBarHtml = `
            <div class="progress-bar">
              ${percentFor > 0 ? `<div class="progress-segment progress-for" style="width: ${percentFor}%"></div>` : ''}
              ${percentAgainst > 0 ? `<div class="progress-segment progress-against" style="width: ${percentAgainst}%"></div>` : ''}
              ${percentAbstain > 0 ? `<div class="progress-segment progress-abstain" style="width: ${percentAbstain}%"></div>` : ''}
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
          <div class="quorum-info" style="margin-top: 8px; margin-bottom: 8px; font-size: 0.85em; color: #6b7280;">
            Quorum: ${formatVoteAmount(totalVotes)} / ${formatVoteAmount(proposalData.quorum)}
          </div>
        ` : ''}
        <a href="${originalUrl}" target="_blank" rel="noopener" class="vote-button" style="${hasPassed && !isEndingSoon ? 'background-color: #e5e7eb !important; color: #6b7280 !important;' : 'background-color: var(--d-button-primary-bg-color, #2563eb) !important; color: var(--d-button-primary-text-color, white) !important;'}">
          ${buttonText}
        </a>
      </div>
    `;

    // CRITICAL: Update content atomically to prevent visual flash
    // When updating in place, use atomic replacement for smooth update
    if (isUpdatingInPlace && statusWidget.parentNode) {
      // Find the inner widget container to replace only that part
      const existingInnerWidget = statusWidget.querySelector('.tally-status-widget');
      if (existingInnerWidget) {
        // Create new content in a temporary container
        const tempContainer = document.createElement('div');
        tempContainer.innerHTML = widgetHTML;
        const newInnerWidget = tempContainer.firstElementChild;
        
        // Atomically replace the inner widget (no flash)
        if (newInnerWidget && existingInnerWidget.parentNode) {
          existingInnerWidget.parentNode.replaceChild(newInnerWidget, existingInnerWidget);
        } else {
          // Fallback: update innerHTML but ensure visibility is maintained
          const wasVisible = statusWidget.style.display !== 'none' && 
                            statusWidget.style.visibility !== 'hidden';
          statusWidget.innerHTML = widgetHTML;
          if (wasVisible) {
            statusWidget.style.display = 'block';
            statusWidget.style.visibility = 'visible';
            statusWidget.style.opacity = '1';
          }
        }
      } else {
        // Fallback: update innerHTML but ensure visibility is maintained
        const wasVisible = statusWidget.style.display !== 'none' && 
                          statusWidget.style.visibility !== 'hidden';
        statusWidget.innerHTML = widgetHTML;
        if (wasVisible) {
          statusWidget.style.display = 'block';
          statusWidget.style.visibility = 'visible';
          statusWidget.style.opacity = '1';
        }
      }
    } else {
      // New widget - set innerHTML directly
      statusWidget.innerHTML = widgetHTML;
    }

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
      
      // CRITICAL: Pre-style widget fully BEFORE insertion to prevent blinking
      // Set all styles and content before DOM insertion to avoid layout shift
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
      
      // Mobile: Insert widgets sequentially so all are visible
      // Find existing widgets and insert after the last one, or before first post if none exist
      // CRITICAL: Use requestAnimationFrame to batch DOM insertion and prevent blinking
      requestAnimationFrame(() => {
        preserveScrollPosition(() => {
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
            
            // CRITICAL: Widget is already fully styled and visible before insertion
            // Just ensure it stays visible after DOM insertion
            if (statusWidget && statusWidget.parentNode) {
              // Force immediate reflow to ensure smooth rendering
              void statusWidget.offsetHeight;
              // CRITICAL: Mark as visible in cache immediately to prevent scroll flickering
              markWidgetAsVisibleInCache(statusWidget);
            }
          } catch (error) {
            console.error("❌ [MOBILE] Error inserting widget:", error);
          }
        });
      });
        
        // Ensure widget is visible on mobile - force visibility
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
        
        // Remove any hidden classes that might prevent display
        statusWidget.classList.remove('hidden', 'd-none', 'is-hidden');
        
        // CRITICAL: Mark widget as visible in cache immediately to prevent scroll flickering
        markWidgetAsVisibleInCache(statusWidget);
        
        // Force immediate visibility on mobile - ensure widget appears without scroll
        // Use requestAnimationFrame to ensure DOM is ready
        requestAnimationFrame(() => {
          statusWidget.style.display = 'block';
          statusWidget.style.visibility = 'visible';
          statusWidget.style.opacity = '1';
          // Force a reflow to ensure visibility
          void statusWidget.offsetHeight;
          // Mark as visible in cache again after DOM update
          markWidgetAsVisibleInCache(statusWidget);
        });
        
        // Also ensure visibility after a short delay to catch any late DOM updates
        setTimeout(() => {
          if (statusWidget && statusWidget.parentNode) {
            statusWidget.style.display = 'block';
            statusWidget.style.visibility = 'visible';
            statusWidget.style.opacity = '1';
            statusWidget.classList.remove('hidden', 'd-none', 'is-hidden');
            
            // Force visibility with !important via setProperty
            statusWidget.style.setProperty('display', 'block', 'important');
            statusWidget.style.setProperty('visibility', 'visible', 'important');
            statusWidget.style.setProperty('opacity', '1', 'important');
            
            // Check computed styles to ensure it's actually visible
            const computedStyle = window.getComputedStyle(statusWidget);
            if (computedStyle.display === 'none' || computedStyle.visibility === 'hidden') {
              console.warn(`⚠️ [MOBILE] Widget still hidden after force - display: ${computedStyle.display}, visibility: ${computedStyle.visibility}`);
              // Don't scroll to widget - just log the warning. Visibility is already forced via CSS.
            }
          }
        }, 50);
        
        // Additional check after longer delay to catch any Discourse lazy loading
        setTimeout(() => {
          if (statusWidget && statusWidget.parentNode) {
            const computedStyle = window.getComputedStyle(statusWidget);
            if (computedStyle.display === 'none' || computedStyle.visibility === 'hidden' || computedStyle.opacity === '0') {
              console.log(`🔵 [MOBILE] Widget was hidden, forcing visibility again after delay`);
              statusWidget.style.setProperty('display', 'block', 'important');
              statusWidget.style.setProperty('visibility', 'visible', 'important');
              statusWidget.style.setProperty('opacity', '1', 'important');
              statusWidget.classList.remove('hidden', 'd-none', 'is-hidden');
            }
          }
        }, 300);
        
        // Mark URL as rendered after successful insertion
        if (originalUrl) {
          renderingUrls.add(originalUrl);
          console.log(`✅ [MOBILE] Widget rendered and marked: ${originalUrl}`);
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
    
    // CRITICAL: Mark widget as shown for this topic (prevents disappearing on scroll)
    // This ensures widget appears on first visit and stays visible
    markWidgetAsShown();
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
          // Decode HTML entities to normalize URLs
          const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
          // Include Aave Snapshot space links (aave.eth or s:aavedao.eth) OR testnet Snapshot URLs
          const isAaveSpace = decodedUrl.includes('aave.eth') || decodedUrl.includes('aavedao.eth');
          const isTestnet = decodedUrl.includes('testnet.snapshot.box');
          if (isAaveSpace || isTestnet) {
            if (!extractedLinks.snapshot.includes(decodedUrl) && !extractedLinks.snapshot.includes(url)) {
              extractedLinks.snapshot.push(decodedUrl);
              console.log("✅ [FORUM] Found Snapshot link:", decodedUrl, isTestnet ? "(testnet)" : "(production)");
            }
          }
        });
      }
      
      // Find AIP links in this post
      const aipMatches = combinedContent.match(AIP_URL_REGEX);
      if (aipMatches) {
        aipMatches.forEach(url => {
          // Decode HTML entities to normalize URLs
          const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
          if (!extractedLinks.aip.includes(decodedUrl) && !extractedLinks.aip.includes(url)) {
            extractedLinks.aip.push(decodedUrl);
            console.log("✅ [FORUM] Found AIP link:", decodedUrl);
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
    
    // CRITICAL FIX: Scan the topic content area HTML to catch URLs in lazy-loaded or hidden posts
    // This ensures AIP URLs are found even if posts aren't fully rendered yet
    // But we limit it to topic content only (not navigation/sidebar/etc)
    // Only scan if we're actually on a topic page (check URL pattern)
    const isTopicPage = window.location.pathname.match(/^\/t\//);
    
    if (isTopicPage) {
      const topicContentSelectors = [
        '.topic-body',
        '.post-stream', 
        '.posts-wrapper',
        '.topic-post-stream',
        '[data-topic-id]',
        'main .posts-wrapper',
        '.topic-area',
        '.topic-body-wrapper'
      ];
      
      let topicContentHTML = '';
      
      // Find the topic content container (not the entire page)
      for (const selector of topicContentSelectors) {
        const element = document.querySelector(selector);
        if (element) {
          topicContentHTML = element.innerHTML || '';
          console.log(`🔍 [TOPIC] Found topic content container: ${selector}, HTML length: ${topicContentHTML.length}`);
          break;
        }
      }
      
      // Fallback: If no specific container found, try to find main content area
      // But still more targeted than entire page
      if (!topicContentHTML) {
        const mainContent = document.querySelector('main, [role="main"], .contents');
        if (mainContent) {
          topicContentHTML = mainContent.innerHTML || '';
          console.log(`🔍 [TOPIC] Using main content area as fallback, HTML length: ${topicContentHTML.length}`);
        }
      }
      
      // Only scan topic content HTML (not entire page) for proposals
      if (topicContentHTML && topicContentHTML.length > 0) {
        console.log("🔍 [TOPIC] Scanning topic content HTML for proposals (catches all posts including lazy-loaded ones)...");
        console.log(`🔍 [TOPIC] Topic content HTML length: ${topicContentHTML.length} characters`);
        
        // Scan topic content HTML for AIP URLs
        AIP_URL_REGEX.lastIndex = 0;
        const topicAipMatches = topicContentHTML.match(AIP_URL_REGEX);
        console.log(`🔍 [TOPIC] AIP regex found ${topicAipMatches ? topicAipMatches.length : 0} match(es) in topic content HTML`);
        
        if (topicAipMatches) {
          topicAipMatches.forEach((url, idx) => {
            console.log(`🔍 [TOPIC] AIP match ${idx + 1}: "${url}"`);
            const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
            // Exclude forum topic URLs (governance.aave.com/t/) - these are NOT AIP proposal URLs
            if (!decodedUrl.includes('governance.aave.com/t/')) {
              if (!proposals.aip.includes(decodedUrl) && !proposals.aip.includes(url)) {
                proposals.aip.push(decodedUrl);
                console.log("✅ [TOPIC] Found AIP link in topic content HTML:", decodedUrl);
              } else {
                console.log(`⚠️ [TOPIC] AIP URL already in list: ${decodedUrl}`);
              }
            } else {
              console.log(`⚠️ [TOPIC] Skipping forum topic URL (not an AIP): ${decodedUrl}`);
            }
          });
        } else {
          // Debug: Check if AIP URL patterns exist in HTML but regex didn't match
          const hasVoteOnaave = topicContentHTML.includes('vote.onaave.com');
          const hasAppAave = topicContentHTML.includes('app.aave.com/governance');
          const hasGovernanceAave = topicContentHTML.includes('governance.aave.com/aip/');
          console.log(`🔍 [TOPIC] AIP pattern check in HTML - vote.onaave.com: ${hasVoteOnaave}, app.aave.com: ${hasAppAave}, governance.aave.com/aip/: ${hasGovernanceAave}`);
          
          if (hasVoteOnaave || hasAppAave || hasGovernanceAave) {
            // Try to find the URL manually
            const patterns = [
              /https?:\/\/[^\s<>"']*vote\.onaave\.com[^\s<>"']*/gi,
              /https?:\/\/[^\s<>"']*app\.aave\.com\/governance[^\s<>"']*/gi,
              /https?:\/\/[^\s<>"']*governance\.aave\.com\/aip\/[^\s<>"']*/gi
            ];
            
            patterns.forEach((pattern, idx) => {
              pattern.lastIndex = 0;
              const matches = topicContentHTML.match(pattern);
              if (matches) {
                console.log(`⚠️ [TOPIC] Found AIP-like URLs with pattern ${idx + 1}:`, matches);
                matches.forEach(url => {
                  const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
                  if (!decodedUrl.includes('governance.aave.com/t/') && !proposals.aip.includes(decodedUrl)) {
                    proposals.aip.push(decodedUrl);
                    console.log("✅ [TOPIC] Found AIP link via fallback pattern:", decodedUrl);
                  }
                });
              }
            });
          }
        }
        
        // Scan topic content HTML for Snapshot URLs
        const topicSnapshotMatches = topicContentHTML.match(SNAPSHOT_URL_REGEX);
        console.log(`🔍 [TOPIC] Snapshot regex found ${topicSnapshotMatches ? topicSnapshotMatches.length : 0} match(es) in topic content HTML`);
        if (topicSnapshotMatches) {
          topicSnapshotMatches.forEach((url, idx) => {
            console.log(`🔍 [TOPIC] Snapshot match ${idx + 1}: "${url}"`);
            const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
            const isAaveSpace = decodedUrl.includes('aave.eth') || decodedUrl.includes('aavedao.eth');
            const isTestnet = decodedUrl.includes('testnet.snapshot.box');
            console.log(`🔍 [TOPIC] Snapshot URL check - isAaveSpace: ${isAaveSpace}, isTestnet: ${isTestnet}, URL: ${decodedUrl}`);
            
            // CRITICAL: Accept ALL Snapshot URLs, not just Aave spaces
            // This ensures we catch proposals even if they're from different spaces
            // The space filter was too restrictive and prevented detection
            if (isAaveSpace || isTestnet || decodedUrl.includes('snapshot.org') || decodedUrl.includes('snapshot.box')) {
              if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(url)) {
                proposals.snapshot.push(decodedUrl);
                console.log("✅ [TOPIC] Found Snapshot link in topic content HTML:", decodedUrl, isTestnet ? "(testnet)" : "(production)");
              }
            } else {
              console.log(`⚠️ [TOPIC] Snapshot URL found but doesn't match Aave space filter: ${decodedUrl}`);
              // Still add it - the space filter was too restrictive
              if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(url)) {
                proposals.snapshot.push(decodedUrl);
                console.log("✅ [TOPIC] Added Snapshot link despite space filter (more permissive):", decodedUrl);
              }
            }
          });
        } else {
          // Debug: Check if Snapshot URL pattern exists in HTML but regex didn't match
          const hasSnapshot = topicContentHTML.includes('snapshot.org') || topicContentHTML.includes('snapshot.box');
          console.log(`🔍 [TOPIC] Snapshot pattern check in HTML - snapshot.org: ${topicContentHTML.includes('snapshot.org')}, snapshot.box: ${topicContentHTML.includes('snapshot.box')}`);
          if (hasSnapshot) {
            // Try a more flexible pattern
            const flexiblePattern = /https?:\/\/[^\s<>"']*snapshot\.(?:org|box)[^\s<>"']*/gi;
            const flexibleMatches = topicContentHTML.match(flexiblePattern);
            if (flexibleMatches) {
              console.log(`⚠️ [TOPIC] Found Snapshot-like URLs with flexible pattern:`, flexibleMatches);
              flexibleMatches.forEach(url => {
                const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
                if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(url)) {
                  proposals.snapshot.push(decodedUrl);
                  console.log("✅ [TOPIC] Found Snapshot link via flexible pattern:", decodedUrl);
                }
              });
            }
          }
        }
        
        // Scan topic content HTML for Forum URLs
        const topicForumMatches = topicContentHTML.match(AAVE_FORUM_URL_REGEX);
        if (topicForumMatches) {
          topicForumMatches.forEach((url) => {
            const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
            const cleanUrl = decodedUrl.replace(/[\/#\?].*$/, '').replace(/\/$/, '');
            if (!proposals.forum.includes(cleanUrl) && !proposals.forum.includes(url)) {
              proposals.forum.push(cleanUrl);
              console.log("✅ [TOPIC] Found Forum link in topic content HTML:", cleanUrl);
            }
          });
        }
        
        // CRITICAL: Also scan oneboxes in the topic content HTML for Snapshot URLs
        // Oneboxes might be in the HTML but the regex might not catch them due to encoding
        // Create a temporary container to parse and search oneboxes
        const tempContainer = document.createElement('div');
        tempContainer.innerHTML = topicContentHTML;
        const allOneboxes = tempContainer.querySelectorAll('.onebox, .onebox-body, [class*="onebox"]');
        console.log(`🔍 [TOPIC] Found ${allOneboxes.length} onebox(es) in topic content HTML to scan for Snapshot URLs`);
        allOneboxes.forEach((onebox, idx) => {
          const oneboxText = onebox.textContent || onebox.innerText || '';
          const oneboxHtml = onebox.innerHTML || '';
          const oneboxContent = oneboxText + ' ' + oneboxHtml;
          
          if (oneboxContent.includes('snapshot.org') || oneboxContent.includes('snapshot.box') || oneboxContent.includes('testnet.snapshot.box')) {
            console.log(`🔍 [TOPIC] Onebox ${idx + 1} in topic HTML: Contains Snapshot URL pattern`);
            SNAPSHOT_URL_REGEX.lastIndex = 0;
            const oneboxMatches = oneboxContent.match(SNAPSHOT_URL_REGEX);
            if (oneboxMatches) {
              oneboxMatches.forEach(url => {
                const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
                const isTestnet = decodedUrl.includes('testnet.snapshot.box');
                if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(url)) {
                  proposals.snapshot.push(decodedUrl);
                  console.log(`✅ [TOPIC] Found Snapshot link in topic HTML onebox:`, decodedUrl, isTestnet ? "(testnet)" : "(production)");
                }
              });
            } else {
              // Try flexible pattern (includes testnet)
              const flexiblePattern = /https?:\/\/[^\s<>"']*snapshot\.(?:org|box)[^\s<>"']*/gi;
              const flexibleMatches = oneboxContent.match(flexiblePattern);
              if (flexibleMatches) {
                flexibleMatches.forEach(url => {
                  const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
                  const isTestnet = decodedUrl.includes('testnet.snapshot.box');
                  if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(url)) {
                    proposals.snapshot.push(decodedUrl);
                    console.log(`✅ [TOPIC] Found Snapshot link in topic HTML onebox (flexible):`, decodedUrl, isTestnet ? "(testnet)" : "(production)");
                  }
                });
              }
            }
          }
        });
      }
    } else {
      console.log("🔍 [TOPIC] Not on a topic page - skipping full HTML scan (prevents widgets on wrong pages)");
    }
    
    // Find all posts in the topic (for more detailed post-by-post scanning)
    // Also try to find posts that might be lazy-loaded (check for post-like elements even if not visible)
    const allPosts = Array.from(document.querySelectorAll('.topic-post, .post, [data-post-id], article[data-post-id]'));
    console.log("🔍 [TOPIC] Found", allPosts.length, "rendered posts to search (supplementing full page scan)");
    
    // Also check for lazy-loaded posts that might be in the DOM but not visible
    if (allPosts.length === 0) {
      console.log("⚠️ [TOPIC] No posts found with standard selectors - trying alternative selectors for lazy-loaded posts");
      const altPosts = Array.from(document.querySelectorAll('article, .cooked, .post-content, [class*="post"], [id*="post"]'));
      if (altPosts.length > 0) {
        console.log(`🔍 [TOPIC] Found ${altPosts.length} potential posts with alternative selectors`);
        allPosts.push(...altPosts);
      }
    }
    
    if (allPosts.length === 0) {
      const altPosts = Array.from(document.querySelectorAll('article, .cooked, .post-content, [class*="post"]'));
      if (altPosts.length > 0) {
        allPosts.push(...altPosts);
      }
    }
    
    // Search through all posts
    for (let i = 0; i < allPosts.length; i++) {
      const post = allPosts[i];
      
      // CRITICAL: Check the .cooked element (raw HTML before oneboxes are created)
      // This is what decorateCookedElement uses, so we should use it too
      const cookedElement = post.querySelector('.cooked, .post-content, [data-post-content]');
      let postText = '';
      let postHtml = '';
      
      if (cookedElement) {
        // Use cooked element's content (raw HTML before processing)
        postText = cookedElement.textContent || cookedElement.innerText || '';
        postHtml = cookedElement.innerHTML || '';
        console.log(`🔍 [TOPIC] Post ${i + 1}: Using .cooked element (length: ${postText.length} chars text, ${postHtml.length} chars HTML)`);
      } else {
        // Fallback to post's content
        postText = post.textContent || post.innerText || '';
        postHtml = post.innerHTML || '';
        console.log(`🔍 [TOPIC] Post ${i + 1}: No .cooked element found, using post content (length: ${postText.length} chars text, ${postHtml.length} chars HTML)`);
      }
      
      const combinedContent = postText + ' ' + postHtml;
      
      // CRITICAL: Check combined text+HTML content for Snapshot URLs (like decorateCookedElement does)
      // This catches URLs even if they're not in links yet or oneboxes haven't been created
      // Use combined content to match what decorateCookedElement sees
      const combinedText = postText + ' ' + postHtml;
      SNAPSHOT_URL_REGEX.lastIndex = 0;
      const allMatches = Array.from(combinedText.matchAll(SNAPSHOT_URL_REGEX));
      console.log(`🔍 [TOPIC] Post ${i + 1}: Found ${allMatches.length} Snapshot URL(s) in combined content (text+HTML)`);
      allMatches.forEach((match, matchIdx) => {
        const url = match[0];
        const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
        const isTestnet = decodedUrl.includes('testnet.snapshot.box');
        if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(url)) {
          proposals.snapshot.push(decodedUrl);
          console.log(`✅ [TOPIC] Found Snapshot link (in combined content, match ${matchIdx + 1}):`, decodedUrl, isTestnet ? "(testnet)" : "(production)");
        }
      });
      
      // CRITICAL: Check for links directly in the post (before oneboxes are rendered)
      // This catches Snapshot URLs even if oneboxes haven't been created yet
      const allLinks = post.querySelectorAll('a[href]');
      console.log(`🔍 [TOPIC] Post ${i + 1}: Found ${allLinks.length} total link(s) to check`);
      let foundDirectLinks = 0;
      allLinks.forEach((link, linkIdx) => {
        const href = link.href || link.getAttribute('href') || '';
        if (href && (href.includes('snapshot.org') || href.includes('snapshot.box') || href.includes('testnet.snapshot.box'))) {
          console.log(`🔍 [TOPIC] Post ${i + 1}, Link ${linkIdx + 1}: Found Snapshot-like URL: "${href}"`);
          const decodedUrl = href.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
          const isTestnet = decodedUrl.includes('testnet.snapshot.box');
          // Check if it matches the Snapshot URL pattern
          SNAPSHOT_URL_REGEX.lastIndex = 0;
          if (SNAPSHOT_URL_REGEX.test(decodedUrl)) {
            if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(href)) {
              proposals.snapshot.push(decodedUrl);
              foundDirectLinks++;
              console.log(`✅ [TOPIC] Found Snapshot link (direct link in post ${i + 1}):`, decodedUrl, isTestnet ? "(testnet)" : "(production)");
            }
          } else {
            console.log(`⚠️ [TOPIC] Post ${i + 1}, Link ${linkIdx + 1}: URL contains snapshot but regex didn't match: "${decodedUrl}"`);
          }
        }
      });
      if (foundDirectLinks > 0) {
        console.log(`✅ [TOPIC] Post ${i + 1}: Found ${foundDirectLinks} Snapshot link(s) via direct link check`);
      }
      
      // Also check for custom preview containers (these replace oneboxes)
      // If preview containers exist, it means decorateCookedElement already found URLs
      // Extract the URL from the preview container's data attribute
      const previewContainers = post.querySelectorAll('.tally-url-preview, [data-tally-preview-id]');
      console.log(`🔍 [TOPIC] Post ${i + 1}: Found ${previewContainers.length} preview container(s)`);
      let foundPreviewLinks = 0;
      previewContainers.forEach((preview, previewIdx) => {
        // Method 1: Extract URL from data-tally-url attribute (stored when preview was created)
        const storedUrl = preview.getAttribute('data-tally-url');
        if (storedUrl) {
          const decodedUrl = storedUrl.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
          
          // Check if it's a Snapshot URL
          SNAPSHOT_URL_REGEX.lastIndex = 0;
          if (SNAPSHOT_URL_REGEX.test(decodedUrl)) {
            const isTestnet = decodedUrl.includes('testnet.snapshot.box');
            if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(storedUrl)) {
              proposals.snapshot.push(decodedUrl);
              foundPreviewLinks++;
              console.log(`✅ [TOPIC] Found Snapshot link (from preview container data attribute ${previewIdx + 1}):`, decodedUrl, isTestnet ? "(testnet)" : "(production)");
            }
          }
          
          // Check if it's an AIP URL
          AIP_URL_REGEX.lastIndex = 0;
          if (AIP_URL_REGEX.test(decodedUrl)) {
            if (!proposals.aip.includes(decodedUrl) && !proposals.aip.includes(storedUrl)) {
              proposals.aip.push(decodedUrl);
              foundPreviewLinks++;
              console.log(`✅ [TOPIC] Found AIP link (from preview container data attribute ${previewIdx + 1}):`, decodedUrl);
            }
          }
          
          // Check if it's a Forum URL
          AAVE_FORUM_URL_REGEX.lastIndex = 0;
          if (AAVE_FORUM_URL_REGEX.test(decodedUrl)) {
            const cleanUrl = decodedUrl.replace(/[\/#\?].*$/, '').replace(/\/$/, '');
            if (!proposals.forum.includes(cleanUrl) && !proposals.forum.includes(decodedUrl) && !proposals.forum.includes(storedUrl)) {
              proposals.forum.push(cleanUrl);
              foundPreviewLinks++;
              console.log(`✅ [TOPIC] Found Forum link (from preview container data attribute ${previewIdx + 1}):`, cleanUrl);
            }
          }
        }
        
        // Method 2: Check for links in preview container (might be loading)
        const previewLinks = preview.querySelectorAll('a[href*="snapshot.org"], a[href*="snapshot.box"], a[href*="testnet.snapshot.box"]');
        console.log(`🔍 [TOPIC] Post ${i + 1}, Preview ${previewIdx + 1}: Found ${previewLinks.length} link(s) in preview`);
        previewLinks.forEach(link => {
          const href = link.href || link.getAttribute('href') || '';
          if (href && (href.includes('snapshot.org') || href.includes('snapshot.box') || href.includes('testnet.snapshot.box'))) {
            const decodedUrl = href.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
            const isTestnet = decodedUrl.includes('testnet.snapshot.box');
            SNAPSHOT_URL_REGEX.lastIndex = 0;
            if (SNAPSHOT_URL_REGEX.test(decodedUrl)) {
              if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(href)) {
                proposals.snapshot.push(decodedUrl);
                foundPreviewLinks++;
                console.log(`✅ [TOPIC] Found Snapshot link (in preview container ${previewIdx + 1}):`, decodedUrl, isTestnet ? "(testnet)" : "(production)");
              }
            }
          }
        });
        
        // Method 3: If preview container exists but no URL stored and no links yet, check the cooked element's HTML
        // The URL might still be in the cooked element's HTML before it was fully replaced
        if (!storedUrl && previewLinks.length === 0 && cookedElement) {
          // Check if cooked element's HTML still contains the URL (before replacement)
          const cookedHtml = cookedElement.innerHTML || '';
          SNAPSHOT_URL_REGEX.lastIndex = 0;
          const cookedMatches = Array.from(cookedHtml.matchAll(SNAPSHOT_URL_REGEX));
          if (cookedMatches.length > 0) {
            console.log(`🔍 [TOPIC] Post ${i + 1}, Preview ${previewIdx + 1}: Found ${cookedMatches.length} URL(s) in cooked HTML (preview container exists but links not loaded yet)`);
            cookedMatches.forEach((match, matchIdx) => {
              const url = match[0];
              const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
              const isTestnet = decodedUrl.includes('testnet.snapshot.box');
              if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(url)) {
                proposals.snapshot.push(decodedUrl);
                foundPreviewLinks++;
                console.log(`✅ [TOPIC] Found Snapshot link (from cooked HTML, preview ${previewIdx + 1}, match ${matchIdx + 1}):`, decodedUrl, isTestnet ? "(testnet)" : "(production)");
              }
            });
          }
        }
      });
      if (foundPreviewLinks > 0) {
        console.log(`✅ [TOPIC] Post ${i + 1}: Found ${foundPreviewLinks} Snapshot link(s) via preview container check`);
      }
      
      // Find Aave Governance Forum links (single-link strategy)
      // Match: governance.aave.com/t/{slug}/{id} or governance.aave.com/t/{slug}
      const forumMatches = combinedContent.match(AAVE_FORUM_URL_REGEX);
      if (forumMatches) {
        forumMatches.forEach(url => {
          // Decode HTML entities to normalize URLs
          const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
          // Clean up URL (remove trailing slashes, fragments, etc.)
          const cleanUrl = decodedUrl.replace(/[\/#\?].*$/, '').replace(/\/$/, '');
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
            // Decode HTML entities to normalize URLs
            const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
            const cleanUrl = decodedUrl.replace(/[\/#\?].*$/, '').replace(/\/$/, '');
            if (!proposals.forum.includes(cleanUrl) && !proposals.forum.includes(url)) {
              proposals.forum.push(cleanUrl);
              console.log("✅ [TOPIC] Found Aave Governance Forum link (flexible match):", cleanUrl);
            }
          });
        }
      }
      
      // Find Snapshot links (direct links, or will be extracted from forum)
      const snapshotMatches = combinedContent.match(SNAPSHOT_URL_REGEX);
      console.log(`🔍 [TOPIC] Post ${i + 1}: Snapshot regex found ${snapshotMatches ? snapshotMatches.length : 0} match(es)`);
      if (snapshotMatches) {
        snapshotMatches.forEach((url, idx) => {
          console.log(`🔍 [TOPIC] Post ${i + 1}, Snapshot match ${idx + 1}: "${url}"`);
          // Decode HTML entities to normalize URLs
          const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
          // Include Aave Snapshot space links OR testnet Snapshot URLs
          const isAaveSpace = decodedUrl.includes('aave.eth') || decodedUrl.includes('aavedao.eth');
          const isTestnet = decodedUrl.includes('testnet.snapshot.box');
          console.log(`🔍 [TOPIC] Post ${i + 1}: Snapshot URL check - isAaveSpace: ${isAaveSpace}, isTestnet: ${isTestnet}`);
          
          // CRITICAL: Accept ALL Snapshot URLs, not just Aave spaces
          // The space filter was too restrictive
          if (isAaveSpace || isTestnet || decodedUrl.includes('snapshot.org') || decodedUrl.includes('snapshot.box')) {
            if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(url)) {
              proposals.snapshot.push(decodedUrl);
              console.log("✅ [TOPIC] Found Snapshot link in post:", decodedUrl);
            }
          } else {
            // Still add it - be more permissive
            if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(url)) {
              proposals.snapshot.push(decodedUrl);
              console.log("✅ [TOPIC] Added Snapshot link (permissive mode):", decodedUrl);
            }
          }
        });
      } else {
        // Debug: Check if Snapshot URL pattern exists in content but regex didn't match
        if (combinedContent.includes('snapshot.org') || combinedContent.includes('snapshot.box')) {
          const snapshotIndex = Math.max(
            combinedContent.indexOf('snapshot.org'),
            combinedContent.indexOf('snapshot.box')
          );
          if (snapshotIndex >= 0) {
            const snippet = combinedContent.substring(Math.max(0, snapshotIndex - 50), Math.min(combinedContent.length, snapshotIndex + 200));
            console.log(`⚠️ [TOPIC] Post ${i + 1}: Snapshot URL pattern found in content but regex didn't match. Snippet: "${snippet}"`);
            // Try flexible pattern
            const flexiblePattern = /https?:\/\/[^\s<>"']*snapshot\.(?:org|box)[^\s<>"']*/gi;
            const flexibleMatches = combinedContent.match(flexiblePattern);
            if (flexibleMatches) {
              flexibleMatches.forEach(url => {
                const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
                if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(url)) {
                  proposals.snapshot.push(decodedUrl);
                  console.log("✅ [TOPIC] Found Snapshot link via flexible pattern:", decodedUrl);
                }
              });
            }
          }
        }
      }
      
      // Also check for Snapshot links in href attributes (including testnet)
      const snapshotLinks = post.querySelectorAll('a[href*="snapshot.org"], a[href*="snapshot.box"], a[href*="testnet.snapshot.box"]');
      snapshotLinks.forEach(link => {
        const href = link.href || link.getAttribute('href') || '';
        if (href && (href.includes('snapshot.org') || href.includes('snapshot.box') || href.includes('testnet.snapshot.box'))) {
          const decodedUrl = href.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
          const isTestnet = decodedUrl.includes('testnet.snapshot.box');
          if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(href)) {
            proposals.snapshot.push(decodedUrl);
            console.log("✅ [TOPIC] Found Snapshot link (via href):", decodedUrl, isTestnet ? "(testnet)" : "(production)");
          }
        }
      });
      
      // CRITICAL: Check for links directly in post content (before oneboxes are rendered)
      // This catches Snapshot URLs even if oneboxes haven't been created yet
      const directLinks = post.querySelectorAll('a[href]');
      directLinks.forEach(link => {
        const href = link.href || link.getAttribute('href') || '';
        if (href && (href.includes('snapshot.org') || href.includes('snapshot.box') || href.includes('testnet.snapshot.box'))) {
          // Verify it matches Snapshot URL pattern
          SNAPSHOT_URL_REGEX.lastIndex = 0;
          if (SNAPSHOT_URL_REGEX.test(href)) {
            const decodedUrl = href.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
            const isTestnet = decodedUrl.includes('testnet.snapshot.box');
            if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(href)) {
              proposals.snapshot.push(decodedUrl);
              console.log(`✅ [TOPIC] Found Snapshot link (direct link in post ${i + 1}):`, decodedUrl, isTestnet ? "(testnet)" : "(production)");
            }
          }
        }
      });
      
      // CRITICAL: Check oneboxes and embedded content for Snapshot URLs
      // Oneboxes are where Discourse embeds URLs, and this is where Snapshot URLs often appear
      const snapshotOneboxes = post.querySelectorAll('.onebox, .onebox-body, [class*="onebox"], .cooked .onebox');
      console.log(`🔍 [TOPIC] Post ${i + 1}: Found ${snapshotOneboxes.length} onebox(es) to scan for Snapshot URLs`);
      snapshotOneboxes.forEach((onebox, oneboxIdx) => {
        const oneboxText = onebox.textContent || onebox.innerText || '';
        const oneboxHtml = onebox.innerHTML || '';
        const oneboxContent = oneboxText + ' ' + oneboxHtml;
        
        // Check for Snapshot URLs in onebox (including testnet)
        if (oneboxContent.includes('snapshot.org') || oneboxContent.includes('snapshot.box') || oneboxContent.includes('testnet.snapshot.box')) {
          console.log(`🔍 [TOPIC] Post ${i + 1}, Onebox ${oneboxIdx + 1}: Contains Snapshot URL pattern`);
          SNAPSHOT_URL_REGEX.lastIndex = 0;
          const oneboxSnapshotMatches = oneboxContent.match(SNAPSHOT_URL_REGEX);
          if (oneboxSnapshotMatches) {
            console.log(`✅ [TOPIC] Post ${i + 1}, Onebox ${oneboxIdx + 1}: Found ${oneboxSnapshotMatches.length} Snapshot URL(s) via regex`);
            oneboxSnapshotMatches.forEach((url, urlIdx) => {
              const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
              const isTestnet = decodedUrl.includes('testnet.snapshot.box');
              if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(url)) {
                proposals.snapshot.push(decodedUrl);
                console.log(`✅ [TOPIC] Found Snapshot link (via onebox ${oneboxIdx + 1}, URL ${urlIdx + 1}):`, decodedUrl, isTestnet ? "(testnet)" : "(production)");
              }
            });
          } else {
            // Try flexible pattern if main regex fails (includes testnet)
            const flexiblePattern = /https?:\/\/[^\s<>"']*snapshot\.(?:org|box)[^\s<>"']*/gi;
            const flexibleMatches = oneboxContent.match(flexiblePattern);
            if (flexibleMatches) {
              console.log(`✅ [TOPIC] Post ${i + 1}, Onebox ${oneboxIdx + 1}: Found ${flexibleMatches.length} Snapshot URL(s) via flexible pattern`);
              flexibleMatches.forEach(url => {
                const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
                const isTestnet = decodedUrl.includes('testnet.snapshot.box');
                if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(url)) {
                  proposals.snapshot.push(decodedUrl);
                  console.log(`✅ [TOPIC] Found Snapshot link (via onebox flexible pattern):`, decodedUrl, isTestnet ? "(testnet)" : "(production)");
                }
              });
            } else {
              // Also check href attributes in onebox links (including testnet)
              const oneboxLinks = onebox.querySelectorAll('a[href*="snapshot.org"], a[href*="snapshot.box"], a[href*="testnet.snapshot.box"]');
              oneboxLinks.forEach(link => {
                const href = link.href || link.getAttribute('href') || '';
                if (href && (href.includes('snapshot.org') || href.includes('snapshot.box') || href.includes('testnet.snapshot.box'))) {
                  const decodedUrl = href.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
                  const isTestnet = decodedUrl.includes('testnet.snapshot.box');
                  if (!proposals.snapshot.includes(decodedUrl) && !proposals.snapshot.includes(href)) {
                    proposals.snapshot.push(decodedUrl);
                    console.log(`✅ [TOPIC] Found Snapshot link (via onebox link href):`, decodedUrl, isTestnet ? "(testnet)" : "(production)");
                  }
                }
              });
            }
          }
        }
      });
      
      // Find AIP links (direct links, or will be extracted from forum)
      // Method 1: Check href attributes in links (more reliable for HTML)
      const aipLinks = post.querySelectorAll('a[href*="vote.onaave.com"], a[href*="app.aave.com/governance"], a[href*="governance.aave.com/aip/"]');
      console.log(`🔍 [TOPIC] Post ${i + 1}: Found ${aipLinks.length} AIP link(s) via href selector`);
      aipLinks.forEach((link, idx) => {
        const href = link.href || link.getAttribute('href') || '';
        console.log(`🔍 [TOPIC] Post ${i + 1}, Link ${idx + 1}: href="${href}"`);
        // Check for AIP URLs but exclude forum topic URLs (governance.aave.com/t/)
        if (href && 
            (href.includes('vote.onaave.com') || 
             href.includes('app.aave.com/governance') || 
             (href.includes('governance.aave.com') && !href.includes('governance.aave.com/t/') && href.includes('governance.aave.com/aip/')))) {
          // Decode HTML entities
          const decodedUrl = href.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
          if (!proposals.aip.includes(decodedUrl) && !proposals.aip.includes(href)) {
            proposals.aip.push(decodedUrl);
            console.log("✅ [TOPIC] Found AIP link (via href):", decodedUrl);
          }
        }
      });
      
      // Method 2: Use regex on combined content (handles plain text URLs)
      // Reset regex lastIndex to avoid issues with global regex
      AIP_URL_REGEX.lastIndex = 0;
      const aipMatches = combinedContent.match(AIP_URL_REGEX);
      console.log(`🔍 [TOPIC] Post ${i + 1}: AIP regex found ${aipMatches ? aipMatches.length : 0} match(es)`);
      if (aipMatches) {
        aipMatches.forEach((url, idx) => {
          console.log(`🔍 [TOPIC] Post ${i + 1}, Match ${idx + 1}: "${url}"`);
          // Decode HTML entities (e.g., &amp; -> &) to normalize URLs
          // This prevents the same URL from being treated as different due to HTML encoding
          const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
          
          // Explicitly exclude forum topic URLs (governance.aave.com/t/) - these are NOT AIP proposal URLs
          if (decodedUrl.includes('governance.aave.com/t/')) {
            console.log(`⚠️ [TOPIC] Skipping forum topic URL (not an AIP proposal): ${decodedUrl}`);
            return; // Skip this URL
          }
          
          if (!proposals.aip.includes(decodedUrl) && !proposals.aip.includes(url)) {
            proposals.aip.push(decodedUrl);
            console.log("✅ [TOPIC] Found AIP link (via regex):", decodedUrl);
          }
        });
      } else {
        // Debug: Check if AIP URL pattern exists in content
        if (combinedContent.includes('vote.onaave.com') || combinedContent.includes('app.aave.com/governance') || combinedContent.includes('governance.aave.com/aip/')) {
          const aipIndex = Math.max(
            combinedContent.indexOf('vote.onaave.com'),
            combinedContent.indexOf('app.aave.com/governance'),
            combinedContent.indexOf('governance.aave.com/aip/')
          );
          if (aipIndex >= 0) {
            const snippet = combinedContent.substring(Math.max(0, aipIndex - 50), Math.min(combinedContent.length, aipIndex + 200));
            console.log(`⚠️ [TOPIC] Post ${i + 1}: AIP URL pattern found in content but regex didn't match. Snippet: "${snippet}"`);
          }
        }
      }
      
      // Method 3: Check oneboxes and embedded content for AIP URLs
      const oneboxes = post.querySelectorAll('.onebox, .onebox-body, [class*="onebox"]');
      oneboxes.forEach(onebox => {
        const oneboxText = onebox.textContent || onebox.innerText || '';
        const oneboxHtml = onebox.innerHTML || '';
        const oneboxContent = oneboxText + ' ' + oneboxHtml;
        
        // Check for AIP URLs in onebox (exclude forum topic URLs)
        if (oneboxContent.includes('vote.onaave.com') || 
            oneboxContent.includes('app.aave.com/governance') || 
            (oneboxContent.includes('governance.aave.com/aip/') && !oneboxContent.includes('governance.aave.com/t/'))) {
          AIP_URL_REGEX.lastIndex = 0;
          const oneboxMatches = oneboxContent.match(AIP_URL_REGEX);
          if (oneboxMatches) {
            oneboxMatches.forEach(url => {
              const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
              if (!proposals.aip.includes(decodedUrl) && !proposals.aip.includes(url)) {
                proposals.aip.push(decodedUrl);
                console.log("✅ [TOPIC] Found AIP link (via onebox):", decodedUrl);
              }
            });
          }
        }
      });
      
      // Method 4: Also check for AIP links in a more flexible way (in case regex misses some)
      // Check for vote.onaave.com, app.aave.com/governance, or governance.aave.com/aip/ (exclude forum topic URLs)
      if (combinedContent.includes('vote.onaave.com') || 
          combinedContent.includes('app.aave.com/governance') || 
          (combinedContent.includes('governance.aave.com/aip/') && !combinedContent.includes('governance.aave.com/t/'))) {
        // More robust regex that handles URLs with query parameters and HTML encoding
        // Use the same pattern as AIP_URL_REGEX for consistency
        const flexibleAipRegex = /https?:\/\/(?:www\.)?(?:vote\.onaave\.com|app\.aave\.com\/governance|governance\.aave\.com\/aip\/)[^\s<>"']+/gi;
        flexibleAipRegex.lastIndex = 0; // Reset regex
        const flexibleAipMatch = combinedContent.match(flexibleAipRegex);
        if (flexibleAipMatch) {
          flexibleAipMatch.forEach(url => {
            // Decode HTML entities to normalize URLs
            const decodedUrl = url.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
            // Only add if it matches AIP pattern and not already in list
            if ((decodedUrl.includes('vote.onaave.com') || decodedUrl.includes('app.aave.com/governance') || decodedUrl.includes('governance.aave.com/aip/')) &&
                !proposals.aip.includes(decodedUrl) && !proposals.aip.includes(url)) {
              proposals.aip.push(decodedUrl);
              console.log("✅ [TOPIC] Found AIP link (flexible match):", decodedUrl);
            }
          });
        } else {
          // Debug: log if we expected to find AIP URLs but flexible match also failed
          console.log(`⚠️ [TOPIC] Post ${i + 1}: AIP URL pattern detected but flexible regex also didn't match`);
        }
      }
    }
    
    // Final summary with detailed logging
    console.log("✅ [TOPIC] ========== PROPOSAL DETECTION SUMMARY ==========");
    console.log(`✅ [TOPIC] Found ${proposals.snapshot.length} Snapshot proposal(s):`, proposals.snapshot);
    console.log(`✅ [TOPIC] Found ${proposals.aip.length} AIP proposal(s):`, proposals.aip);
    console.log(`✅ [TOPIC] Found ${proposals.forum.length} Forum link(s):`, proposals.forum);
    console.log("✅ [TOPIC] ================================================");
    
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
    
    // If no proposals found, provide helpful debugging info
    if (proposals.snapshot.length === 0 && proposals.aip.length === 0 && proposals.forum.length === 0) {
      console.warn("⚠️ [TOPIC] No proposals found! This might mean:");
      console.warn("   1. The post doesn't contain any proposal URLs");
      console.warn("   2. The URLs are in a format not recognized by the regex patterns");
      console.warn("   3. The content is lazy-loaded and not yet in the DOM");
      console.warn("   Check the console logs above for detailed detection attempts");
    } else if (proposals.snapshot.length === 0 && proposals.aip.length === 0) {
      console.warn("⚠️ [TOPIC] Found forum links but no Snapshot or AIP proposals.");
      console.warn("   If the forum link contains proposals, they should be extracted from the forum thread.");
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
    
    // CRITICAL: Prevent Discourse's viewport tracker from hiding this widget
    errorWidget.setAttribute("data-cloak", "false");
    errorWidget.setAttribute("data-skip-cloak", "true");
    errorWidget.setAttribute("data-no-cloak", "true");
    
    // CRITICAL: Mark error widget as visible in cache immediately when created
    markWidgetAsVisibleInCache(errorWidget);
    
    errorWidget.innerHTML = `
      <div class="tally-status-widget" style="padding: 16px; border: 1px solid #fca5a5; border-radius: 8px; background: #fff;">
        <div style="margin-bottom: 12px; font-size: 1em; font-weight: 700; color: #dc2626;">⚠️ Network Error</div>
        <div style="margin-bottom: 12px; font-size: 0.9em; line-height: 1.5; color: #6b7280;">
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
    
    // Ensure error widget stays visible after insertion
    markWidgetAsVisibleInCache(errorWidget);
  }

  // Helper function to preserve scroll position during DOM operations
  // Prevents auto-scrolling when widgets are inserted into the page
  function preserveScrollPosition(callback) {
    // Save current scroll position BEFORE any DOM operations
    // Use initial scroll position if we're still in the scroll lock period
    const scrollX = scrollLocked ? initialScrollX : (window.pageXOffset || window.scrollX || document.documentElement.scrollLeft || 0);
    const scrollY = scrollLocked ? initialScrollY : (window.pageYOffset || window.scrollY || document.documentElement.scrollTop || 0);
    
    // Mark that widgets are being inserted
    widgetsInserting = true;
    
    // Execute the callback (widget insertion)
    callback();
    
    // Immediately restore scroll position synchronously
    window.scrollTo(scrollX, scrollY);
    document.documentElement.scrollLeft = scrollX;
    document.documentElement.scrollTop = scrollY;
    document.body.scrollLeft = scrollX;
    document.body.scrollTop = scrollY;
    
    // Keep preventing scroll for a bit after insertion
    setTimeout(() => {
      widgetsInserting = false;
    }, 500);
    
    // Restore multiple times using different methods to ensure it sticks
    // Use setTimeout(0) for immediate execution after current call stack
    setTimeout(() => {
      window.scrollTo(scrollX, scrollY);
      document.documentElement.scrollLeft = scrollX;
      document.documentElement.scrollTop = scrollY;
      document.body.scrollLeft = scrollX;
      document.body.scrollTop = scrollY;
    }, 0);
    
    // Use requestAnimationFrame to ensure it happens after any browser auto-scroll
    requestAnimationFrame(() => {
      window.scrollTo(scrollX, scrollY);
      document.documentElement.scrollLeft = scrollX;
      document.documentElement.scrollTop = scrollY;
      document.body.scrollLeft = scrollX;
      document.body.scrollTop = scrollY;
      // Also restore in next frame as backup
      requestAnimationFrame(() => {
        window.scrollTo(scrollX, scrollY);
        document.documentElement.scrollLeft = scrollX;
        document.documentElement.scrollTop = scrollY;
        document.body.scrollLeft = scrollX;
        document.body.scrollTop = scrollY;
        // Final restore after a short delay
        setTimeout(() => {
          window.scrollTo(scrollX, scrollY);
          document.documentElement.scrollLeft = scrollX;
          document.documentElement.scrollTop = scrollY;
          document.body.scrollLeft = scrollX;
          document.body.scrollTop = scrollY;
        }, 10);
        // Extra restore after longer delay
        setTimeout(() => {
          window.scrollTo(scrollX, scrollY);
          document.documentElement.scrollLeft = scrollX;
          document.documentElement.scrollTop = scrollY;
        }, 50);
      });
    });
  }
  
  // CRITICAL: Ensure all widgets are visible immediately after creation
  // This function ensures widgets appear on page load and stay visible on ALL screen sizes
  // This is called after widgets are created and periodically to prevent them from being hidden
  // Uses a cache to prevent unnecessary DOM updates that cause blinking
  const widgetVisibilityCache = new WeakMap();
  
  // Helper function to immediately mark a widget as visible in cache when it's created
  // This prevents unnecessary visibility checks during scroll
  function markWidgetAsVisibleInCache(widget) {
    if (widget && widget.classList && widget.classList.contains('tally-status-widget-container')) {
      widgetVisibilityCache.set(widget, {
        display: 'block',
        visibility: 'visible',
        opacity: '1',
        isHidden: false
      });
    }
  }
  
  function ensureAllWidgetsVisible() {
    const allWidgets = document.querySelectorAll('.tally-status-widget-container');
    if (allWidgets.length === 0) {
      return; // No widgets yet
    }
    
    const isMobileCheck = window.innerWidth <= 1024;
    
    allWidgets.forEach(widget => {
      // CRITICAL: Always prevent Discourse cloaking and exclude from viewport tracking
      widget.setAttribute('data-cloak', 'false');
      widget.setAttribute('data-skip-cloak', 'true');
      widget.setAttribute('data-no-cloak', 'true');
      widget.setAttribute('data-viewport', 'false');
      widget.setAttribute('data-exclude-viewport', 'true');
      widget.setAttribute('data-no-viewport-track', 'true');
      widget.classList.add('no-viewport-track');
      
      const computedStyle = window.getComputedStyle(widget);
      const isHidden = computedStyle.display === 'none' || computedStyle.visibility === 'hidden' || computedStyle.opacity === '0';
      
      // Check cache to see if we've already applied these styles (prevents blinking)
      const cachedState = widgetVisibilityCache.get(widget);
      
      // Only update if widget is hidden OR if state changed (prevents unnecessary updates)
      if (isHidden || !cachedState || cachedState.isHidden !== isHidden) {
        if (isHidden) {
          console.log(`🔵 [WIDGET] Widget was hidden, forcing visibility - display: ${computedStyle.display}, visibility: ${computedStyle.visibility}`);
        }
        widget.style.setProperty('display', 'block', 'important');
        widget.style.setProperty('visibility', 'visible', 'important');
        widget.style.setProperty('opacity', '1', 'important');
        widget.classList.remove('hidden', 'd-none', 'is-hidden', 'cloaked');
        
        // Ensure cloaking is disabled
        widget.setAttribute('data-cloak', 'false');
        widget.setAttribute('data-skip-cloak', 'true');
        widget.setAttribute('data-no-cloak', 'true');
        
        // Update cache - use the helper function for consistency
        markWidgetAsVisibleInCache(widget);
        
        if (isHidden) {
          console.log(`✅ [WIDGET] Forced visibility for widget`);
        }
      }
    });
    
    // Also ensure container wrapper is visible and positioned correctly
    // Use cache to prevent unnecessary updates
    const container = document.querySelector('.governance-widgets-wrapper');
    if (container) {
      const containerStyle = window.getComputedStyle(container);
      const containerIsHidden = containerStyle.display === 'none' || containerStyle.visibility === 'hidden' || containerStyle.opacity === '0';
      
      // CRITICAL: Always prevent Discourse cloaking and exclude from viewport tracking
      container.setAttribute('data-cloak', 'false');
      container.setAttribute('data-skip-cloak', 'true');
      container.setAttribute('data-no-cloak', 'true');
      container.setAttribute('data-viewport', 'false');
      container.setAttribute('data-exclude-viewport', 'true');
      container.setAttribute('data-no-viewport-track', 'true');
      container.classList.add('no-viewport-track');
      
      // Only update if container is hidden (prevents blinking)
      if (containerIsHidden) {
        container.style.setProperty('display', 'flex', 'important');
        container.style.setProperty('visibility', 'visible', 'important');
        container.style.setProperty('opacity', '1', 'important');
        container.classList.remove('cloaked');
        
        // Ensure cloaking is disabled
        container.setAttribute('data-cloak', 'false');
        container.setAttribute('data-skip-cloak', 'true');
        container.setAttribute('data-no-cloak', 'true');
        
        if (isMobileCheck) {
          // Mobile/Tablet: Relative positioning (inline)
          container.style.setProperty('position', 'relative', 'important');
          container.style.setProperty('width', '100%', 'important');
          container.style.setProperty('max-width', '100%', 'important');
        } else {
          // Desktop: Fixed positioning (right side)
          container.style.setProperty('position', 'fixed', 'important');
          container.style.setProperty('z-index', '500', 'important');
          // CRITICAL: Keep width fixed at 320px to prevent width changes
          container.style.setProperty('width', '320px', 'important');
          container.style.setProperty('max-width', '320px', 'important');
        }
      }
    }
    
    // Also ensure AIP widgets specifically
    ensureAIPWidgetsVisible();
  }

  // Ensure ALL widgets remain visible after scroll events
  // CRITICAL: ALL widget types should ALWAYS be visible once found:
  // - AIP widgets (Aave Improvement Proposals)
  // - Snapshot widgets (Temp Check, ARFC, and generic Snapshot)
  // - Testnet Snapshot widgets (testnet.snapshot.box)
  // This function should be called frequently to prevent widgets from being hidden
  // UPDATED: Now ensures ALL widgets (AIP, Snapshot, Temp Check, ARFC, and Testnet) stay visible
  function ensureAIPWidgetsVisible() {
    // Only run on topic pages - don't process widgets on other pages
    const isTopicPage = window.location.pathname.match(/^\/t\//);
    if (!isTopicPage) {
      return; // Don't process widgets if not on a topic page
    }
    const allWidgets = document.querySelectorAll('.tally-status-widget-container');
    let aipWidgetCount = 0;
    let snapshotWidgetCount = 0;
    let testnetWidgetCount = 0;
    let tempCheckWidgetCount = 0;
    let arfcWidgetCount = 0;
    let hiddenAIPCount = 0;
    let hiddenSnapshotCount = 0;
    
    allWidgets.forEach(widget => {
      const widgetType = widget.getAttribute('data-proposal-type');
      const widgetTypeAttr = widget.getAttribute('data-widget-type');
      const hasAIP = widget.querySelector('.governance-stage[data-stage="aip"]') !== null;
      const hasTempCheck = widget.querySelector('.governance-stage[data-stage="temp-check"]') !== null;
      const hasARFC = widget.querySelector('.governance-stage[data-stage="arfc"]') !== null;
      const url = widget.getAttribute('data-tally-url') || '';
      const isTestnet = widget.getAttribute('data-is-testnet') === 'true' || url.includes('testnet.snapshot.box');
      const isAIPUrl = url.includes('vote.onaave.com') || url.includes('app.aave.com/governance') || url.includes('governance.aave.com/aip/');
      const isAIPWidget = widgetType === 'aip' || widgetTypeAttr === 'aip' || hasAIP || isAIPUrl;
      
      // Count widget types for logging
      if (isAIPWidget) {
        aipWidgetCount++;
      } else {
        snapshotWidgetCount++;
        if (isTestnet) {
          testnetWidgetCount++;
        }
        if (hasTempCheck) {
          tempCheckWidgetCount++;
        }
        if (hasARFC) {
          arfcWidgetCount++;
        }
      }
      
      // CRITICAL: ALL widgets (AIP, Snapshot, Temp Check, ARFC, Testnet) should ALWAYS be visible
      // This ensures widgets appear on page load and stay visible, not just when scrolling
      // Only update if widget is actually hidden (prevents blinking from unnecessary DOM updates)
      const computedStyle = window.getComputedStyle(widget);
      const isHidden = computedStyle.display === 'none' || computedStyle.visibility === 'hidden' || computedStyle.opacity === '0';
      
      if (isHidden) {
        widget.style.setProperty('display', 'block', 'important');
        widget.style.setProperty('visibility', 'visible', 'important');
        widget.style.setProperty('opacity', '1', 'important');
        widget.classList.remove('hidden', 'd-none', 'is-hidden');
        
        // Check if it's actually visible now
        const newComputedStyle = window.getComputedStyle(widget);
        if (newComputedStyle.display === 'none' || newComputedStyle.visibility === 'hidden' || newComputedStyle.opacity === '0') {
          if (isAIPWidget) {
            hiddenAIPCount++;
            console.warn(`⚠️ [AIP] AIP widget still hidden after force visibility attempt - display: ${newComputedStyle.display}, visibility: ${newComputedStyle.visibility}, opacity: ${newComputedStyle.opacity}`);
          } else {
            hiddenSnapshotCount++;
            const widgetTypeLabel = isTestnet ? 'Testnet Snapshot' : (hasTempCheck ? 'Temp Check' : (hasARFC ? 'ARFC' : 'Snapshot'));
            console.warn(`⚠️ [${widgetTypeLabel}] ${widgetTypeLabel} widget still hidden after force visibility attempt - display: ${newComputedStyle.display}, visibility: ${newComputedStyle.visibility}, opacity: ${newComputedStyle.opacity}`);
          }
        }
      }
    });
    
    // Log summary of widget types found
    if (aipWidgetCount > 0 || snapshotWidgetCount > 0) {
      const widgetTypes = [];
      if (aipWidgetCount > 0) {
        widgetTypes.push(`${aipWidgetCount} AIP`);
      }
      if (tempCheckWidgetCount > 0) {
        widgetTypes.push(`${tempCheckWidgetCount} Temp Check`);
      }
      if (arfcWidgetCount > 0) {
        widgetTypes.push(`${arfcWidgetCount} ARFC`);
      }
      if (testnetWidgetCount > 0) {
        widgetTypes.push(`${testnetWidgetCount} Testnet`);
      }
      if (snapshotWidgetCount > tempCheckWidgetCount + arfcWidgetCount + testnetWidgetCount) {
        widgetTypes.push(`${snapshotWidgetCount - tempCheckWidgetCount - arfcWidgetCount - testnetWidgetCount} Snapshot`);
      }
      if (widgetTypes.length > 0) {
        console.log(`✅ [WIDGET] Ensured visibility for ${widgetTypes.join(', ')} widget(s)`);
      }
    }
    
    if (aipWidgetCount > 0) {
      if (hiddenAIPCount > 0) {
        console.warn(`⚠️ [AIP] ${hiddenAIPCount} of ${aipWidgetCount} AIP widget(s) are still hidden after force visibility`);
      }
    }
    if (snapshotWidgetCount > 0) {
      if (hiddenSnapshotCount > 0) {
        console.warn(`⚠️ [SNAPSHOT] ${hiddenSnapshotCount} of ${snapshotWidgetCount} Snapshot widget(s) are still hidden after force visibility`);
      }
    }
  }

  function hideWidgetIfNoProposal() {
    // CRITICAL: This function is now DISABLED - widgets should ALWAYS remain visible once created
    // All widgets (both Snapshot and AIP) are topic-level and should persist regardless of scroll position
    // This ensures widgets appear on page load and stay visible, matching user expectations
    console.log("🔵 [WIDGET] hideWidgetIfNoProposal called - but widgets are now always visible (not hiding)");
    
    // Instead of hiding widgets, just ensure all widgets are visible
    const allWidgets = document.querySelectorAll('.tally-status-widget-container');
    allWidgets.forEach(widget => {
      widget.style.setProperty('display', 'block', 'important');
      widget.style.setProperty('visibility', 'visible', 'important');
      widget.style.setProperty('opacity', '1', 'important');
      widget.classList.remove('hidden', 'd-none', 'is-hidden');
    });
    
    // Ensure AIP widgets are visible (this also helps with Snapshot widgets)
    ensureAIPWidgetsVisible();
    
    // Reset current visible proposal (but widgets remain visible)
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
    
    // Fetch type from API instead of determining from URL pattern
    // This ensures we get the actual type from the API response
    const typeResult = await fetchProposalTypeFromAPI(url);
    if (!typeResult) {
      console.warn("❌ Could not determine proposal type from API for URL:", url);
      // Fallback to URL pattern matching if API fails
    let type = null;
    if (url.includes('snapshot.org') || url.includes('testnet.snapshot.box')) {
      type = 'snapshot';
    } else if (url.includes('governance.aave.com') || url.includes('vote.onaave.com') || url.includes('app.aave.com/governance')) {
      type = 'aip';
    }
    if (!type) {
        // Silently skip proposals that are not AIP or Snapshot - don't show errors
      return null;
    }
    return await fetchProposalDataByType(url, type, forceRefresh);
    }
    
    // Only process if type is AIP or Snapshot - silently skip others
    if (typeResult.type === 'snapshot' || typeResult.type === 'aip') {
      return await fetchProposalDataByType(url, typeResult.type, forceRefresh);
    } else {
      // Silently skip proposals that are not AIP or Snapshot - don't show errors
      return null;
    }
  }

  // Fetch proposal type from API by trying both Snapshot and AIP endpoints
  // Returns the type determined from API response, not URL patterns
  async function fetchProposalTypeFromAPI(url) {
    if (!url) {return null;}
    
    console.log("🔍 [TYPE] Fetching proposal type from API for URL:", url);
    
    // Try to extract identifiers for both types
    const snapshotInfo = extractSnapshotProposalInfo(url);
    const aipInfo = extractAIPProposalInfo(url);
    
    // If we can extract Snapshot info, try Snapshot API first
    if (snapshotInfo) {
      try {
        const graphqlEndpoint = snapshotInfo.isTestnet ? SNAPSHOT_TESTNET_GRAPHQL_ENDPOINT : SNAPSHOT_GRAPHQL_ENDPOINT;
        let cleanSpace = snapshotInfo.space;
        if (cleanSpace.startsWith('s:')) {
          cleanSpace = cleanSpace.substring(2);
        }
        if (cleanSpace.startsWith('s-tn:')) {
          cleanSpace = cleanSpace.substring(5);
        }
        const fullProposalId = `${cleanSpace}/${snapshotInfo.proposalId}`;
        
        // Lightweight query to check if proposal exists and get its type from API
        const query = `
          query ProposalType($id: String!) {
            proposal(id: $id) {
              id
              type
              space {
                id
                name
              }
            }
          }
        `;
        
        const response = await fetchWithRetry(graphqlEndpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            query,
            variables: { id: fullProposalId }
          }),
        });
        
        if (response.ok) {
          const result = await response.json();
          if (result.data?.proposal) {
            const apiType = result.data.proposal.type || 'snapshot';
            console.log("✅ [TYPE] Fetched type from Snapshot API:", apiType);
            return {
              type: 'snapshot',
              apiType, // The type field from Snapshot API response
              proposalInfo: snapshotInfo
            };
          }
        }
      } catch {
        console.log("🔵 [TYPE] Snapshot API check failed, trying AIP...");
      }
    }
    
    // If Snapshot failed or we have AIP info, try AIP API
    if (aipInfo) {
      try {
        // Try a lightweight check on AIP - attempt to fetch proposal metadata
        const proposalId = aipInfo.proposalId;
        if (proposalId) {
          // Try fetching from subgraph first (lightweight check)
          const subgraphResult = await fetchAIPFromSubgraph(proposalId);
          if (subgraphResult) {
            console.log("✅ [TYPE] Fetched type from AIP API: aip");
            return {
              type: 'aip',
              proposalInfo: aipInfo
            };
          }
          
          // Try on-chain as fallback
          const onChainResult = await fetchAIPFromOnChain(proposalId, aipInfo.urlSource || 'app.aave.com');
          if (onChainResult) {
            console.log("✅ [TYPE] Fetched type from AIP on-chain: aip");
            return {
              type: 'aip',
              proposalInfo: aipInfo
            };
          }
        }
      } catch {
        console.log("🔵 [TYPE] AIP API check failed");
      }
    }
    
    // Fallback: if we have extracted info but API calls failed, use extracted type
    if (snapshotInfo) {
      console.log("⚠️ [TYPE] Using extracted Snapshot type (API fetch failed)");
      return {
        type: 'snapshot',
        proposalInfo: snapshotInfo
      };
    }
    
    if (aipInfo) {
      console.log("⚠️ [TYPE] Using extracted AIP type (API fetch failed)");
      return {
        type: 'aip',
        proposalInfo: aipInfo
      };
    }
    
    console.warn("❌ [TYPE] Could not determine proposal type from API or URL:", url);
    return null;
  }

  // Fetch proposal data based on type (Tally, Snapshot, or AIP)
  // If type is not provided or is 'auto', fetches type from API first
  async function fetchProposalDataByType(url, type, forceRefresh = false) {
    try {
      const cacheKey = url;
      
      // First check localStorage cache (persistent across page reloads)
      if (!forceRefresh) {
        const localStorageData = getCachedProposalData(url);
        if (localStorageData) {
          // Also update in-memory cache for faster access
          proposalCache.set(cacheKey, localStorageData);
          return localStorageData;
        }
      }
      
      // Then check in-memory cache (skip if forceRefresh is true)
      if (!forceRefresh && proposalCache.has(cacheKey)) {
        const cachedData = proposalCache.get(cacheKey);
        const cacheAge = Date.now() - (cachedData._cachedAt || 0);
        if (cacheAge < 5 * 60 * 1000) {
          console.log("🔵 [CACHE] Returning cached data (age:", Math.round(cacheAge / 1000), "seconds)");
          return cachedData;
        }
        proposalCache.delete(cacheKey);
      }
      
      // If type is not provided or is 'auto', fetch type from API
      if (!type || type === 'auto') {
        console.log("🔍 [FETCH] Type not provided, fetching from API...");
        const typeResult = await fetchProposalTypeFromAPI(url);
        if (typeResult) {
          type = typeResult.type;
          console.log("✅ [FETCH] Determined type from API:", type);
        } else {
          console.warn("⚠️ [FETCH] Could not determine type from API, falling back to URL pattern matching");
          // Fallback to URL pattern matching
          const proposalInfo = extractProposalInfo(url);
          if (proposalInfo && proposalInfo.type) {
            type = proposalInfo.type;
          }
        }
      }
      
      // Only process AIP or Snapshot proposals - silently skip other types
      if (type !== 'snapshot' && type !== 'aip') {
        // Silently skip proposals that are not AIP or Snapshot - don't show errors
        return null;
      }
      
      if (type === 'snapshot') {
        const proposalInfo = extractSnapshotProposalInfo(url);
        if (!proposalInfo) {
          return null;
        }
        const result = await fetchSnapshotProposal(proposalInfo.space, proposalInfo.proposalId, cacheKey, proposalInfo.isTestnet);
        // The result already includes apiType from transformSnapshotData
        // which reads proposal.type from the API response
        return result;
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
   
  function extractAIPUrlFromSnapshot(snapshotData) {
    if (!snapshotData) {
      console.log("⚠️ [CASCADE] No snapshotData provided");
      return null;
    }
    
    console.log("🔍 [CASCADE] Searching for AIP link in Snapshot proposal description...");
    console.log("🔍 [CASCADE] Snapshot data keys:", Object.keys(snapshotData));
    
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
      console.log("🔍 [CASCADE] Description length:", description.length, "Body length:", body.length);
    }
    
    if (combinedText.length === 0) {
      console.log("⚠️ [CASCADE] No description/body text found in Snapshot proposal");
      return null;
    }
    
    console.log(`🔍 [CASCADE] Searching in ${combinedText.length} characters of proposal text`);
    
    // Check if text contains AIP URL patterns before regex matching
    const hasVoteOnaave = combinedText.includes('vote.onaave.com');
    const hasAppAave = combinedText.includes('app.aave.com/governance');
    const hasGovernanceAave = combinedText.includes('governance.aave.com/aip/');
    console.log(`🔍 [CASCADE] URL pattern check - vote.onaave.com: ${hasVoteOnaave}, app.aave.com: ${hasAppAave}, governance.aave.com: ${hasGovernanceAave}`);
    
    // ENHANCED: Search for AIP links with multiple patterns
    // Pattern 1: Direct URLs (governance.aave.com or app.aave.com/governance or vote.onaave.com)
    AIP_URL_REGEX.lastIndex = 0; // Reset regex
    const aipUrlMatches = combinedText.match(AIP_URL_REGEX);
    if (aipUrlMatches && aipUrlMatches.length > 0) {
      // Prefer full URLs, extract the first valid one
      const foundUrl = aipUrlMatches[0];
      console.log(`✅ [CASCADE] Found AIP URL in description: ${foundUrl}`);
      return foundUrl;
    } else {
      console.log(`⚠️ [CASCADE] AIP_URL_REGEX didn't match, but patterns detected. Text snippet:`, combinedText.substring(0, 500));
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
          // Prefer Aave Snapshot links or testnet URLs
          const isAaveSpace = foundUrl.includes('aave.eth') || foundUrl.includes('aavedao.eth');
          const isTestnet = foundUrl.includes('testnet.snapshot.box');
          if (isAaveSpace || isTestnet) {
            console.log(`✅ [CASCADE] Found previous Snapshot stage URL: ${foundUrl}`, isTestnet ? "(testnet)" : "(production)");
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
        const isTestnet = url.includes('testnet.snapshot.box');
        const isNotCurrent = !currentUrl || !url.includes(currentUrl.split('/').pop() || '');
        return (isAave || isTestnet) && isNotCurrent;
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
      // Filter for Aave Snapshot space links or testnet URLs (preferred)
      const preferredMatch = snapshotUrlMatches.find(url => {
        const isAave = url.includes('aave.eth') || url.includes('aavedao.eth');
        const isTestnet = url.includes('testnet.snapshot.box');
        return isAave || isTestnet;
      });
      if (preferredMatch) {
        const isTestnet = preferredMatch.includes('testnet.snapshot.box');
        console.log(`✅ [CASCADE] Found Snapshot URL: ${preferredMatch}`, isTestnet ? "(testnet)" : "(production)");
        return preferredMatch;
      }
      // If no preferred link, return first match anyway
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
    // CRITICAL: Prevent concurrent executions - check running flag first
    if (isWidgetSetupRunning) {
      console.log(`🔵 [TOPIC] Widget setup already running - skipping concurrent execution`);
      return Promise.resolve();
    }
    
    // CRITICAL: Early return if widget setup already completed and widgets exist
    // This prevents re-initialization that causes page reload/blinking (especially for Snapshot widgets)
    if (widgetSetupCompleted) {
      const existingWidgets = document.querySelectorAll('.tally-status-widget-container');
      if (existingWidgets.length > 0) {
        console.log(`🔵 [TOPIC] Widget setup already completed - skipping to prevent reload (${existingWidgets.length} widget(s) exist)`);
        // Hide loader if widgets already exist
        hideMainWidgetLoader();
        // CRITICAL: Reset running flag to prevent blocking future legitimate updates
        isWidgetSetupRunning = false;
        return Promise.resolve();
      }
    }
    
    // Set running flag to prevent concurrent executions
    isWidgetSetupRunning = true;
    console.log("🔵 [TOPIC] Setting up widgets - one per proposal URL...");
    
    // Show main loader to prevent blinking while widgets are being fetched
    showMainWidgetLoader();
    
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
    
    // Render widgets immediately if proposals found
    if (allProposals.snapshot.length > 0 || allProposals.aip.length > 0) {
      // CRITICAL: Check if widgets already exist before rendering - prevent duplicate rendering
      const existingWidgetsBeforeRender = document.querySelectorAll('.tally-status-widget-container');
      if (existingWidgetsBeforeRender.length > 0 && widgetSetupCompleted) {
        console.log(`🔵 [TOPIC] Widgets already exist before render (${existingWidgetsBeforeRender.length} widget(s)) - skipping to prevent reload`);
        hideMainWidgetLoader();
        isWidgetSetupRunning = false;
        return Promise.resolve();
      }
      
      // Mark as completed BEFORE rendering to prevent observer-triggered re-executions
      widgetSetupCompleted = true;
      try {
        setupTopicWidgetWithProposals(allProposals);
      } catch (error) {
        console.error("❌ [TOPIC] Error in setupTopicWidgetWithProposals:", error);
        // Reset flags on error to allow retry
        widgetSetupCompleted = false;
        isWidgetSetupRunning = false;
      }
    }
    
    // CRITICAL: Retry to catch lazy-loaded content for BOTH Snapshot and AIP proposals
    // This ensures proposals are detected on page load, not just when scrolling
    // Retry even if some proposals were found, in case there are more in lazy-loaded posts
    // Match tally widget timing: single retry after 1000ms
    const retryDelays = [1000];
    let retryCount = 0;
    const foundUrls = new Set([...allProposals.snapshot, ...allProposals.aip]);
    
    retryDelays.forEach((delay) => {
      setTimeout(() => {
        // CRITICAL: Skip retry if widget setup already completed (prevents re-scanning on scroll)
        // CRITICAL: Also check if widgets exist - if they do, skip retry to prevent reload
        const existingWidgets = document.querySelectorAll('.tally-status-widget-container');
        if (widgetSetupCompleted && existingWidgets.length > 0) {
          console.log(`🔵 [TOPIC] Retry ${retryCount + 1} skipped - widget setup already completed (${existingWidgets.length} widget(s) exist)`);
          // Reset running flag when all retries are done
          if (retryCount === retryDelays.length - 1) {
            isWidgetSetupRunning = false;
          }
          return;
        }
        
        // Also check if widgets exist even if setup not marked as completed
        // This prevents retries from triggering re-renders when widgets already exist
        if (existingWidgets.length > 0) {
          console.log(`🔵 [TOPIC] Retry ${retryCount + 1} skipped - widgets already exist (${existingWidgets.length} widget(s)) - preventing reload`);
          // Mark as completed since widgets exist
          widgetSetupCompleted = true;
          hideMainWidgetLoader();
          // Reset running flag when all retries are done
          if (retryCount === retryDelays.length - 1) {
            isWidgetSetupRunning = false;
          }
          return;
        }
        
        retryCount++;
        console.log(`🔵 [TOPIC] Retry ${retryCount}/${retryDelays.length}: Searching for proposals after ${delay}ms...`);
        
        const retryProposals = findAllProposalsInTopic();
        const retrySnapshotUrls = new Set(retryProposals.snapshot);
        const retryAipUrls = new Set(retryProposals.aip);
        
        // Check if we found any new proposals
        let hasNewProposals = false;
        for (const url of retrySnapshotUrls) {
          if (!foundUrls.has(url)) {
            hasNewProposals = true;
            foundUrls.add(url);
          }
        }
        for (const url of retryAipUrls) {
          if (!foundUrls.has(url)) {
            hasNewProposals = true;
            foundUrls.add(url);
          }
        }
        
        if (hasNewProposals) {
          console.log(`✅ [TOPIC] Found new proposals on retry ${retryCount} - ${retryProposals.snapshot.length} Snapshot, ${retryProposals.aip.length} AIP - updating widgets`);
          // Merge with existing proposals
          const mergedProposals = {
            snapshot: [...new Set([...allProposals.snapshot, ...retryProposals.snapshot])],
            aip: [...new Set([...allProposals.aip, ...retryProposals.aip])],
            forum: [...new Set([...allProposals.forum, ...retryProposals.forum])]
          };
          // Mark as completed BEFORE rendering to prevent observer-triggered re-executions
          widgetSetupCompleted = true;
          try {
            setupTopicWidgetWithProposals(mergedProposals);
          } catch (error) {
            console.error("❌ [TOPIC] Error in setupTopicWidgetWithProposals (retry):", error);
          }
          // Update allProposals so subsequent retries don't duplicate
          allProposals.snapshot = mergedProposals.snapshot;
          allProposals.aip = mergedProposals.aip;
          allProposals.forum = mergedProposals.forum;
        }
        
        // Reset running flag after all retries are complete
        if (retryCount === retryDelays.length) {
          widgetSetupCompleted = true;
          // Hide loader when all retries are done
          hideMainWidgetLoader();
          // Reset running flag after a short delay to allow DOM updates to complete
          setTimeout(() => {
            isWidgetSetupRunning = false;
            // Final hide of loader
            hideMainWidgetLoader();
          }, 100);
        }
      }, delay);
    });
    
    return Promise.resolve();
  }
  
  // Normalize AIP URLs to extract proposalId for comparison (ignore query parameters like ipfsHash)
  function normalizeAIPUrl(url) {
    if (!url || !url.includes('vote.onaave.com') && !url.includes('app.aave.com') && !url.includes('governance.aave.com')) {
      return url; // Not an AIP URL, return as-is
    }
    
    // Explicitly exclude forum topic URLs (governance.aave.com/t/) - these are NOT AIP proposal URLs
    if (url.includes('governance.aave.com/t/')) {
      console.log(`⚠️ [NORMALIZE] Skipping forum topic URL (not an AIP proposal): ${url}`);
      return url; // Return as-is, but it should not be processed as an AIP URL
    }
    
    const proposalInfo = extractAIPProposalInfo(url);
    if (proposalInfo && proposalInfo.proposalId) {
      // Return normalized URL based on proposalId
      if (url.includes('vote.onaave.com')) {
        return `https://vote.onaave.com/proposal/?proposalId=${proposalInfo.proposalId}`;
      } else if (url.includes('app.aave.com')) {
        return `https://app.aave.com/governance/v3/proposal/?proposalId=${proposalInfo.proposalId}`;
      }
    }
    return url; // Fallback to original URL if extraction fails
  }

  // ===== FORUM TOPIC VALIDATION =====
  // These functions ensure proposals are only shown if they're related to the current forum topic
  
  /**
   * Normalize a forum URL for comparison
   * Returns a normalized URL with protocol, host, and path up to topic ID (removes query params, fragments, trailing slashes)
   * Example: https://governance.aave.com/t/slug/123/456?param=1#frag -> https://governance.aave.com/t/slug/123
   */
  function normalizeForumUrl(forumUrl) {
    if (!forumUrl) {return null;}
    try {
      // Decode HTML entities
      let url = forumUrl.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"');
      
      // Extract the base URL and path up to topic ID
      // Pattern: protocol://host/t/slug/topicId (with optional trailing path, query, fragment)
      const urlMatch = url.match(/^(https?:\/\/[^\/]+)\/t\/([^\/]+)\/(\d+)/i);
      if (urlMatch) {
        const protocol = urlMatch[1].toLowerCase().startsWith('https') ? 'https' : 'http';
        const host = urlMatch[1].replace(/^https?:\/\//i, '').toLowerCase();
        // Remove www. prefix for normalization
        const normalizedHost = host.replace(/^www\./, '');
        const slug = urlMatch[2];
        const topicId = urlMatch[3];
        
        // Construct normalized URL: protocol://host/t/slug/topicId
        const normalized = `${protocol}://${normalizedHost}/t/${slug}/${topicId}`;
        return normalized;
      }
      
      return null;
    } catch (error) {
      console.warn(`⚠️ [NORMALIZE] Error normalizing forum URL: ${forumUrl}`, error);
      return null;
    }
  }
  
  /**
   * Get the current forum topic URL if we're on a forum page
   * Returns the normalized forum topic URL or null
   * Works on any Discourse forum, not just governance.aave.com
   */
  function getCurrentForumTopicUrl() {
    try {
      const currentUrl = window.location.href;
      const pathname = window.location.pathname;
      
      // Check if we're on a Discourse topic page (pattern: /t/{slug}/{id})
      // This works on any Discourse forum, not just governance.aave.com
      const topicMatch = pathname.match(/^\/t\/([^\/]+)\/(\d+)/);
      if (topicMatch) {
        // Extract the base URL (protocol + host)
        const baseUrl = `${window.location.protocol}//${window.location.host}`;
        const slug = topicMatch[1];
        const topicId = topicMatch[2];
        
        // Construct forum topic URL and normalize it
        const forumUrl = `${baseUrl}/t/${slug}/${topicId}`;
        const normalized = normalizeForumUrl(forumUrl);
        if (normalized) {
          console.log(`🔵 [VALIDATE] Current forum topic URL: ${normalized}`);
          return normalized;
        }
        // Fallback to non-normalized if normalization fails
        console.log(`🔵 [VALIDATE] Current forum topic URL (fallback): ${forumUrl}`);
        return forumUrl;
      }
      
      // Fallback: Check for governance.aave.com specifically (for backward compatibility)
      const forumMatch = currentUrl.match(/https?:\/\/(?:www\.)?governance\.aave\.com\/t\/[^\s<>"']+/i);
      if (forumMatch) {
        const forumUrl = forumMatch[0];
        // Normalize URL using normalizeForumUrl
        const normalized = normalizeForumUrl(forumUrl);
        if (normalized) {
          console.log(`🔵 [VALIDATE] Current forum topic URL (legacy, normalized): ${normalized}`);
          return normalized;
        }
        // Fallback to simple normalization if normalizeForumUrl fails
        const simpleNormalized = forumUrl.replace(/[\/#\?].*$/, '').replace(/\/$/, '');
        console.log(`🔵 [VALIDATE] Current forum topic URL (legacy, simple): ${simpleNormalized}`);
        return simpleNormalized;
      }
    } catch (error) {
      console.warn(`⚠️ [VALIDATE] Error getting current forum URL:`, error);
    }
    return null;
  }
  
  /**
   * Extract forum topic ID from a forum URL
   * Returns the topic ID (numeric) or null
   * Works with any Discourse forum URL pattern: /t/{slug}/{id}
   */
  function extractForumTopicId(forumUrl) {
    if (!forumUrl) {return null;}
    try {
      // Try Discourse pattern first: /t/{slug}/{id} (works on any Discourse forum)
      const discourseMatch = forumUrl.match(/\/t\/[^\/]+\/(\d+)/);
      if (discourseMatch) {
        return discourseMatch[1];
      }
      
      // Fallback: Check for governance.aave.com specifically (for backward compatibility)
      const legacyMatch = forumUrl.match(/governance\.aave\.com\/t\/[^\/]+\/(\d+)/i);
      if (legacyMatch) {
        return legacyMatch[1];
      }
      
      return null;
    // eslint-disable-next-line no-unused-vars
    } catch (_error) {
      return null;
    }
  }
  
  /**
   * Get the current forum topic title from the page
   * Returns the topic title as a string, or null if not found
   */
  // eslint-disable-next-line no-unused-vars
  function getCurrentForumTopicTitle() {
    try {
      // Try various Discourse selectors for topic title
      const selectors = [
        'h1.fancy-title',
        '.fancy-title',
        'h1.topic-title',
        '.topic-title',
        'h1',
        '[data-topic-id] h1',
        '.topic-meta-data h1',
        'article[data-topic-id] h1'
      ];
      
      for (const selector of selectors) {
        const element = document.querySelector(selector);
        if (element) {
          const title = element.textContent?.trim() || element.innerText?.trim();
          if (title && title.length > 0) {
            console.log(`🔵 [VALIDATE] Found topic title: "${title}"`);
            return title;
          }
        }
      }
      
      console.log(`⚠️ [VALIDATE] Could not find topic title on page`);
      return null;
    } catch (error) {
      console.warn(`⚠️ [VALIDATE] Error getting topic title:`, error);
      return null;
    }
  }
  
  /**
   * Normalize a topic name for comparison (lowercase, trim whitespace)
   * Returns normalized string
   */
  function normalizeTopicName(name) {
    if (!name || typeof name !== 'string') {return '';}
    return name.toLowerCase().trim();
  }
  
  /**
   * Compare two topic names (case-insensitive)
   * Returns true if names match after normalization
   */
  // eslint-disable-next-line no-unused-vars
  function compareTopicNames(name1, name2) {
    const normalized1 = normalizeTopicName(name1);
    const normalized2 = normalizeTopicName(name2);
    return normalized1 === normalized2 && normalized1.length > 0;
  }
  
  /**
   * Extract topic slug from a forum URL
   * Returns the slug (e.g., "temp-check-focussing-the-aave-v3-multichain-strategy") or null
   * Works with any Discourse forum URL pattern: /t/{slug}/{id}
   */
  function extractTopicSlugFromForumUrl(forumUrl) {
    if (!forumUrl) {return null;}
    try {
      // Try Discourse pattern: /t/{slug}/{id}
      const discourseMatch = forumUrl.match(/\/t\/([^\/]+)\/\d+/);
      if (discourseMatch) {
        return discourseMatch[1];
      }
      
      // Fallback: Check for governance.aave.com specifically
      const legacyMatch = forumUrl.match(/governance\.aave\.com\/t\/([^\/]+)\/\d+/i);
      if (legacyMatch) {
        return legacyMatch[1];
      }
      
      return null;
    // eslint-disable-next-line no-unused-vars
    } catch (_error) {
      return null;
    }
  }
  
  /**
   * Convert a topic title to a slug format (like Discourse does)
   * Converts to lowercase, replaces spaces and special chars with hyphens
   * Returns normalized slug string
   */
  function topicTitleToSlug(title) {
    if (!title || typeof title !== 'string') {return '';}
    return title
      .toLowerCase()
      .trim()
      .replace(/[^\w\s-]/g, '') // Remove special characters
      .replace(/\s+/g, '-')      // Replace spaces with hyphens
      .replace(/-+/g, '-')       // Replace multiple hyphens with single hyphen
      .replace(/^-|-$/g, '');    // Remove leading/trailing hyphens
  }
  
  /**
   * Compare a forum URL's topic slug with a topic title
   * Returns true if the slug from the URL matches the slug derived from the title
   * Also handles cases where the URL slug has prefixes like "temp-check-" that may not be in the title
   */
  // eslint-disable-next-line no-unused-vars
  function compareTopicSlugWithTitle(forumUrl, topicTitle) {
    const slugFromUrl = extractTopicSlugFromForumUrl(forumUrl);
    if (!slugFromUrl) {return false;}
    
    const slugFromTitle = topicTitleToSlug(topicTitle);
    if (!slugFromTitle) {return false;}
    
    // Direct slug comparison (already normalized)
    if (slugFromUrl === slugFromTitle) {
      return true;
    }
    
    // Check if the title slug is contained in the URL slug (handles prefixes like "temp-check-")
    // For example: "temp-check-focussing-the-aave-v3-multichain-strategy" contains "focussing-the-aave-v3-multichain-strategy"
    if (slugFromUrl.includes(slugFromTitle) && slugFromTitle.length > 10) {
      return true;
    }
    
    // Also check if URL slug is contained in title slug (handles cases where URL slug is shorter)
    if (slugFromTitle.includes(slugFromUrl) && slugFromUrl.length > 10) {
      return true;
    }
    
    return false;
  }
  
  /**
   * Extract discussion/reference links from a Snapshot proposal
   * Returns an array of URLs found in discussion fields (can be any URL, not just forum links)
   */
  function extractDiscussionLinksFromSnapshot(snapshotProposal) {
    const proposalTitle = snapshotProposal?.data?.title || 'Unknown';
    console.log(`🔍 [DISCUSSION] Extracting discussion links from: "${proposalTitle}"`);
    
    if (!snapshotProposal || !snapshotProposal.data) {
      console.log('   ❌ [DISCUSSION] No proposal data found');
      return [];
    }
    
    const discussionLinks = [];
    
    // Check 1: proposal.discussion field (direct discussion link)
    // Extract any Discourse forum URLs (works for any Discourse instance, not just governance.aave.com)
    const discussion = snapshotProposal.data.discussion;
    console.log(`   📋 [DISCUSSION] snapshotProposal.data.discussion =`, discussion);
    if (discussion) {
      // Try specific Aave forum regex first (for backward compatibility)
      AAVE_FORUM_URL_REGEX.lastIndex = 0; // Reset regex
      let forumMatch = discussion.match(AAVE_FORUM_URL_REGEX);
      if (forumMatch) {
        console.log(`   ✅ [DISCUSSION] Found Aave forum links in discussion field:`, forumMatch);
        discussionLinks.push(...forumMatch);
      } else {
        // Try general Discourse forum regex (matches any Discourse instance)
        DISCOURSE_FORUM_URL_REGEX.lastIndex = 0; // Reset regex
        forumMatch = discussion.match(DISCOURSE_FORUM_URL_REGEX);
        if (forumMatch) {
          console.log(`   ✅ [DISCUSSION] Found Discourse forum links in discussion field:`, forumMatch);
          discussionLinks.push(...forumMatch);
        } else {
          console.log(`   ❌ [DISCUSSION] No forum URLs found in discussion field (value: "${discussion}")`);
        }
      }
    } else {
      console.log(`   ⚠️ [DISCUSSION] discussion field is null/undefined`);
    }
    
    // Check 2: proposal.plugins field (Discourse plugin)
    const plugins = snapshotProposal.data.plugins;
    console.log(`   📋 [DISCUSSION] snapshotProposal.data.plugins =`, plugins);
    if (plugins) {
      try {
        const pluginsStr = typeof plugins === 'string' ? plugins : JSON.stringify(plugins);
        // Try specific Aave forum regex first, then general Discourse regex
        AAVE_FORUM_URL_REGEX.lastIndex = 0;
        let forumMatch = pluginsStr.match(AAVE_FORUM_URL_REGEX);
        if (forumMatch) {
          console.log(`   ✅ [DISCUSSION] Found Aave forum links in plugins:`, forumMatch);
          discussionLinks.push(...forumMatch);
        } else {
          DISCOURSE_FORUM_URL_REGEX.lastIndex = 0;
          forumMatch = pluginsStr.match(DISCOURSE_FORUM_URL_REGEX);
          if (forumMatch) {
            console.log(`   ✅ [DISCUSSION] Found Discourse forum links in plugins:`, forumMatch);
            discussionLinks.push(...forumMatch);
          } else {
            console.log(`   ❌ [DISCUSSION] No forum links found in plugins`);
          }
        }
      } catch (e) {
        console.log(`   ❌ [DISCUSSION] Error parsing plugins:`, e.message);
      }
    } else {
      console.log(`   ⚠️ [DISCUSSION] plugins field is null/undefined`);
    }
    
    // Check 3: proposal._rawProposal.discussion or plugins
    const rawProposal = snapshotProposal.data._rawProposal;
    console.log(`   📋 [DISCUSSION] snapshotProposal.data._rawProposal exists:`, !!rawProposal);
    if (rawProposal) {
      if (rawProposal.discussion) {
        console.log(`   📋 [DISCUSSION] _rawProposal.discussion =`, rawProposal.discussion);
        // Try specific Aave forum regex first, then general Discourse regex
        AAVE_FORUM_URL_REGEX.lastIndex = 0;
        let forumMatch = rawProposal.discussion.match(AAVE_FORUM_URL_REGEX);
        if (forumMatch) {
          console.log(`   ✅ [DISCUSSION] Found Aave forum links in _rawProposal.discussion:`, forumMatch);
          discussionLinks.push(...forumMatch);
        } else {
          DISCOURSE_FORUM_URL_REGEX.lastIndex = 0;
          forumMatch = rawProposal.discussion.match(DISCOURSE_FORUM_URL_REGEX);
          if (forumMatch) {
            console.log(`   ✅ [DISCUSSION] Found Discourse forum links in _rawProposal.discussion:`, forumMatch);
            discussionLinks.push(...forumMatch);
          } else {
            console.log(`   ❌ [DISCUSSION] No forum URLs found in _rawProposal.discussion`);
          }
        }
      } else {
        console.log(`   ⚠️ [DISCUSSION] _rawProposal.discussion is null/undefined`);
      }
      
      if (rawProposal.plugins) {
        try {
          const pluginsStr = typeof rawProposal.plugins === 'string' 
            ? rawProposal.plugins 
            : JSON.stringify(rawProposal.plugins);
          // Try specific Aave forum regex first, then general Discourse regex
          AAVE_FORUM_URL_REGEX.lastIndex = 0;
          let forumMatch = pluginsStr.match(AAVE_FORUM_URL_REGEX);
          if (forumMatch) {
            console.log(`   ✅ [DISCUSSION] Found Aave forum links in _rawProposal.plugins:`, forumMatch);
            discussionLinks.push(...forumMatch);
          } else {
            DISCOURSE_FORUM_URL_REGEX.lastIndex = 0;
            forumMatch = pluginsStr.match(DISCOURSE_FORUM_URL_REGEX);
            if (forumMatch) {
              console.log(`   ✅ [DISCUSSION] Found Discourse forum links in _rawProposal.plugins:`, forumMatch);
              discussionLinks.push(...forumMatch);
            } else {
              console.log(`   ❌ [DISCUSSION] No forum links found in _rawProposal.plugins`);
            }
          }
        } catch (e) {
          console.log(`   ❌ [DISCUSSION] Error parsing _rawProposal.plugins:`, e.message);
        }
      } else {
        console.log(`   ⚠️ [DISCUSSION] _rawProposal.plugins is null/undefined`);
      }
    }
    
    // Check 4: proposal body/description (as fallback - some proposals embed forum links in the text)
    if (discussionLinks.length === 0) {
      const body = snapshotProposal.data.body || snapshotProposal.data.description || '';
      const title = snapshotProposal.data.title || '';
      const combinedText = `${title} ${body}`;
      
      if (combinedText.length > 0) {
        console.log(`   📋 [DISCUSSION] Checking proposal body/description for forum links (${combinedText.length} chars)`);
        // Try specific Aave forum regex first, then general Discourse regex
        AAVE_FORUM_URL_REGEX.lastIndex = 0;
        let forumMatches = combinedText.match(AAVE_FORUM_URL_REGEX);
        if (forumMatches && forumMatches.length > 0) {
          console.log(`   ✅ [DISCUSSION] Found Aave forum links in proposal body/description:`, forumMatches);
          discussionLinks.push(...forumMatches);
        } else {
          DISCOURSE_FORUM_URL_REGEX.lastIndex = 0;
          forumMatches = combinedText.match(DISCOURSE_FORUM_URL_REGEX);
          if (forumMatches && forumMatches.length > 0) {
            console.log(`   ✅ [DISCUSSION] Found Discourse forum links in proposal body/description:`, forumMatches);
            discussionLinks.push(...forumMatches);
          } else {
            console.log(`   ❌ [DISCUSSION] No forum URLs found in proposal body/description`);
          }
        }
      }
    }
    
    // Normalize and deduplicate links
    // Remove query parameters and fragments, but keep the full path
    const normalizedLinks = discussionLinks
      .map(link => {
        // Remove query parameters (?) and fragments (#) but keep the path
        let normalized = link.split('?')[0].split('#')[0];
        // Remove trailing slash
        normalized = normalized.replace(/\/$/, '');
        return normalized;
      })
      .filter((link, index, self) => self.indexOf(link) === index);
    
    console.log(`   📊 [DISCUSSION] Final extracted discussion links:`, normalizedLinks.length > 0 ? normalizedLinks : 'NONE');
    return normalizedLinks;
  }
  
  /**
   * Fetch metadata from IPFS
   * Similar to recombee.mjs approach
   */
  async function fetchFromIPFS(ipfsHash) {
    if (!ipfsHash || ipfsHash === '0x0' || ipfsHash.startsWith('0x0000')) {
      return null;
    }
    
    try {
      // Convert hex IPFS hash to base58 if needed, or try direct IPFS gateway
      // IPFS hashes are usually base58, but this might be hex-encoded
      
      // If it's a hex string starting with 0x, try to decode it
      if (ipfsHash.startsWith('0x')) {
        // Try multiple IPFS gateways
        const gateways = [
          `https://ipfs.io/ipfs/${ipfsHash.slice(2)}`,
          `https://gateway.pinata.cloud/ipfs/${ipfsHash.slice(2)}`,
          `https://cloudflare-ipfs.com/ipfs/${ipfsHash.slice(2)}`,
        ];
        
        for (const gateway of gateways) {
          try {
            console.log(`   🔍 [DISCUSSION] Trying IPFS gateway: ${gateway}`);
            const response = await fetch(gateway, { 
              method: 'GET',
              headers: { 'Accept': 'application/json' },
              signal: AbortSignal.timeout(2000) // 2 second timeout (reduced for faster rendering)
            });
            
            if (response.ok) {
              const data = await response.json();
              console.log(`   ✅ [DISCUSSION] Found IPFS metadata!`);
              return data;
            }
          // eslint-disable-next-line no-unused-vars
          } catch (_err) {
            // Try next gateway
            continue;
          }
        }
      }
      
      return null;
    } catch (err) {
      console.warn(`   ⚠️  [DISCUSSION] IPFS fetch error: ${err.message}`);
      return null;
    }
  }

  /**
   * Extract discussion/reference links from an AIP proposal
   * Uses the same comprehensive approach as recombee.mjs
   * Returns an array of forum URLs found in discussion/reference fields
   */
  async function extractDiscussionLinksFromAIP(aipProposal) {
    const proposalTitle = aipProposal?.data?.title || 'Unknown';
    console.log(`🔍 [DISCUSSION] Extracting discussion links from AIP: "${proposalTitle}"`);
    
    if (!aipProposal || !aipProposal.data) {
      console.log('   ❌ [DISCUSSION] No proposal data found');
      return [];
    }
    
    // Debug: Log available fields in proposal data
    console.log(`   📋 [DISCUSSION] Available fields in proposal data:`, Object.keys(aipProposal.data));
    console.log(`   📋 [DISCUSSION] ipfsHash:`, aipProposal.data.ipfsHash);
    console.log(`   📋 [DISCUSSION] rawContent:`, aipProposal.data.rawContent ? `${aipProposal.data.rawContent.substring(0, 100)}...` : 'null/undefined');
    
    const discussionLinks = [];
    
    // Check 1: proposalMetadata.rawContent FIRST (usually available immediately, no network delay)
    // Try both top-level rawContent and nested locations
    let rawContent = aipProposal.data.rawContent || aipProposal.data.proposalMetadata?.rawContent;
    
    if (rawContent) {
      console.log(`   📋 [DISCUSSION] Checking proposalMetadata.rawContent for discussion URLs (fast path - no network delay)...`);
      console.log(`   📋 [DISCUSSION] rawContent type: ${typeof rawContent}, length: ${typeof rawContent === 'string' ? rawContent.length : 'N/A'}`);
      
      if (typeof rawContent === 'string') {
        // Try specific Aave forum regex first, then general Discourse regex
        AAVE_FORUM_URL_REGEX.lastIndex = 0;
        let matches = rawContent.match(AAVE_FORUM_URL_REGEX);
        if (matches && matches.length > 0) {
          console.log(`   ✅ [DISCUSSION] Found Aave forum URLs in rawContent:`, matches);
          discussionLinks.push(...matches);
        } else {
          DISCOURSE_FORUM_URL_REGEX.lastIndex = 0;
          matches = rawContent.match(DISCOURSE_FORUM_URL_REGEX);
          if (matches && matches.length > 0) {
            console.log(`   ✅ [DISCUSSION] Found Discourse forum URLs in rawContent:`, matches);
            discussionLinks.push(...matches);
          } else {
            console.log(`   ❌ [DISCUSSION] No forum URLs found in rawContent string`);
          }
        }
      }
      
      // Check if rawContent is JSON and parse it
      try {
        const parsed = JSON.parse(rawContent);
        if (parsed && typeof parsed === 'object') {
          // Check common fields in parsed JSON
          const parsedFields = [
            parsed.discussion,
            parsed.discussionUrl,
            parsed.discussion_url,
            parsed.link,
            parsed.reference,
            parsed.body,
            parsed.description
          ];
          
          for (const fieldValue of parsedFields) {
            if (fieldValue && typeof fieldValue === 'string') {
              // Try specific Aave forum regex first, then general Discourse regex
              AAVE_FORUM_URL_REGEX.lastIndex = 0;
              let matches = fieldValue.match(AAVE_FORUM_URL_REGEX);
              if (matches && matches.length > 0) {
                console.log(`   ✅ [DISCUSSION] Found Aave forum URLs in parsed rawContent:`, matches);
                discussionLinks.push(...matches);
              } else {
                DISCOURSE_FORUM_URL_REGEX.lastIndex = 0;
                matches = fieldValue.match(DISCOURSE_FORUM_URL_REGEX);
                if (matches && matches.length > 0) {
                  console.log(`   ✅ [DISCUSSION] Found Discourse forum URLs in parsed rawContent:`, matches);
                  discussionLinks.push(...matches);
                }
              }
            }
          }
        }
      // eslint-disable-next-line no-unused-vars
      } catch (_e) {
        // rawContent is not JSON, ignore
      }
    } else {
      console.log(`   ⚠️  [DISCUSSION] No rawContent found in proposal data (checked both data.rawContent and data.proposalMetadata.rawContent)`);
    }
    
    // If we already found discussion links in rawContent, skip IPFS (faster rendering)
    if (discussionLinks.length > 0) {
      console.log(`   ⚡ [DISCUSSION] Discussion links found in rawContent - skipping IPFS fetch for faster rendering`);
    } else {
      // Check 2: IPFS metadata (only if rawContent didn't have links - non-blocking for faster rendering)
      // Try both top-level ipfsHash and nested locations
      const ipfsHash = aipProposal.data.ipfsHash || aipProposal.data.proposalMetadata?.ipfsHash;
      let ipfsData = null;
      if (ipfsHash) {
        console.log(`   📋 [DISCUSSION] No links in rawContent - attempting to fetch metadata from IPFS (hash: ${ipfsHash})...`);
        // Use Promise.race to timeout faster if IPFS is slow
        try {
          ipfsData = await Promise.race([
            fetchFromIPFS(ipfsHash),
            new Promise((_, reject) => setTimeout(() => reject(new Error('IPFS timeout')), 3000)) // 3 second max wait
          ]);
        } catch (err) {
          console.log(`   ⚠️  [DISCUSSION] IPFS fetch timed out or failed (continuing without it): ${err.message}`);
          ipfsData = null;
        }
        if (!ipfsData) {
          console.log(`   ⚠️  [DISCUSSION] IPFS fetch returned null (gateway might be down or hash invalid)`);
        }
      } else {
        console.log(`   ⚠️  [DISCUSSION] No ipfsHash found in proposal data (checked both data.ipfsHash and data.proposalMetadata.ipfsHash)`);
      }
      
      if (ipfsData) {
        console.log(`   📋 [DISCUSSION] Checking IPFS metadata for discussion URLs...`);
        
        // Check common fields in IPFS metadata
        const fieldsToCheck = [
          ipfsData.discussion,
          ipfsData.discussionUrl,
          ipfsData.discussion_url,
          ipfsData.forumLink,
          ipfsData.forum_link,
          ipfsData.link,
          ipfsData.reference,
          ipfsData.referenceUrl
        ];
        
        // Also check if the entire metadata is a string
        if (typeof ipfsData === 'string') {
          fieldsToCheck.push(ipfsData);
        } else {
          // Check entire JSON string representation
          try {
            fieldsToCheck.push(JSON.stringify(ipfsData));
          // eslint-disable-next-line no-unused-vars
          } catch (_e) {
            // Ignore JSON stringify errors
          }
        }
        
        for (const fieldValue of fieldsToCheck) {
          if (fieldValue && typeof fieldValue === 'string') {
            // Try specific Aave forum regex first, then general Discourse regex
            AAVE_FORUM_URL_REGEX.lastIndex = 0;
            let matches = fieldValue.match(AAVE_FORUM_URL_REGEX);
            if (matches && matches.length > 0) {
              console.log(`   ✅ [DISCUSSION] Found Aave forum URLs in IPFS metadata:`, matches);
              discussionLinks.push(...matches);
            } else {
              DISCOURSE_FORUM_URL_REGEX.lastIndex = 0;
              matches = fieldValue.match(DISCOURSE_FORUM_URL_REGEX);
              if (matches && matches.length > 0) {
                console.log(`   ✅ [DISCUSSION] Found Discourse forum URLs in IPFS metadata:`, matches);
                discussionLinks.push(...matches);
              }
            }
          }
        }
      }
    }
    
    // Check 4: description/body for forum links (fallback)
    const description = aipProposal.data.description || '';
    const body = aipProposal.data.body || '';
    if (description || body) {
      console.log(`   📋 [DISCUSSION] description length: ${description.length}, body length: ${body.length}`);
      const combinedText = `${description} ${body}`;
      
      if (combinedText.length > 0) {
        // Try specific Aave forum regex first, then general Discourse regex
        AAVE_FORUM_URL_REGEX.lastIndex = 0;
        let forumMatches = combinedText.match(AAVE_FORUM_URL_REGEX);
        if (forumMatches && forumMatches.length > 0) {
          console.log(`   ✅ [DISCUSSION] Found Aave forum links in description/body:`, forumMatches);
          discussionLinks.push(...forumMatches);
        } else {
          DISCOURSE_FORUM_URL_REGEX.lastIndex = 0;
          forumMatches = combinedText.match(DISCOURSE_FORUM_URL_REGEX);
          if (forumMatches && forumMatches.length > 0) {
            console.log(`   ✅ [DISCUSSION] Found Discourse forum links in description/body:`, forumMatches);
            discussionLinks.push(...forumMatches);
          }
        }
      }
    }
    
    // Check 5: metadata field (if available, as fallback)
    const metadata = aipProposal.data.metadata;
    if (metadata) {
      console.log(`   📋 [DISCUSSION] metadata exists:`, !!metadata);
      try {
        const metadataStr = typeof metadata === 'string' ? metadata : JSON.stringify(metadata);
        // Try specific Aave forum regex first, then general Discourse regex
        AAVE_FORUM_URL_REGEX.lastIndex = 0;
        let forumMatch = metadataStr.match(AAVE_FORUM_URL_REGEX);
        if (forumMatch) {
          console.log(`   ✅ [DISCUSSION] Found Aave forum links in metadata:`, forumMatch);
          discussionLinks.push(...forumMatch);
        } else {
          DISCOURSE_FORUM_URL_REGEX.lastIndex = 0;
          forumMatch = metadataStr.match(DISCOURSE_FORUM_URL_REGEX);
          if (forumMatch) {
            console.log(`   ✅ [DISCUSSION] Found Discourse forum links in metadata:`, forumMatch);
            discussionLinks.push(...forumMatch);
          }
        }
      } catch (e) {
        console.log(`   ❌ [DISCUSSION] Error parsing metadata:`, e.message);
      }
    }
    
    // Normalize and deduplicate links
    // Remove query parameters and fragments, but keep the full path
    const normalizedLinks = discussionLinks
      .map(link => {
        // Remove query parameters (?) and fragments (#) but keep the path
        let normalized = link.split('?')[0].split('#')[0];
        // Remove trailing slash
        normalized = normalized.replace(/\/$/, '');
        // Remove trailing punctuation that might have been captured with the URL
        // (parentheses, commas, periods, etc. that are part of surrounding text)
        normalized = normalized.replace(/[.,;:)!?]+$/, '');
        return normalized;
      })
      .filter((link, index, self) => self.indexOf(link) === index);
    
    if (normalizedLinks.length > 0) {
      console.log(`   ✅ [DISCUSSION] Final extracted discussion URLs:`, normalizedLinks);
    } else {
      console.log(`   ❌ [DISCUSSION] No discussion URLs found in IPFS metadata or rawContent`);
    }
    
    return normalizedLinks;
  }
  
  /**
   * Validate if a Snapshot proposal is related to the current forum topic
   * Returns an object with { isRelated: boolean, discussionLink: string|null }
   * 
   * A proposal is considered related if:
   * 1. The proposal's discussion/reference link matches the current forum topic URL (full URL match)
   * 2. OR we're not on a forum page (show all proposals)
   * 
   * Forum thread URLs are unique and stable, whereas titles can vary slightly.
   * The URL is treated as the sole authoritative link for matching.
   */
  function validateSnapshotProposalForForum(snapshotProposal, currentForumUrl) {
    console.log(`🔍 [VALIDATE] Validating Snapshot proposal: ${snapshotProposal?.data?.title || 'Unknown'}`);
    
    if (!currentForumUrl) {
      // If we're not on a forum page, allow all proposals
      console.log(`   ⚠️ Not on forum page - allowing proposal`);
      return { isRelated: true, discussionLink: null };
    }
    
    if (!snapshotProposal || !snapshotProposal.data) {
      console.log(`   ❌ No proposal data`);

      return { isRelated: false, discussionLink: null };
    }
    
    // Normalize current forum URL for comparison
    const normalizedCurrentUrl = normalizeForumUrl(currentForumUrl);
    if (!normalizedCurrentUrl) {
      // Can't normalize current URL - cannot match
      console.log(`⚠️ [VALIDATE] Could not normalize current forum URL: ${currentForumUrl} - cannot match without URL`);
      const discussionLinks = extractDiscussionLinksFromSnapshot(snapshotProposal);
      return { isRelated: false, discussionLink: discussionLinks.length > 0 ? discussionLinks[0] : null };
    }
    
    console.log(`   Current normalized forum URL: ${normalizedCurrentUrl}`);
    
    // Check: Discussion/reference links (full URL matching)
    const discussionLinks = extractDiscussionLinksFromSnapshot(snapshotProposal);
    for (const link of discussionLinks) {
      const normalizedLink = normalizeForumUrl(link);
      console.log(`   🔍 [VALIDATE] Comparing discussion link: ${link}`);
      console.log(`   🔍 [VALIDATE] Normalized discussion link: ${normalizedLink}`);
      console.log(`   🔍 [VALIDATE] Normalized current URL: ${normalizedCurrentUrl}`);
      console.log(`   🔍 [VALIDATE] Match: ${normalizedLink === normalizedCurrentUrl ? 'YES ✅' : 'NO ❌'}`);
      if (normalizedLink && normalizedLink === normalizedCurrentUrl) {
        console.log(`✅ [VALIDATE] Snapshot proposal is related to forum topic (found matching discussion link: ${link})`);
        return { isRelated: true, discussionLink: link };
      }
    }
    
    // If no match found, it's not related to this topic
    // But still return the discussion link so it can be displayed
    console.log(`⚠️ [VALIDATE] Snapshot proposal is NOT related to current forum topic - will show with discussion link`);
    if (discussionLinks.length > 0) {
      console.log(`   Found discussion links: ${discussionLinks.join(', ')}`);
      return { isRelated: false, discussionLink: discussionLinks[0] };
    } else {
      console.log(`   No discussion links found in proposal`);
      return { isRelated: false, discussionLink: null };
    }
  }
  
  /**
   * Validate if an AIP proposal is related to the current forum topic
   * Returns true if the proposal is related, false otherwise
   * 
   * A proposal is considered related if:
   * 1. The proposal's discussion/reference link matches the current forum topic URL (full URL match)
   * 2. OR the AIP proposal ID matches the forum topic ID (they're directly linked by ID)
   * 3. OR we're not on a forum page (show all proposals)
   * 
   * Forum thread URLs are unique and stable, whereas titles can vary slightly.
   * The URL is treated as the sole authoritative link for matching.
   */
  async function validateAIPProposalForForum(aipProposal, currentForumUrl) {
    if (!currentForumUrl) {
      // If we're not on a forum page, allow all proposals
      return { isRelated: true, discussionLink: null };
    }
    
    if (!aipProposal || !aipProposal.data) {
      return { isRelated: false, discussionLink: null };
    }
    
    // Normalize current forum URL for comparison
    const normalizedCurrentUrl = normalizeForumUrl(currentForumUrl);
    if (!normalizedCurrentUrl) {
      // Can't normalize current URL - try ID matching as fallback
      const currentTopicId = extractForumTopicId(currentForumUrl);
      if (currentTopicId) {
        // Check if AIP proposal ID matches forum topic ID (they're directly linked by ID)
        const aipId = String(aipProposal.data.id || '');
        if (aipId === currentTopicId) {
          console.log(`✅ [VALIDATE] AIP proposal ID ${aipId} matches forum topic ID - directly related`);
          const discussionLinks = await extractDiscussionLinksFromAIP(aipProposal);
          return { isRelated: true, discussionLink: discussionLinks.length > 0 ? discussionLinks[0] : null };
        }
      }
      // Can't match without normalized URL or matching ID
      console.log(`⚠️ [VALIDATE] Could not normalize current forum URL: ${currentForumUrl} - cannot match without URL`);
      const discussionLinks = await extractDiscussionLinksFromAIP(aipProposal);
      return { isRelated: false, discussionLink: discussionLinks.length > 0 ? discussionLinks[0] : null };
    }
    
    console.log(`   Current normalized forum URL: ${normalizedCurrentUrl}`);
    
    // Check 1: Discussion/reference links (full URL matching)
    const discussionLinks = await extractDiscussionLinksFromAIP(aipProposal);
    for (const link of discussionLinks) {
      const normalizedLink = normalizeForumUrl(link);
      if (normalizedLink && normalizedLink === normalizedCurrentUrl) {
        console.log(`✅ [VALIDATE] AIP proposal is related to forum topic (found matching discussion link: ${link})`);
        return { isRelated: true, discussionLink: link };
      }
    }
    
    // Check 2: AIP proposal ID matches forum topic ID (they're directly linked by ID)
    // This is a special case where AIPs and forum topics share the same ID
    const currentTopicId = extractForumTopicId(currentForumUrl);
    if (currentTopicId) {
      const aipId = String(aipProposal.data.id || '');
      if (aipId === currentTopicId) {
        console.log(`✅ [VALIDATE] AIP proposal ID ${aipId} matches forum topic ID - directly related`);
        return { isRelated: true, discussionLink: discussionLinks.length > 0 ? discussionLinks[0] : null };
      }
    }
    
    // If no match found, it's not related to this topic
    // But still return the discussion link so it can be displayed
    console.log(`⚠️ [VALIDATE] AIP proposal is NOT related to current forum topic - will show with discussion link`);
    if (discussionLinks.length > 0) {
      console.log(`   Found discussion links: ${discussionLinks.join(', ')}`);
      return { isRelated: false, discussionLink: discussionLinks[0] };
    } else {
      console.log(`   No discussion links found in proposal`);
      return { isRelated: false, discussionLink: null };
    }
  }

  // ===== PROPOSAL CATEGORIZATION AND SELECTION HELPERS =====
  // These functions handle edge cases where multiple proposals of the same type exist
  
  /**
   * Categorize all Snapshot proposals by type (Temp Check, ARFC, or generic Snapshot)
   * Returns: { tempChecks: [], arfcs: [], snapshots: [] }
   */
  function categorizeSnapshotProposals(snapshotProposals) {
    const categorized = {
      tempChecks: [],
      arfcs: [],
      snapshots: [] // Generic snapshot proposals that aren't Temp Check or ARFC
    };
    
    snapshotProposals.forEach(proposal => {
      if (!proposal || !proposal.data) {return;}
      
      const stage = proposal.data.stage || 'snapshot';
      
      // Extract timestamp from raw proposal data (endTime is available, or use _rawProposal.start/end)
      let timestamp = 0;
      if (proposal.data.endTime) {
        timestamp = proposal.data.endTime; // Use endTime as proxy for recency
      } else if (proposal.data._rawProposal) {
        timestamp = proposal.data._rawProposal.start || proposal.data._rawProposal.end || 0;
      }
      
      if (stage === 'temp-check') {
        categorized.tempChecks.push({
          ...proposal,
          stage: 'temp-check',
          timestamp
        });
      } else if (stage === 'arfc') {
        categorized.arfcs.push({
          ...proposal,
          stage: 'arfc',
          timestamp
        });
      } else {
        categorized.snapshots.push({
          ...proposal,
          stage: 'snapshot',
          timestamp
        });
      }
    });
    
    console.log(`🔵 [CATEGORIZE] Snapshot proposals: ${categorized.tempChecks.length} Temp Check(s), ${categorized.arfcs.length} ARFC(s), ${categorized.snapshots.length} generic Snapshot(s)`);
    
    return categorized;
  }
  
  /**
   * Categorize all AIP proposals
   * Returns: { aips: [] }
   */
  function categorizeAIPProposals(aipProposals) {
    const categorized = {
      aips: []
    };
    
    aipProposals.forEach(proposal => {
      if (!proposal || !proposal.data) {return;}
      
      // Use timestamp if already set, otherwise extract from data
      let timestamp = proposal.timestamp || 0;
      if (!timestamp || timestamp === 0) {
        // Extract timestamp from data - use daysLeft to infer recency
        if (proposal.data.daysLeft !== null && proposal.data.daysLeft !== undefined) {
          // Use daysLeft as proxy: more negative = older, more positive = newer
          // Convert to a timestamp-like value (larger = newer)
          timestamp = -proposal.data.daysLeft * 86400; // Convert days to seconds
        } else {
          // Fallback: use current time for proposals without timestamp
          timestamp = Date.now() / 1000;
        }
      }
      
      categorized.aips.push({
        ...proposal,
        timestamp,
        status: proposal.status || proposal.data.status || 'unknown'
      });
    });
    
    console.log(`🔵 [CATEGORIZE] AIP proposals: ${categorized.aips.length} AIP(s)`);
    
    return categorized;
  }
  
  /**
   * Select the best proposal from an array based on status and recency
   * Groups proposals by discussion URL, then selects the best one from each group
   * Priority: active → pending → closed/ended → failed
   * This ensures only ONE proposal is shown per discussion URL/type
   * This handles edge cases like:
   * - Multiple proposals on same forum topic (active vs ended) - shows active
   * - Failed + resubmitted proposals - shows active/resubmitted
   * - Executed (old) + Created (new) proposals - shows newer
   */
  /**
   * Get state priority for sorting (lower number = higher priority)
   * Priority order: active → pending → closed/ended → failed
   */
  function getStatePriority(status, type = 'snapshot') {
    const statusLower = (status || '').toLowerCase();
    
    if (type === 'aip') {
      // AIP states: active > created > pending > executed > cancelled > failed
      if (['active', 'open'].includes(statusLower)) {
        return 1;
      }
      if (['created'].includes(statusLower)) {
        return 2;
      }
      if (['pending'].includes(statusLower)) {
        return 3;
      }
      if (['executed', 'completed', 'succeeded', 'passed'].includes(statusLower)) {
        return 4;
      }
      if (['cancelled', 'expired'].includes(statusLower)) {
        return 5;
      }
      if (['failed', 'defeated'].includes(statusLower)) {
        return 6;
      }
    } else {
      // Snapshot states: active > pending > closed/passed/ended > failed
      if (['active', 'open'].includes(statusLower)) {
        return 1;
      }
      if (['pending'].includes(statusLower)) {
        return 2;
      }
      if (['closed', 'passed', 'ended'].includes(statusLower)) {
        return 3;
      }
      if (['failed', 'cancelled', 'expired'].includes(statusLower)) {
        return 4;
      }
    }
    
    return 99; // Unknown states get lowest priority
  }

  /**
   * Group proposals by discussion URL
   * Returns: Map<discussionUrl, proposals[]>
   */
  function groupProposalsByDiscussionUrl(proposals) {
    const groups = new Map();
    
    proposals.forEach(proposal => {
      // Get discussion URL from validation or proposal data
      const discussionUrl = proposal._validation?.discussionLink || 
                           proposal.data?.discussion || 
                           proposal.discussion || 
                           null;
      
      // Use 'no-discussion' as key for proposals without discussion URL
      const key = discussionUrl ? normalizeForumUrl(discussionUrl) || discussionUrl : 'no-discussion';
      
      if (!groups.has(key)) {
        groups.set(key, []);
      }
      groups.get(key).push(proposal);
    });
    
    return groups;
  }

  /**
   * Select the best proposal from a group, prioritizing by state
   * Priority: active → pending → closed → failed
   */
  function selectBestProposal(proposals, type = 'snapshot') {
    if (!proposals || proposals.length === 0) {return null;}
    if (proposals.length === 1) {return proposals[0];}
    
    console.log(`🔵 [SELECT] Selecting best proposal from ${proposals.length} ${type} proposal(s)`);
    
    // Group by discussion URL first
    const groups = groupProposalsByDiscussionUrl(proposals);
    
    // If all proposals have the same discussion URL (or no discussion URL), select best from all
    if (groups.size === 1) {
      const allProposals = Array.from(groups.values())[0];
      return selectBestProposalByState(allProposals, type);
    }
    
    // Multiple discussion groups - select best from each group, then best overall
    console.log(`🔵 [SELECT] Found ${groups.size} discussion group(s), selecting best from each`);
    const bestFromEachGroup = [];
    
    groups.forEach((groupProposals, discussionUrl) => {
      const best = selectBestProposalByState(groupProposals, type);
      if (best) {
        bestFromEachGroup.push(best);
        console.log(`   [GROUP] ${discussionUrl || 'no-discussion'}: selected "${best.data?.title?.substring(0, 50)}..." (status: ${best.data?.status || 'unknown'})`);
      }
    });
    
    // If we have multiple groups, select the best overall
    if (bestFromEachGroup.length > 1) {
      console.log(`🔵 [SELECT] Selecting best proposal from ${bestFromEachGroup.length} discussion group(s)`);
      return selectBestProposalByState(bestFromEachGroup, type);
    }
    
    return bestFromEachGroup[0] || null;
  }

  /**
   * Select best proposal by state priority (active → pending → closed/ended → failed)
   * This ensures only ONE proposal is shown per type, prioritizing active proposals
   */
  function selectBestProposalByState(proposals, type = 'snapshot') {
    if (!proposals || proposals.length === 0) {return null;}
    if (proposals.length === 1) {return proposals[0];}
    
    // Sort by: 1) state priority, 2) timestamp (newest first)
    const sorted = [...proposals].sort((a, b) => {
      const statusA = a.data?.status?.toLowerCase() || a.status?.toLowerCase() || '';
      const statusB = b.data?.status?.toLowerCase() || b.status?.toLowerCase() || '';
      
      const priorityA = getStatePriority(statusA, type);
      const priorityB = getStatePriority(statusB, type);
      
      // First sort by state priority (lower = better)
      if (priorityA !== priorityB) {
        return priorityA - priorityB;
    }
    
      // If same priority, sort by timestamp (newer = better)
      const timeA = a.timestamp || 0;
      const timeB = b.timestamp || 0;
      return timeB - timeA; // Descending (newest first)
    });
    
    const selected = sorted[0];
    const selectedStatus = selected.data?.status?.toLowerCase() || selected.status?.toLowerCase() || 'unknown';
    console.log(`✅ [SELECT] Selected proposal: "${selected.data?.title?.substring(0, 50)}..." (status: ${selectedStatus}, priority: ${getStatePriority(selectedStatus, type)})`);
    
    return selected;
  }
  
  /**
   * Select up to 3 snapshot proposals with distribution logic
   * If only one type exists, shows up to 3 of that type
   * If multiple types exist, distributes slots (e.g., 1 of each, or 2 of one type and 1 of another)
   * Prioritizes by status (active > pending > ended) and then by timestamp (newest first)
   * Returns: Array of { proposal, type, order } objects
   */
  function selectUpTo3SnapshotProposals(categorized) {
    const MAX_WIDGETS = 3;
    const selected = [];
    
    const tempChecks = categorized.tempChecks || [];
    const arfcs = categorized.arfcs || [];
    const snapshots = categorized.snapshots || [];
    
    // Sort each type by priority (status then timestamp)
    const sortProposals = (proposals) => {
      return [...proposals].sort((a, b) => {
        const statusA = a.data?.status?.toLowerCase() || a.status?.toLowerCase() || '';
        const statusB = b.data?.status?.toLowerCase() || b.status?.toLowerCase() || '';
        
        const priorityA = getStatePriority(statusA, 'snapshot');
        const priorityB = getStatePriority(statusB, 'snapshot');
        
        // First sort by state priority (lower = better)
        if (priorityA !== priorityB) {
          return priorityA - priorityB;
        }
        
        // If same priority, sort by timestamp (newer = better)
        const timeA = a.timestamp || 0;
        const timeB = b.timestamp || 0;
        return timeB - timeA; // Descending (newest first)
      });
    };
    
    const sortedTempChecks = sortProposals(tempChecks);
    const sortedARFCs = sortProposals(arfcs);
    const sortedSnapshots = sortProposals(snapshots);
    
    // Count how many types we have
    const typeCount = (sortedTempChecks.length > 0 ? 1 : 0) + 
                      (sortedARFCs.length > 0 ? 1 : 0) + 
                      (sortedSnapshots.length > 0 ? 1 : 0);
    
    if (typeCount === 0) {
      return [];
    }
    
    // If only one type exists, show up to 3 of that type
    if (typeCount === 1) {
      if (sortedTempChecks.length > 0) {
        return sortedTempChecks.slice(0, MAX_WIDGETS).map((proposal, idx) => ({
          proposal,
          type: 'temp-check',
          order: idx
        }));
      }
      if (sortedARFCs.length > 0) {
        return sortedARFCs.slice(0, MAX_WIDGETS).map((proposal, idx) => ({
          proposal,
          type: 'arfc',
          order: idx
        }));
      }
      if (sortedSnapshots.length > 0) {
        return sortedSnapshots.slice(0, MAX_WIDGETS).map((proposal, idx) => ({
          proposal,
          type: 'snapshot',
          order: idx
        }));
      }
    }
    
    // Multiple types exist - distribute slots
    // Strategy: Round-robin distribution, prioritizing best proposals from each type
    const typeQueues = [
      { proposals: sortedTempChecks, type: 'temp-check', index: 0 },
      { proposals: sortedARFCs, type: 'arfc', index: 0 },
      { proposals: sortedSnapshots, type: 'snapshot', index: 0 }
    ].filter(q => q.proposals.length > 0);
    
    // Round-robin selection: take one from each type in turn
    while (selected.length < MAX_WIDGETS && typeQueues.length > 0) {
      let foundAny = false;
      
      for (const queue of typeQueues) {
        if (selected.length >= MAX_WIDGETS) {
          break;
        }
        
        if (queue.index < queue.proposals.length) {
          selected.push({
            proposal: queue.proposals[queue.index],
            type: queue.type,
            order: selected.length
          });
          queue.index++;
          foundAny = true;
        }
      }
      
      // If we didn't find any proposals in this round, we're done
      if (!foundAny) {
        break;
      }
    }
    
    return selected;
  }
  
  /**
   * Get all proposals of a specific type (for timeline/history display)
   * Returns array sorted by timestamp (newest first)
   */
  // eslint-disable-next-line no-unused-vars
  function getAllProposalsOfType(proposals, _type = 'snapshot') {
    if (!proposals || proposals.length === 0) {return [];}
    
    // Sort by timestamp (newest first)
    return [...proposals].sort((a, b) => {
      const timeA = a.timestamp || 0;
      const timeB = b.timestamp || 0;
      return timeB - timeA; // Descending (newest first)
    });
  }
  
  /**
   * Detect ALL proposals of each type from fetched data
   * This is the main function that replaces findOne() patterns
   * Returns: { tempChecks: [], arfcs: [], aips: [] }
   */
  // eslint-disable-next-line no-unused-vars
  function detectAllProposalsByType(snapshotProposals, aipProposals) {
    const snapshotCategorized = categorizeSnapshotProposals(snapshotProposals || []);
    const aipCategorized = categorizeAIPProposals(aipProposals || []);
    
    return {
      tempChecks: snapshotCategorized.tempChecks,
      arfcs: snapshotCategorized.arfcs,
      aips: aipCategorized.aips,
      // Also include generic snapshots for completeness
      snapshots: snapshotCategorized.snapshots
    };
  }

  // Separate function to set up widget with proposals (to allow re-running after extraction)
  // Render widgets - one per proposal URL
  function setupTopicWidgetWithProposals(allProposals) {
    // CRITICAL: Only run on topic pages - prevent widgets from appearing on other pages
    const isTopicPage = window.location.pathname.match(/^\/t\//);
    if (!isTopicPage) {
      console.log("🔍 [TOPIC] Not on a topic page - skipping widget setup (prevents widgets on wrong pages)");
      return;
    }
    
    // CRITICAL: Early exit if widgets already exist - prevent ANY re-rendering that causes reload
    // This is the most important check to prevent page reloading/blinking
    const existingWidgetsCheck = document.querySelectorAll('.tally-status-widget-container');
    if (existingWidgetsCheck.length > 0 && widgetSetupCompleted) {
      console.log(`🔵 [TOPIC] Widgets already exist (${existingWidgetsCheck.length} widget(s)) and setup completed - EXITING to prevent reload`);
      hideMainWidgetLoader();
      return; // CRITICAL: Exit immediately to prevent any re-rendering
    }
    
    // Note: Don't check isWidgetSetupRunning here - that flag is for debouncedSetupTopicWidget
    // This function can be called multiple times if proposals change
    
    // Check if widgets already exist and match current proposals - if so, don't clear them
    // CRITICAL: Separate AIP widgets from Snapshot widgets - AIP widgets should never be cleared
    const existingWidgets = document.querySelectorAll('.tally-status-widget-container');
    const existingAIPWidgets = [];
    const existingSnapshotWidgets = [];
    const existingUrls = new Set();
    
    existingWidgets.forEach(widget => {
      const widgetType = widget.getAttribute('data-proposal-type');
      const widgetTypeAttr = widget.getAttribute('data-widget-type');
      const hasAIP = widget.querySelector('.governance-stage[data-stage="aip"]') !== null;
      const url = widget.getAttribute('data-tally-url') || '';
      const isAIPUrl = url.includes('vote.onaave.com') || url.includes('app.aave.com/governance') || url.includes('governance.aave.com/aip/');
      const isAIPWidget = widgetType === 'aip' || widgetTypeAttr === 'aip' || hasAIP || isAIPUrl;
      
      if (isAIPWidget) {
        existingAIPWidgets.push(widget);
      } else {
        existingSnapshotWidgets.push(widget);
      }
      
      const widgetUrl = widget.getAttribute('data-tally-url');
      if (widgetUrl && !isAIPWidget) {
        // Only add Snapshot URLs to the comparison set (AIP widgets are handled separately)
        const normalizedUrl = normalizeAIPUrl(widgetUrl);
        existingUrls.add(normalizedUrl);
      }
    });
    
    // Normalize all current proposal URLs for comparison (only Snapshot URLs)
    // AIP URLs are handled separately - if AIP widgets exist, keep them regardless
    const currentUrls = new Set([...allProposals.snapshot]); // Only Snapshot URLs for comparison
    
    // Check if Snapshot widgets match (AIP widgets are always preserved)
    const snapshotUrlsMatch = existingUrls.size === currentUrls.size && 
                     [...existingUrls].every(url => currentUrls.has(url)) &&
                     [...currentUrls].every(url => existingUrls.has(url));
    
    // CRITICAL: If AIP widgets already exist, ALWAYS preserve them and ensure they're visible
    // AIP widgets are topic-level and should never be removed, regardless of proposals found
    if (existingAIPWidgets.length > 0) {
      console.log(`✅ [TOPIC] Found ${existingAIPWidgets.length} existing AIP widget(s) - they will be preserved and kept visible`);
      // Force visibility for existing AIP widgets
      ensureAIPWidgetsVisible();
    }
    
    // CRITICAL: If widgets already exist and match, skip re-render to prevent page reload/blinking
    // Check both normalized and original URLs to ensure proper matching
    const normalizeUrlForComparison = (url) => {
      if (!url) {
        return '';
      }
      return url.trim().replace(/\/+$/, '').split('?')[0].split('#')[0].toLowerCase();
    };
    
    // Normalize all current Snapshot URLs for comparison
    const normalizedCurrentUrls = new Set(allProposals.snapshot.map(url => normalizeUrlForComparison(url)));
    const normalizedExistingUrls = new Set();
    existingSnapshotWidgets.forEach(widget => {
      const widgetUrl = widget.getAttribute('data-tally-url');
      if (widgetUrl) {
        normalizedExistingUrls.add(normalizeUrlForComparison(widgetUrl));
      }
    });
    
    // Check if normalized URLs match (more reliable than exact match)
    const normalizedUrlsMatch = normalizedExistingUrls.size === normalizedCurrentUrls.size &&
                                [...normalizedExistingUrls].every(url => normalizedCurrentUrls.has(url)) &&
                                [...normalizedCurrentUrls].every(url => normalizedExistingUrls.has(url));
    
    // If Snapshot widgets match (by normalized URL) and we have the expected AIP widgets, skip re-render
    // AIP widgets are preserved regardless
    if ((snapshotUrlsMatch || normalizedUrlsMatch) && existingSnapshotWidgets.length === allProposals.snapshot.length && 
        existingAIPWidgets.length >= allProposals.aip.length) {
      console.log(`🔵 [TOPIC] Widgets already match current proposals (${existingWidgets.length} widget(s): ${existingSnapshotWidgets.length} Snapshot, ${existingAIPWidgets.length} AIP), skipping re-render to prevent reload`);
      // Still ensure AIP widgets are visible
      ensureAIPWidgetsVisible();
      // Hide loader since widgets already exist
      hideMainWidgetLoader();
      // Mark as completed since widgets already exist and match
      widgetSetupCompleted = true;
      // CRITICAL: Reset running flag to allow future updates if needed
      isWidgetSetupRunning = false;
      return; // Don't re-render if widgets already match - prevents page reload
    }
    
    // Clear existing widgets only if proposals have changed
    // CRITICAL: Never clear AIP widgets - they are topic-level and should always stay visible
    // CRITICAL: Only clear widgets if URLs don't match - prevents blinking on navigation
    // CRITICAL: Use normalized URL comparison to prevent false mismatches that cause reload
    if (existingWidgets.length > 0) {
      // Check if we need to clear widgets - use normalized URL comparison for reliability
      const needsClearing = (!snapshotUrlsMatch && !normalizedUrlsMatch) || existingSnapshotWidgets.length !== allProposals.snapshot.length;
      
      if (needsClearing) {
        console.log(`🔵 [TOPIC] Proposals changed - clearing ${existingWidgets.length} existing widget(s) before creating new ones (AIP widgets will be preserved)`);
        existingWidgets.forEach(widget => {
          // Check if this is an AIP widget - if so, skip it (never remove AIP widgets)
          const widgetType = widget.getAttribute('data-proposal-type');
          const widgetTypeAttr = widget.getAttribute('data-widget-type');
          const hasAIP = widget.querySelector('.governance-stage[data-stage="aip"]') !== null;
          const url = widget.getAttribute('data-tally-url') || '';
          const isAIPUrl = url.includes('vote.onaave.com') || url.includes('app.aave.com/governance') || url.includes('governance.aave.com/aip/');
          
          if (widgetType === 'aip' || widgetTypeAttr === 'aip' || hasAIP || isAIPUrl) {
            console.log("🔵 [WIDGET] Preserving AIP widget during proposal change - type:", widgetType, "widgetType:", widgetTypeAttr);
            return; // Skip AIP widgets - never remove them
          }
          
          // Only remove Snapshot widgets that don't match current proposals
          const widgetUrl = widget.getAttribute('data-tally-url');
          if (widgetUrl) {
            // For Snapshot URLs, compare directly (they're already in currentUrls as-is)
            // Only remove if URL is not in current proposals
            if (!currentUrls.has(widgetUrl)) {
              // Remove from tracking sets when clearing widget
              renderingUrls.delete(widgetUrl);
              fetchingUrls.delete(widgetUrl);
              widget.remove();
            } else {
              console.log(`🔵 [WIDGET] Preserving widget with matching URL: ${widgetUrl}`);
            }
          } else {
            // No URL - remove it
            widget.remove();
          }
        });
      } else {
        console.log(`🔵 [TOPIC] Widgets match current proposals - skipping widget clearing to prevent blinking`);
      }
    }
    
    // Also clear the container if it exists (will be recreated if needed)
    // CRITICAL: Don't remove container if it has AIP widgets
    const container = document.getElementById('governance-widgets-wrapper');
    if (container) {
      // Check if there are any AIP widgets in the container
      const aipWidgetsInContainer = container.querySelectorAll('.tally-status-widget-container[data-proposal-type="aip"], .tally-status-widget-container[data-widget-type="aip"]');
      if (aipWidgetsInContainer.length === 0) {
        container.remove();
        console.log("🔵 [TOPIC] Cleared widgets container (no AIP widgets)");
      } else {
        console.log(`🔵 [TOPIC] Keeping widgets container because it has ${aipWidgetsInContainer.length} AIP widget(s)`);
      }
    }
    
    // Clear tracking sets only for URLs that were actually removed
    // URLs for preserved widgets are already handled above (removed from sets when widgets are removed)
    // Only clear tracking for URLs that don't have corresponding widgets anymore
    // This prevents re-rendering preserved widgets while allowing new widgets to be created
    
    // Only clear widgets if there are no proposals at all
    // hideWidgetIfNoProposal() already preserves AIP widgets, so it's safe to call
    if (allProposals.snapshot.length === 0 && allProposals.aip.length === 0) {
      console.log("🔵 [TOPIC] No proposals found - removing widgets (AIP widgets preserved if any exist)");
      hideWidgetIfNoProposal(); // This function already preserves AIP widgets
      // Still ensure any existing AIP widgets stay visible
      ensureAIPWidgetsVisible();
      // Hide loader since there are no proposals to show
      hideMainWidgetLoader();
      return;
    }
    
    // CRITICAL: Always ensure existing AIP widgets stay visible
    // This ensures AIP widgets persist even when setupTopicWidgetWithProposals is called multiple times
    ensureAIPWidgetsVisible();
    
    // Normalize and deduplicate URLs to prevent creating multiple widgets for the same proposal
    // For AIP URLs, normalize to base URL (ignore query parameters like ipfsHash)
    // For Snapshot URLs, use as-is (they're already unique by space/proposalId)
    const normalizedAipUrls = allProposals.aip.map(url => normalizeAIPUrl(url));
    
    // Create a map from normalized AIP URL to original URL to preserve the original for display
    const aipUrlMap = new Map();
    allProposals.aip.forEach((url, index) => {
      const normalized = normalizedAipUrls[index];
      if (!aipUrlMap.has(normalized)) {
        aipUrlMap.set(normalized, url);
      }
    });
    
    // Get unique URLs
    // Snapshot URLs: use as-is (already unique)
    const uniqueSnapshotUrls = [...new Set(allProposals.snapshot)];
    // AIP URLs: deduplicate by normalized URL, then map back to original
    // Use let instead of const so we can update it after cascading search
    let uniqueAipUrls = [...new Set(normalizedAipUrls)].map(normalized => aipUrlMap.get(normalized));
    
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
      // Normalize URLs for comparison to handle query parameter variations
      const snapshotUrlsToFetch = uniqueSnapshotUrls.filter(url => {
        const normalizedUrl = normalizeAIPUrl(url);
        if (fetchingUrls.has(normalizedUrl) || renderingUrls.has(normalizedUrl) || 
            fetchingUrls.has(url) || renderingUrls.has(url)) {
          console.log(`🔵 [TOPIC] Snapshot URL ${url} is already being fetched/rendered, skipping duplicate`);
          return false;
        }
        fetchingUrls.add(normalizedUrl);
        fetchingUrls.add(url); // Also add original for backward compatibility
        
        // Global loader is already created above - no need for individual loaders
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
          
          // Filter out failures that are due to invalid types (not AIP or Snapshot)
          // Only show errors for actual network/fetch failures, not for unsupported proposal types
          const actualFailures = failedSnapshots.filter(result => {
            // Check if the failure was due to invalid type (silently skipped)
            if (result.status === 'fulfilled' && result.value && result.value.type === 'snapshot' && !result.value.data) {
              // This might be a type mismatch - check if URL doesn't match Snapshot pattern
              const url = result.value.url || '';
              if (!url.includes('snapshot.org') && !url.includes('snapshot.box')) {
                // Not a Snapshot URL - silently skip, don't count as error
                return false;
              }
            }
            return true;
          });
          
          if (actualFailures.length > 0 && validSnapshots.length === 0) {
            // All proposals failed - show error message (only for actual failures, not type mismatches)
            console.warn(`⚠️ [TOPIC] All ${uniqueSnapshotUrls.length} Snapshot proposal(s) failed to load. This may be a temporary network issue.`);
            // Optionally show a user-visible error widget
            showNetworkErrorWidget(uniqueSnapshotUrls.length, 'snapshot');
          } else if (actualFailures.length > 0) {
            console.warn(`⚠️ [TOPIC] ${actualFailures.length} out of ${uniqueSnapshotUrls.length} Snapshot proposal(s) failed to load`);
          }
          
          console.log(`🔵 [TOPIC] Found ${validSnapshots.length} valid Snapshot proposal(s) out of ${snapshotUrlsToFetch.length} unique URL(s)`);
          
          // ===== EXTRACT AIP URLs FROM SNAPSHOT PROPOSALS (CASCADING SEARCH) =====
          // Check if any Snapshot proposals contain AIP URLs in their descriptions
          console.log(`🔍 [CASCADE] Starting cascading search for AIP URLs in ${validSnapshots.length} Snapshot proposal(s)`);
          const extractedAipUrls = [];
          validSnapshots.forEach((snapshot, idx) => {
            console.log(`🔍 [CASCADE] Checking Snapshot proposal ${idx + 1}/${validSnapshots.length}: "${snapshot.data?.title?.substring(0, 50)}..."`);
            const aipUrl = extractAIPUrlFromSnapshot(snapshot.data);
            if (aipUrl) {
              console.log(`✅ [CASCADE] Found AIP URL in Snapshot proposal "${snapshot.data.title?.substring(0, 50)}...": ${aipUrl}`);
              if (!extractedAipUrls.includes(aipUrl)) {
                extractedAipUrls.push(aipUrl);
              }
            } else {
              console.log(`❌ [CASCADE] No AIP URL found in Snapshot proposal ${idx + 1}`);
            }
          });
          console.log(`🔍 [CASCADE] Cascading search complete - found ${extractedAipUrls.length} AIP URL(s)`);
          
          // If AIP URLs were found, add them to proposals and trigger widget update
          if (extractedAipUrls.length > 0) {
            console.log(`🔵 [CASCADE] Found ${extractedAipUrls.length} AIP URL(s) in Snapshot proposals - adding to proposals list`);
            console.log(`🔵 [CASCADE] AIP URLs to add:`, extractedAipUrls);
            
            // Update allProposals.aip with extracted URLs
            const previousAipCount = allProposals.aip.length;
            allProposals.aip = [...new Set([...allProposals.aip, ...extractedAipUrls])];
            console.log(`🔵 [CASCADE] Updated allProposals.aip - now has ${allProposals.aip.length} AIP URL(s) (was ${previousAipCount})`);
            
            // Recalculate uniqueAipUrls since we added new URLs
            const updatedNormalizedAipUrls = allProposals.aip.map(url => normalizeAIPUrl(url));
            const updatedAipUrlMap = new Map();
            allProposals.aip.forEach((url, index) => {
              const normalized = updatedNormalizedAipUrls[index];
              if (!updatedAipUrlMap.has(normalized)) {
                updatedAipUrlMap.set(normalized, url);
              }
            });
            // Update uniqueAipUrls for the AIP widgets section to use
            uniqueAipUrls = [...new Set(updatedNormalizedAipUrls)].map(normalized => updatedAipUrlMap.get(normalized));
            console.log(`🔵 [CASCADE] Recalculated uniqueAipUrls - now has ${uniqueAipUrls.length} unique AIP URL(s)`);
          }
          
          // ===== VALIDATE PROPOSALS FOR FORUM TOPIC =====
          // Check if proposals are related to current forum topic, but show all proposals
          // Proposals not related to current forum will show their discussion link
          const currentForumUrl = getCurrentForumTopicUrl();
          console.log(`🔍 [VALIDATE] Current forum URL: ${currentForumUrl || 'NOT ON FORUM PAGE'}`);
          console.log(`🔍 [VALIDATE] Validating ${validSnapshots.length} Snapshot proposal(s) against forum topic...`);
          const validatedSnapshots = validSnapshots.map(proposal => {
            const validation = validateSnapshotProposalForForum(proposal, currentForumUrl);
            // Add validation info to proposal object
            proposal._validation = validation;
            return proposal;
          });
          
          const relatedCount = validatedSnapshots.filter(p => p._validation.isRelated).length;
          const unrelatedCount = validatedSnapshots.length - relatedCount;
          if (unrelatedCount > 0) {
            console.log(`🔵 [VALIDATE] ${unrelatedCount} Snapshot proposal(s) not related to forum topic - will show with discussion link`);
          }
          
          // ===== CATEGORIZE ALL PROPOSALS BY TYPE =====
          // This handles edge cases: multiple Temp Checks, multiple ARFCs, etc.
          const categorized = categorizeSnapshotProposals(validatedSnapshots);
          
          // ===== SELECT UP TO 3 PROPOSALS WITH DISTRIBUTION LOGIC =====
          // If only one type exists, shows up to 3 of that type
          // If multiple types exist, distributes slots (e.g., 1 of each, or 2 of one type and 1 of another)
          const proposalsToRender = selectUpTo3SnapshotProposals(categorized);
          
          // Log what we found
          if (categorized.tempChecks.length > 1) {
            console.log(`🔵 [EDGE-CASE] Found ${categorized.tempChecks.length} Temp Check(s) - selected up to 3`);
            categorized.tempChecks.forEach((tc, idx) => {
              console.log(`   [${idx + 1}] ${tc.data?.title?.substring(0, 60)}... (status: ${tc.data?.status || 'unknown'})`);
            });
          }
          if (categorized.arfcs.length > 1) {
            console.log(`🔵 [EDGE-CASE] Found ${categorized.arfcs.length} ARFC(s) - selected up to 3`);
            categorized.arfcs.forEach((arfc, idx) => {
              console.log(`   [${idx + 1}] ${arfc.data?.title?.substring(0, 60)}... (status: ${arfc.data?.status || 'unknown'})`);
            });
          }
          
          // Count by type for logging
          const tempCheckCount = proposalsToRender.filter(p => p.type === 'temp-check').length;
          const arfcCount = proposalsToRender.filter(p => p.type === 'arfc').length;
          const snapshotCount = proposalsToRender.filter(p => p.type === 'snapshot').length;
          
          console.log(`🔵 [RENDER] Total snapshot widgets to render: ${proposalsToRender.length} (Temp Check: ${tempCheckCount}, ARFC: ${arfcCount}, Snapshot: ${snapshotCount})`);
          
          // Render each selected proposal
          proposalsToRender.forEach(({ proposal: snapshot, type: stageType, order: typeOrder }, index) => {
            // Check again if URL is being rendered (in case another fetch completed first)
            // Normalize URL for comparison
            const normalizedUrl = normalizeAIPUrl(snapshot.url);
            if (renderingUrls.has(normalizedUrl) || renderingUrls.has(snapshot.url)) {
              console.log(`🔵 [TOPIC] Snapshot URL ${snapshot.url} is already being rendered, skipping duplicate render`);
              return;
            }
            
            const stage = snapshot.data.stage || 'snapshot';
            const stageName = stage === 'temp-check' ? 'Temp Check' : 
                             stage === 'arfc' ? 'ARFC' : 'Snapshot';
            
            // Find proposal order in combined list (order in content)
            const proposalOrderIndex = orderedProposals.findIndex(p => p.url === snapshot.url && p.type === 'snapshot');
            const proposalOrder = proposalOrderIndex >= 0 ? proposalOrderIndex : typeOrder;
            
            console.log(`🔵 [RENDER] Creating Snapshot widget ${index + 1}/${proposalsToRender.length} for ${stageName} (order: ${proposalOrder})`);
            console.log(`   Title: ${snapshot.data.title?.substring(0, 60)}...`);
            console.log(`   URL: ${snapshot.url}`);
            if (stageType === 'temp-check' && categorized.tempChecks.length > 1) {
              console.log(`   ⚠️ Note: Selected from ${categorized.tempChecks.length} Temp Check(s) found in thread`);
            }
            if (stageType === 'arfc' && categorized.arfcs.length > 1) {
              console.log(`   ⚠️ Note: Selected from ${categorized.arfcs.length} ARFC(s) found in thread`);
            }
            
            // CRITICAL: Check if widget already exists with this URL before creating new ID
            // This enables in-place updates to prevent blinking (same as Tally widgets)
            // If widget exists, use its existing ID; otherwise create stable ID from URL
            let widgetId;
            const existingWidgetByUrl = document.querySelector(`.tally-status-widget-container[data-tally-url="${snapshot.url}"]`);
            if (existingWidgetByUrl) {
              // Widget exists - extract its ID to enable in-place update
              const existingWidgetId = existingWidgetByUrl.id;
              if (existingWidgetId && existingWidgetId.startsWith('aave-governance-widget-')) {
                // Extract the widget ID from the existing widget's ID
                widgetId = existingWidgetId.replace('aave-governance-widget-', '');
                console.log(`🔵 [RENDER] Snapshot widget with URL ${snapshot.url} already exists (ID: ${existingWidgetId}), will update in place to prevent blinking`);
              } else {
                // Fallback: use data-widget-id attribute or generate stable ID
                widgetId = existingWidgetByUrl.getAttribute('data-widget-id') || `snapshot-widget-${Math.abs(snapshot.url.split('').reduce((acc, char) => ((acc << 5) - acc) + char.charCodeAt(0), 0))}`;
                console.log(`🔵 [RENDER] Snapshot widget exists but ID format unexpected, using: ${widgetId}`);
              }
            } else {
              // No existing widget - create stable widget ID based on URL (not timestamp)
              // This prevents blinking by allowing the widget to be updated in place on subsequent renders
              const urlHash = snapshot.url.split('').reduce((acc, char) => {
                const hash = ((acc << 5) - acc) + char.charCodeAt(0);
                return hash & hash; // Convert to 32-bit integer
              }, 0);
              widgetId = `snapshot-widget-${Math.abs(urlHash)}`;
            }
            
            // Get validation info (discussion link if not related to current forum)
            const validation = snapshot._validation || { isRelated: true, discussionLink: null };
            console.log(`🔵 [VALIDATION] ${stageName} validation data:`, {
              isRelated: validation.isRelated,
              discussionLink: validation.discussionLink,
              hasValidation: !!snapshot._validation
            });
            
            // CRITICAL: Only show proposals that have a forum link matching the current forum topic
            // This prevents false positives when other proposal links are mentioned in discussions
            // Also filter out proposals without any discourse URL
            if (!validation.isRelated) {
              if (validation.discussionLink) {
                console.log(`⚠️ [RENDER] Skipping ${stageName} widget - discussion URL (${validation.discussionLink}) does not match current forum topic`);
              } else {
                console.log(`⚠️ [RENDER] Skipping ${stageName} widget - no forum discussion link found in proposal (preventing false positives)`);
              }
              return;
            }
            
            // Filter out proposals that don't have any discourse URL
            if (!validation.discussionLink) {
              console.log(`⚠️ [RENDER] Skipping ${stageName} widget - proposal has no discourse URL`);
              return;
            }
            
            // Render single proposal widget based on its stage, with proposal order
            renderMultiStageWidget({
              tempCheck: stage === 'temp-check' ? snapshot.data : null,
              tempCheckUrl: stage === 'temp-check' ? snapshot.url : null,
              arfc: (stage === 'arfc' || stage === 'snapshot') ? snapshot.data : null,
              arfcUrl: (stage === 'arfc' || stage === 'snapshot') ? snapshot.url : null,
              aip: null,
              aipUrl: null
            }, widgetId, proposalOrder, validation.discussionLink, validation.isRelated);
            
            console.log(`✅ [RENDER] Snapshot widget ${index + 1} rendered`);
            
            // CRITICAL: Ensure widget is visible immediately after rendering
            setTimeout(() => {
              ensureAIPWidgetsVisible();
            }, 100);
          });
        })
        .catch(error => {
          console.error("❌ [TOPIC] Error processing Snapshot proposals:", error);
        });
    }
    
    // ===== AIP WIDGETS - Fetch all, then categorize and select best =====
    if (uniqueAipUrls.length > 0) {
      // Filter out forum topic URLs - they are NOT AIP proposal URLs
      const validAipUrls = uniqueAipUrls.filter(url => {
        if (url && url.includes('governance.aave.com/t/')) {
          console.log(`⚠️ [TOPIC] Filtering out forum topic URL (not an AIP proposal): ${url}`);
          return false;
        }
        return true;
      });
      
      if (validAipUrls.length === 0) {
        console.log(`🔵 [TOPIC] No valid AIP URLs after filtering (all were forum topic URLs)`);
      } else {
        console.log(`🔵 [TOPIC] Processing ${validAipUrls.length} valid AIP URL(s) (filtered out ${uniqueAipUrls.length - validAipUrls.length} forum topic URL(s))`);
      }
      
      // Fetch all AIP proposals first
      const aipPromises = validAipUrls.map((aipUrl, aipIndex) => {
        // Check if this URL is already being fetched or rendered
        const normalizedUrl = normalizeAIPUrl(aipUrl);
        if (fetchingUrls.has(normalizedUrl) || renderingUrls.has(normalizedUrl) ||
            fetchingUrls.has(aipUrl) || renderingUrls.has(aipUrl)) {
          console.log(`🔵 [TOPIC] AIP URL ${aipUrl} is already being fetched/rendered, skipping duplicate`);
          return Promise.resolve({ url: aipUrl, data: null, skipped: true });
        }
        
        // Mark URL as being fetched (both normalized and original)
        fetchingUrls.add(normalizedUrl);
        fetchingUrls.add(aipUrl);
        
        // Global loader is already created above - no need for individual loaders
        console.log(`🔵 [TOPIC] Fetching AIP proposal ${aipIndex + 1} from: ${aipUrl}`);
        return fetchProposalDataByType(aipUrl, 'aip')
          .then(aipData => {
            console.log(`🔵 [TOPIC] AIP fetch completed for ${aipUrl}:`, aipData ? 'Success' : 'No data');
            // Remove from fetching set when fetch completes
            fetchingUrls.delete(normalizedUrl);
            fetchingUrls.delete(aipUrl);
            return { url: aipUrl, data: aipData, skipped: false };
          })
          .catch(error => {
            // Remove from fetching set on error
            fetchingUrls.delete(normalizedUrl);
            fetchingUrls.delete(aipUrl);
            console.error(`❌ [TOPIC] Error fetching AIP ${aipIndex + 1} from ${aipUrl}:`, error);
            return { url: aipUrl, data: null, skipped: false, error: error.message || String(error) };
          });
      });
      
      Promise.allSettled(aipPromises)
        .then(async aipResults => {
          // Filter out skipped and invalid data
          const validAIPs = aipResults
            .filter(result => result.status === 'fulfilled' && 
                             result.value && 
                             !result.value.skipped && 
                             result.value.data && 
                             result.value.data.title)
            .map(result => ({
              url: result.value.url,
              data: result.value.data,
              timestamp: result.value.data.startTime || result.value.data.createdAt || 0,
              status: result.value.data.status || 'unknown'
            }));
          
          console.log(`🔵 [TOPIC] Found ${validAIPs.length} valid AIP proposal(s) out of ${uniqueAipUrls.length} unique URL(s)`);
          
          // ===== VALIDATE PROPOSALS FOR FORUM TOPIC =====
          // Check if proposals are related to current forum topic, but show all proposals
          // Proposals not related to current forum will show their discussion link
          const currentForumUrl = getCurrentForumTopicUrl();
          const validatedAIPs = await Promise.all(validAIPs.map(async proposal => {
            const validation = await validateAIPProposalForForum(proposal, currentForumUrl);
            // Add validation info to proposal object
            proposal._validation = validation;
            return proposal;
          }));
          
          const relatedCount = validatedAIPs.filter(p => p._validation.isRelated).length;
          const unrelatedCount = validatedAIPs.length - relatedCount;
          if (unrelatedCount > 0) {
            console.log(`🔵 [VALIDATE] ${unrelatedCount} AIP proposal(s) not related to forum topic - will show with discussion link`);
          }
          
          // ===== CATEGORIZE ALL AIP PROPOSALS =====
          const categorized = categorizeAIPProposals(validatedAIPs);
          
          // ===== SELECT BEST AIP PROPOSAL =====
          // Handle edge case: multiple AIPs (e.g., failed + resubmitted, or historical reference)
          const bestAIP = selectBestProposal(categorized.aips, 'aip');
          
          if (categorized.aips.length > 1) {
            console.log(`🔵 [EDGE-CASE] Found ${categorized.aips.length} AIP(s) - selected best one`);
            categorized.aips.forEach((aip, idx) => {
              console.log(`   [${idx + 1}] ${aip.data?.title?.substring(0, 60)}... (status: ${aip.status || 'unknown'})`);
            });
          }
          
          // ===== CHECK EXISTING WIDGET COUNT =====
          // Count how many widgets already exist (from snapshot proposals)
          // Only render AIPs if total widgets < 3
          // Use requestAnimationFrame to ensure snapshot widgets are in DOM before counting
          // Use .tally-status-widget-container which is the actual widget container
          requestAnimationFrame(() => {
            const existingWidgetsCount = document.querySelectorAll('.tally-status-widget-container').length;
            const maxWidgets = 3;
            const remainingSlots = maxWidgets - existingWidgetsCount;
            
            console.log(`🔵 [RENDER] Existing widgets: ${existingWidgetsCount}, Remaining slots: ${remainingSlots}`);
            
            // ===== RENDER WIDGET FOR SELECTED AIP =====
            // Only render if we have remaining slots and a valid AIP
            if (bestAIP && bestAIP.data && bestAIP.data.title && remainingSlots > 0) {
              const normalizedUrl = normalizeAIPUrl(bestAIP.url);
              
              // CRITICAL: Check if widget already exists by URL (same as Snapshot widgets do)
              // This prevents re-rendering the same widget multiple times
              const existingWidgetByUrl = document.querySelector(`.tally-status-widget-container[data-tally-url="${bestAIP.url}"], .tally-status-widget-container[data-tally-url="${normalizedUrl}"]`);
              if (existingWidgetByUrl) {
                console.log(`🔵 [TOPIC] AIP widget with URL ${bestAIP.url} already exists, skipping duplicate render`);
                // Remove from tracking sets since widget already exists
                renderingUrls.delete(normalizedUrl);
                renderingUrls.delete(bestAIP.url);
                fetchingUrls.delete(normalizedUrl);
                fetchingUrls.delete(bestAIP.url);
                return;
              }
              
              if (renderingUrls.has(normalizedUrl) || renderingUrls.has(bestAIP.url)) {
                console.log(`🔵 [TOPIC] AIP URL ${bestAIP.url} is already being rendered, skipping duplicate render`);
                return;
              }
              
              // Find proposal order in combined list (order in content)
              const proposalOrderIndex = orderedProposals.findIndex(p => p.url === bestAIP.url && p.type === 'aip');
              const proposalOrder = proposalOrderIndex >= 0 ? proposalOrderIndex : (uniqueSnapshotUrls.length + 0);
              
              // Use stable widget ID based on URL (same approach as Snapshot widgets)
              // Extract proposal ID from URL for stable ID generation
              const proposalInfo = extractAIPProposalInfo(bestAIP.url);
              const proposalId = proposalInfo?.proposalId || bestAIP.url.split('').reduce((acc, char) => ((acc << 5) - acc) + char.charCodeAt(0), 0);
              const aipWidgetId = `aip-widget-${proposalId}`;
              
              console.log(`🔵 [RENDER] Creating AIP widget (order: ${proposalOrder}, ID: ${aipWidgetId})`);
              console.log(`🔵 [RENDER] AIP data:`, { title: bestAIP.data.title, status: bestAIP.status, url: bestAIP.url });
              if (categorized.aips.length > 1) {
                console.log(`   ⚠️ Note: Selected from ${categorized.aips.length} AIP(s) found in thread`);
              }
              
              // Get validation info (discussion link if not related to current forum)
              const validation = bestAIP._validation || { isRelated: true, discussionLink: null };
              console.log(`🔵 [VALIDATION] AIP validation data:`, {
                isRelated: validation.isRelated,
                discussionLink: validation.discussionLink,
                hasValidation: !!bestAIP._validation
              });
              
              // CRITICAL: Only show proposals that have a forum link matching the current forum topic
              // This prevents false positives when other proposal links are mentioned in discussions
              // Also filter out proposals without any discourse URL
              if (!validation.isRelated) {
                if (validation.discussionLink) {
                  console.log(`⚠️ [RENDER] Skipping AIP widget - discussion URL (${validation.discussionLink}) does not match current forum topic`);
                } else {
                  console.log(`⚠️ [RENDER] Skipping AIP widget - no forum discussion link found in proposal (preventing false positives)`);
                }
                return;
              }
              
              // Filter out proposals that don't have any discourse URL
              if (!validation.discussionLink) {
                console.log(`⚠️ [RENDER] Skipping AIP widget - proposal has no discourse URL`);
                return;
              }
              
              // Render AIP widget - use same approach as Snapshot widgets
              renderMultiStageWidget({
                tempCheck: null,
                tempCheckUrl: null,
                arfc: null,
                arfcUrl: null,
                aip: bestAIP.data,
                aipUrl: bestAIP.url
              }, aipWidgetId, proposalOrder, validation.discussionLink, validation.isRelated);
              console.log(`✅ [RENDER] AIP widget rendered`);
              
              // CRITICAL: Immediately ensure AIP widget stays visible (topic-level widget, not viewport-dependent)
              // Use requestAnimationFrame to ensure widget is in DOM before checking
              requestAnimationFrame(() => {
                requestAnimationFrame(() => {
                  ensureAIPWidgetsVisible();
                  console.log(`✅ [AIP] Ensured AIP widget visibility immediately after render`);
                });
              });
              
              // CRITICAL: AIP widgets render asynchronously (in Promise callback) while Snapshot renders synchronously
              // This causes AIP widgets to be inserted later, after Discourse may have applied lazy loading CSS
              // Force immediate visibility RIGHT AFTER rendering for BOTH mobile and desktop
              // Track if widget is already visible to prevent unnecessary checks
              let widgetIsVisible = false;
              
              // Use requestAnimationFrame to catch widget immediately after insertion (works for both mobile and desktop)
              requestAnimationFrame(() => {
                requestAnimationFrame(() => {
                  const aipWidget = document.getElementById(`aave-governance-widget-${aipWidgetId}`);
                  if (aipWidget && aipWidget.parentNode) {
                    // Force visibility immediately - same as Snapshot widgets
                    aipWidget.style.setProperty('display', 'block', 'important');
                    aipWidget.style.setProperty('visibility', 'visible', 'important');
                    aipWidget.style.setProperty('opacity', '1', 'important');
                    aipWidget.classList.remove('hidden', 'd-none', 'is-hidden');
                    
                    // Force reflow
                    void aipWidget.offsetHeight;
                    
                    // Verify it's visible
                    const computedStyle = window.getComputedStyle(aipWidget);
                    // Use screen width only - don't rely on user agent as tablets/desktops may have mobile-like user agents
                    const isMobile = window.innerWidth <= 1400;
                    const deviceType = isMobile ? 'MOBILE' : 'DESKTOP';
                    console.log(`🔵 [${deviceType}] AIP widget after insertion - display: ${computedStyle.display}, visibility: ${computedStyle.visibility}, opacity: ${computedStyle.opacity}`);
                    
                    // Check if widget is actually visible (don't remove/re-insert - that causes blinking)
                    if (computedStyle.display !== 'none' && computedStyle.visibility !== 'hidden' && computedStyle.opacity !== '0') {
                      widgetIsVisible = true;
                      console.log(`✅ [${deviceType}] AIP widget is visible - no further checks needed`);
                    } else {
                      // Widget is hidden - just force styles without removing from DOM (prevents blinking)
                      console.warn(`⚠️ [${deviceType}] AIP widget still hidden after force - applying style fixes only`);
                      aipWidget.style.setProperty('display', 'block', 'important');
                      aipWidget.style.setProperty('visibility', 'visible', 'important');
                      aipWidget.style.setProperty('opacity', '1', 'important');
                      aipWidget.classList.remove('hidden', 'd-none', 'is-hidden');
                      // Force another reflow
                      void aipWidget.offsetHeight;
                    }
                    
                    console.log(`✅ [${deviceType}] AIP widget visibility forced immediately after render`);
                  } else {
                    // Use screen width only - don't rely on user agent as tablets/desktops may have mobile-like user agents
                    const isMobile = window.innerWidth <= 1400;
                    const deviceType = isMobile ? 'MOBILE' : 'DESKTOP';
                    console.warn(`⚠️ [${deviceType}] AIP widget not found in DOM yet: aave-governance-widget-${aipWidgetId}`);
                  }
                });
              });
              
              // Reduced delayed checks - only check if widget is not yet visible (prevents blinking from repeated checks)
              // Works for both mobile and desktop
              const checkDelays = [100, 300, 600];
              checkDelays.forEach((delay, index) => {
                setTimeout(() => {
                  // Skip check if widget is already confirmed visible
                  if (widgetIsVisible) {
                    return;
                  }
                  
                  const aipWidget = document.getElementById(`aave-governance-widget-${aipWidgetId}`);
                  if (aipWidget && aipWidget.parentNode) {
                    const computedStyle = window.getComputedStyle(aipWidget);
                    // Use screen width only - don't rely on user agent as tablets/desktops may have mobile-like user agents
                    const isMobile = window.innerWidth <= 1400;
                    const deviceType = isMobile ? 'MOBILE' : 'DESKTOP';
                    
                    // Only force visibility if actually hidden (don't repeatedly check visible widgets)
                    if (computedStyle.display === 'none' || computedStyle.visibility === 'hidden' || computedStyle.opacity === '0') {
                      console.log(`🔵 [${deviceType}] AIP widget hidden at ${delay}ms check ${index + 1}, forcing visibility`);
                      aipWidget.style.setProperty('display', 'block', 'important');
                      aipWidget.style.setProperty('visibility', 'visible', 'important');
                      aipWidget.style.setProperty('opacity', '1', 'important');
                      aipWidget.classList.remove('hidden', 'd-none', 'is-hidden');
                      // Force reflow
                      void aipWidget.offsetHeight;
                    } else {
                      // Widget is visible - mark as such and stop checking
                      widgetIsVisible = true;
                      console.log(`✅ [${deviceType}] AIP widget confirmed visible at ${delay}ms - stopping checks`);
                    }
                  }
                }, delay);
              });
            } else if (bestAIP && bestAIP.data && bestAIP.data.title && remainingSlots <= 0) {
              console.log(`🔵 [RENDER] Skipping AIP widget - maximum of ${maxWidgets} widgets already reached (${existingWidgets} existing)`);
            } else if (validAIPs.length > 0) {
              console.warn(`⚠️ [TOPIC] AIP data fetched but missing title or invalid`);
            }
          }); // End requestAnimationFrame
        })
        .catch(error => {
          console.error("❌ [TOPIC] Error processing AIP proposals:", error);
        });
    }
    
    // CRITICAL: Ensure all widgets are visible immediately after proposals are processed
    // This ensures widgets appear on page load and stay visible, not just when scrolling
    // Reduced delays for faster visibility: immediate, 100ms, 300ms
    ensureAIPWidgetsVisible(); // Immediate
    
    // Hide main loader once widgets start appearing
    // Use a small delay to ensure widgets are rendered before hiding loader
    setTimeout(() => {
      hideMainWidgetLoader();
    }, 100);
    
    // Ensure widgets are visible after a delay
    setTimeout(() => {
      ensureAIPWidgetsVisible();
      console.log("✅ [TOPIC] Ensured all widgets are visible after processing all proposals");
      // Final check to hide loader if still visible
      hideMainWidgetLoader();
    }, 500); // Give widgets time to render
    
    // Also ensure visibility after a short delay to catch any lazy-loaded widgets
    setTimeout(() => {
      ensureAIPWidgetsVisible();
      // Final hide of loader
      hideMainWidgetLoader();
    }, 300);
  }
  
  // Debounce widget setup to prevent duplicate widgets
  let widgetSetupTimeout = null;
  let isWidgetSetupRunning = false;
  // Track if widget setup has completed successfully for current topic (prevents re-initialization on scroll)
  let widgetSetupCompleted = false;
  let currentTopicId = null;
  
  // Track URLs currently being rendered to prevent race conditions
  const renderingUrls = new Set();
  // Track URLs currently being fetched to prevent duplicate fetches
  const fetchingUrls = new Set();
  
  // Main loader element to show while widgets are being fetched
  let mainWidgetLoader = null;
  
  /**
   * Show main loader at widget insertion point to prevent blinking
   */
  function showMainWidgetLoader() {
    // Only show loader on topic pages
    const isTopicPage = window.location.pathname.match(/^\/t\//);
    if (!isTopicPage) {
      return;
    }
    
    // Remove existing loader if any
    if (mainWidgetLoader && mainWidgetLoader.parentNode) {
      mainWidgetLoader.remove();
    }
    
    // Find insertion point (where widgets will appear)
    const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream, .topic-post-stream');
    const firstPost = document.querySelector('.topic-post, .post, [data-post-id], article[data-post-id]');
    
    if (!topicBody && !firstPost) {
      return; // Can't find insertion point
    }
    
    // Create loader element
    mainWidgetLoader = document.createElement('div');
    mainWidgetLoader.id = 'governance-widgets-main-loader';
    mainWidgetLoader.className = 'governance-widgets-main-loader';
    mainWidgetLoader.innerHTML = `
      <div class="loader-content">
        <div class="loading-spinner"></div>
        <span class="loader-text">Loading governance proposals...</span>
      </div>
    `;
    
    // Insert loader at widget insertion point
    if (firstPost && firstPost.parentNode) {
      firstPost.parentNode.insertBefore(mainWidgetLoader, firstPost);
    } else if (topicBody) {
      topicBody.insertBefore(mainWidgetLoader, topicBody.firstChild);
    } else {
      const mainContent = document.querySelector('main, [role="main"]');
      if (mainContent) {
        mainContent.insertBefore(mainWidgetLoader, mainContent.firstChild);
      }
    }
    
    console.log("🔵 [LOADER] Main widget loader shown");
  }
  
  /**
   * Hide main loader once widgets are rendered
   */
  function hideMainWidgetLoader() {
    if (mainWidgetLoader && mainWidgetLoader.parentNode) {
      // Fade out animation
      mainWidgetLoader.style.opacity = '0';
      mainWidgetLoader.style.transition = 'opacity 0.3s ease-out';
      
      setTimeout(() => {
        if (mainWidgetLoader && mainWidgetLoader.parentNode) {
          mainWidgetLoader.remove();
          console.log("🔵 [LOADER] Main widget loader hidden");
        }
        mainWidgetLoader = null;
      }, 300);
    } else {
      mainWidgetLoader = null;
    }
  }
  
  function debouncedSetupTopicWidget() {
    // Clear any pending setup
    if (widgetSetupTimeout) {
      clearTimeout(widgetSetupTimeout);
    }
    
    // CRITICAL: Check if we're on a different topic - reset completion flag if so
    const isTopicPage = window.location.pathname.match(/^\/t\//);
    if (isTopicPage) {
      const topicMatch = window.location.pathname.match(/^\/t\/[^\/]+\/(\d+)/);
      const topicId = topicMatch ? topicMatch[1] : window.location.pathname;
      if (currentTopicId !== topicId) {
        widgetSetupCompleted = false;
        currentTopicId = topicId;
        console.log(`🔵 [TOPIC] Topic changed - resetting widget setup flag. New topic: ${topicId}`);
      }
    } else {
      widgetSetupCompleted = false;
      currentTopicId = null;
    }
    
    // CRITICAL: If widget setup already completed and widgets exist, skip re-initialization
    if (widgetSetupCompleted) {
      const existingWidgets = document.querySelectorAll('.tally-status-widget-container');
      if (existingWidgets.length > 0) {
        console.log(`🔵 [TOPIC] Widget setup already completed for this topic - skipping re-initialization (${existingWidgets.length} widget(s) exist)`);
        return; // Skip re-initialization
      } else {
        // Widgets were removed somehow - allow re-initialization
        widgetSetupCompleted = false;
        console.log(`🔵 [TOPIC] Widget setup was completed but widgets are missing - allowing re-initialization`);
      }
    }
    
    // Use shorter debounce for faster initial load on all devices
    // Reduced from 100/500ms to 50ms for both mobile and desktop for faster widget appearance
    // This ensures widgets appear immediately on page load without requiring scroll
    const debounceDelay = 50;
    
    widgetSetupTimeout = setTimeout(() => {
      if (!isWidgetSetupRunning) {
        isWidgetSetupRunning = true;
        setupTopicWidget().finally(() => {
          isWidgetSetupRunning = false;
        });
      }
    }, debounceDelay);
  }
  
  // Watch for new posts being added to the topic and re-check for proposals
  function setupTopicWatcher() {
    // Only run on topic pages (not on homepage, categories, etc.)
    const isTopicPage = window.location.pathname.match(/^\/t\//);
    if (!isTopicPage) {
      console.log("🔍 [TOPIC] Not on a topic page - skipping topic watcher setup");
      return;
    }
    
    // Helper function to check if mutation is scroll-related (cloaking/uncloaking)
    function isScrollRelatedMutation(mutation) {
      // Check if it's an attribute change related to cloaking
      if (mutation.type === 'attributes') {
        const attrName = mutation.attributeName;
        if (attrName === 'class' || attrName === 'data-cloak' || attrName === 'style') {
          const target = mutation.target;
          // Check if target or its parent has cloaking-related classes/attributes
          if (target.classList?.contains('cloaked') || 
              target.hasAttribute?.('data-cloak') ||
              target.closest?.('.cloaked, [data-cloak]')) {
            return true;
          }
        }
        return false;
      }
      
      // Check added/removed nodes for cloaking-related changes
      for (const node of [...mutation.addedNodes, ...mutation.removedNodes]) {
        // Check if it's just a text node or whitespace (common in scroll changes)
        if (node.nodeType === Node.TEXT_NODE) {
          if (!node.textContent || node.textContent.trim() === '') {
            return true;
          }
          continue;
        }
        
        if (node.nodeType === Node.ELEMENT_NODE) {
          // Check if it's a cloaking-related element
          if (node.classList?.contains('cloaked') || 
              node.hasAttribute?.('data-cloak') ||
              node.classList?.contains('post-cloak') ||
              node.classList?.contains('viewport-tracker') ||
              node.querySelector?.('.cloaked, [data-cloak], .post-cloak')) {
            return true;
          }
        }
      }
      
      return false;
    }
    
    // Helper function to check if mutation is widget-related
    function isWidgetRelatedMutation(mutation) {
      for (const node of [...mutation.addedNodes, ...mutation.removedNodes]) {
        if (node.nodeType === Node.ELEMENT_NODE) {
          const isWidget = node.classList?.contains('tally-status-widget-container') ||
                         node.classList?.contains('governance-widgets-wrapper') ||
                         node.closest?.('.tally-status-widget-container') ||
                         node.closest?.('.governance-widgets-wrapper');
          if (isWidget) {
            return true;
          }
        }
      }
      return false;
    }
    
    // Watch for new posts being added
    const postObserver = new MutationObserver((mutations) => {
      // CRITICAL: Early return if widgets already exist and setup is completed
      if (widgetSetupCompleted) {
        const existingWidgets = document.querySelectorAll('.tally-status-widget-container');
        if (existingWidgets.length > 0) {
          // Check if ALL mutations are scroll-related or widget-related
          let allScrollOrWidgetRelated = true;
          for (const mutation of mutations) {
            if (!isScrollRelatedMutation(mutation) && !isWidgetRelatedMutation(mutation)) {
              // Check if it's actually a new post
              let hasNewPost = false;
              for (const node of mutation.addedNodes) {
                if (node.nodeType === Node.ELEMENT_NODE) {
                  const isPost = node.classList?.contains('post') || 
                                node.classList?.contains('topic-post') ||
                                node.querySelector?.('.post, .topic-post, [data-post-id]');
                  if (isPost && !isWidgetRelatedMutation(mutation)) {
                    hasNewPost = true;
                    break;
                  }
                }
              }
              if (hasNewPost) {
                allScrollOrWidgetRelated = false;
                break;
              }
            }
          }
          
          // Skip if all mutations are scroll/widget related
          if (allScrollOrWidgetRelated) {
            return; // Skip - no actual new content, just scroll-related changes
          }
        }
      }
      
      // Ignore mutations that are only widget-related or scroll-related to prevent flickering
      let hasNonWidgetChanges = false;
      for (const mutation of mutations) {
        // Skip scroll-related mutations
        if (isScrollRelatedMutation(mutation)) {
          continue;
        }
        
        // Skip widget-related mutations
        if (isWidgetRelatedMutation(mutation)) {
          continue;
        }
        
        // Check for actual new posts
        for (const node of mutation.addedNodes) {
          if (node.nodeType === Node.ELEMENT_NODE) {
            const isPost = node.classList?.contains('post') || 
                          node.classList?.contains('topic-post') ||
                          node.querySelector?.('.post, .topic-post, [data-post-id]');
            if (isPost) {
              hasNonWidgetChanges = true;
              break;
            }
          }
        }
        if (hasNonWidgetChanges) {
          break;
        }
      }
      
      // Only trigger widget setup if there are actual post changes, not widget changes or scroll-related changes
      // CRITICAL: Also check if widgets already exist - if they do, don't trigger setup to prevent reload
      if (hasNonWidgetChanges) {
        // Check if widgets already exist before triggering setup
        const existingWidgets = document.querySelectorAll('.tally-status-widget-container');
        if (existingWidgets.length > 0 && widgetSetupCompleted) {
          console.log(`🔵 [OBSERVER] New post detected but widgets already exist (${existingWidgets.length} widget(s)) - skipping setup to prevent reload`);
          return; // Skip setup if widgets already exist
        }
        // Use debounced version to prevent multiple rapid calls
        debouncedSetupTopicWidget();
      }
    });

    const postStream = document.querySelector('.post-stream, .topic-body, .posts-wrapper');
    if (postStream) {
      // Only watch childList changes, not attribute changes (reduces scroll-related triggers)
      postObserver.observe(postStream, { childList: true, subtree: true });
      console.log("✅ [TOPIC] Watching for new posts in topic (ignoring widget and scroll changes)");
    }
    
    // Also watch the entire topic content area for any content changes (catches lazy-loaded posts)
    // This is important because lazy-loaded posts might be added outside the post-stream container
    const topicContentObserver = new MutationObserver((mutations) => {
      // CRITICAL: Early return if widgets already exist and setup is completed
      if (widgetSetupCompleted) {
        const existingWidgets = document.querySelectorAll('.tally-status-widget-container');
        if (existingWidgets.length > 0) {
          // Check if ALL mutations are scroll-related or widget-related
          let allScrollOrWidgetRelated = true;
          for (const mutation of mutations) {
            if (!isScrollRelatedMutation(mutation) && !isWidgetRelatedMutation(mutation)) {
              // Check if it's actually a new post
              let hasNewPost = false;
              for (const node of mutation.addedNodes) {
                if (node.nodeType === Node.ELEMENT_NODE) {
                  const isPost = node.classList?.contains('post') || 
                                node.classList?.contains('topic-post') ||
                                node.querySelector?.('.post, .topic-post, [data-post-id]');
                  if (isPost && !isWidgetRelatedMutation(mutation)) {
                    hasNewPost = true;
                    break;
                  }
                }
              }
              if (hasNewPost) {
                allScrollOrWidgetRelated = false;
                break;
              }
            }
          }
          
          // Skip if all mutations are scroll/widget related
          if (allScrollOrWidgetRelated) {
            return; // Skip - no actual new content, just scroll-related changes
          }
        }
      }
      
      let hasNewContent = false;
      for (const mutation of mutations) {
        // Skip scroll-related mutations
        if (isScrollRelatedMutation(mutation)) {
          continue;
        }
        
        // Skip widget-related mutations
        if (isWidgetRelatedMutation(mutation)) {
          continue;
        }
        
        // Check for actual new posts
        for (const node of mutation.addedNodes) {
          if (node.nodeType === Node.ELEMENT_NODE) {
            const isPost = node.classList?.contains('post') || 
                          node.classList?.contains('topic-post') ||
                          node.querySelector?.('.post, .topic-post, [data-post-id]');
            if (isPost) {
              hasNewContent = true;
              break;
            }
          }
        }
        if (hasNewContent) {
          break;
        }
      }
      
      if (hasNewContent) {
        console.log("🔵 [TOPIC] New content detected in topic - re-scanning for AIP URLs");
        debouncedSetupTopicWidget();
      }
    });
    
    // Observe topic content containers for lazy-loaded content
    // Only watch childList changes, not attribute changes (reduces scroll-related triggers)
    const topicContentSelectors = ['.topic-body', '.post-stream', '.posts-wrapper', '.topic-post-stream', 'main'];
    topicContentSelectors.forEach(selector => {
      const element = document.querySelector(selector);
      if (element) {
        topicContentObserver.observe(element, { childList: true, subtree: true });
        console.log(`✅ [TOPIC] Watching ${selector} for lazy-loaded content (ignoring scroll changes)`);
      }
    });
    
    // CRITICAL: Also watch for oneboxes and preview containers being added
    // When oneboxes/preview containers are added, extract URLs from them
    const previewObserver = new MutationObserver((mutations) => {
      // CRITICAL: Skip if widget setup is already completed or running to prevent blinking
      if (widgetSetupCompleted || isWidgetSetupRunning) {
        const existingWidgets = document.querySelectorAll('.tally-status-widget-container');
        if (existingWidgets.length > 0) {
          // Widgets already exist - skip observer-triggered setup to prevent re-renders
          return;
        }
      }
      
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType === 1) { // Element node
            // Check if this is a onebox (before it's replaced)
            const onebox = node.classList?.contains('onebox') || node.classList?.contains('onebox-body')
              ? node
              : node.querySelector?.('.onebox, .onebox-body');
            
            if (onebox) {
              const oneboxText = onebox.textContent || onebox.innerHTML || '';
              const oneboxLinks = onebox.querySelectorAll('a[href*="snapshot.org"], a[href*="snapshot.box"], a[href*="testnet.snapshot.box"]');
              
              // Check text content
              SNAPSHOT_URL_REGEX.lastIndex = 0;
              const textMatches = Array.from(oneboxText.matchAll(SNAPSHOT_URL_REGEX));
              if (textMatches.length > 0 || oneboxLinks.length > 0) {
                // CRITICAL: Double-check before triggering setup
                if (!widgetSetupCompleted && !isWidgetSetupRunning) {
                  console.log(`✅ [TOPIC] Onebox added with ${textMatches.length} Snapshot URL(s) in text, ${oneboxLinks.length} in links`);
                  // Re-scan to add these URLs to proposals
                  setTimeout(() => {
                    debouncedSetupTopicWidget();
                  }, 200);
                }
              }
            }
            
            // Check if this is a preview container or contains one
            const preview = node.classList?.contains('tally-url-preview') || node.classList?.contains('tally-preview-content')
              ? node
              : node.querySelector?.('.tally-url-preview, [data-tally-preview-id]');
            
            if (preview) {
              // Check for URL in data attribute first (fastest method)
              const storedUrl = preview.getAttribute('data-tally-url');
              if (storedUrl && (storedUrl.includes('snapshot.org') || storedUrl.includes('snapshot.box'))) {
                // CRITICAL: Double-check before triggering setup
                if (!widgetSetupCompleted && !isWidgetSetupRunning) {
                  console.log(`✅ [TOPIC] Preview container added with Snapshot URL in data attribute: ${storedUrl}`);
                  // Re-scan immediately for faster detection
                  debouncedSetupTopicWidget();
                }
              } else {
                // Wait a short time for links to be added to preview container (reduced from 500ms to 100ms)
                setTimeout(() => {
                  // CRITICAL: Check again before triggering setup
                  if (!widgetSetupCompleted && !isWidgetSetupRunning) {
                    const previewLinks = preview.querySelectorAll('a[href*="snapshot.org"], a[href*="snapshot.box"], a[href*="testnet.snapshot.box"]');
                    if (previewLinks.length > 0) {
                      console.log(`✅ [TOPIC] Preview container added with ${previewLinks.length} Snapshot URL(s)`);
                      // Re-scan to add these URLs to proposals
                      debouncedSetupTopicWidget();
                    }
                  }
                }, 100);
              }
            }
          }
        });
      });
    });
    
    // Watch for oneboxes and preview containers being added to the topic
    topicContentSelectors.forEach(selector => {
      const element = document.querySelector(selector);
      if (element) {
        previewObserver.observe(element, { childList: true, subtree: true });
        console.log(`✅ [TOPIC] Watching ${selector} for oneboxes and preview containers`);
      }
    });
    
    // Detect mobile for faster initial load
    // Use screen width only - don't rely on user agent as tablets/desktops may have mobile-like user agents
    const isMobile = window.innerWidth <= 1400;
    
    // CRITICAL: Run immediate scan first (before debounce) to find proposals on page load
    // This ensures widgets appear immediately, not just when scrolling
    // Process immediately like tally widget - minimal delays
    console.log("🔍 [TOPIC] Running immediate scan for proposals on page load...");
    
    // Run immediately (like tally widget) - only once to prevent multiple simultaneous executions
    setupTopicWidget();
    
    // Only retry once after 100ms (like tally widget) to catch lazy-loaded content
    // Use debounced version to prevent concurrent executions
    setTimeout(() => {
      debouncedSetupTopicWidget();
      ensureAllWidgetsVisible();
    }, 100);
    
    // Then also set up debounced version for subsequent changes
    debouncedSetupTopicWidget();
    
    // CRITICAL: Also scan when user scrolls - this catches lazy-loaded posts
    // Use a throttled scroll handler to avoid too many scans
    // IMPORTANT: This ONLY adds new proposals found on scroll, it NEVER hides existing widgets
    // Widgets are detected on page load and remain visible regardless of scroll position
    let lastVisibilityCheck = 0;
    const VISIBILITY_CHECK_THROTTLE = 100; // Reduced to 100ms for more aggressive checking during scroll
    const handleScroll = () => {
      const now = Date.now();
      const shouldCheckVisibility = (now - lastVisibilityCheck) > VISIBILITY_CHECK_THROTTLE;
      
      // CRITICAL: Always force visibility immediately on scroll if widgets exist
      // Discourse's viewport tracker may hide widgets, so we must be aggressive
      const allWidgets = document.querySelectorAll('.tally-status-widget-container');
      if (allWidgets.length > 0) {
        // Use requestAnimationFrame to ensure we run after Discourse's scroll handlers
        requestAnimationFrame(() => {
          // Force visibility immediately without checking cache first
          // This prevents any delay that could cause visible blinking
          allWidgets.forEach(widget => {
            widget.style.setProperty('display', 'block', 'important');
            widget.style.setProperty('visibility', 'visible', 'important');
            widget.style.setProperty('opacity', '1', 'important');
            widget.classList.remove('hidden', 'd-none', 'is-hidden');
            // Update cache to reflect forced visibility
            markWidgetAsVisibleInCache(widget);
          });
          
          // Also force container visibility
          const container = document.querySelector('.governance-widgets-wrapper');
          if (container) {
            container.style.setProperty('display', 'flex', 'important');
            container.style.setProperty('visibility', 'visible', 'important');
            container.style.setProperty('opacity', '1', 'important');
          }
        });
      }
      
      // Only do expensive checks if throttled time has passed
      if (shouldCheckVisibility) {
        lastVisibilityCheck = now;
        // Run full visibility check as backup
        if (allWidgets.length > 0) {
          ensureAllWidgetsVisible();
        }
      }
      
      // CRITICAL: If widget has been shown for this topic, skip expensive scanning
      // This prevents widgets from appearing/disappearing on scroll after first visit
      if (hasWidgetBeenShown()) {
        // Skip expensive scanning if widget was already shown (data is cached)
        // Only scan for new proposals if we haven't found all yet
        const existingWidgets = document.querySelectorAll('.tally-status-widget-container');
        if (existingWidgets.length > 0) {
          // Widgets already exist and have been shown - skip scanning
          return; // Early return to skip scanning
        }
      }
      
      // CRITICAL: Ensure the container wrapper stays visible on ALL screen sizes during scroll
      // Only update if actually hidden (prevents blinking)
      const container = document.querySelector('.governance-widgets-wrapper');
      if (container) {
        const containerStyle = window.getComputedStyle(container);
        const containerIsHidden = containerStyle.display === 'none' || containerStyle.visibility === 'hidden' || containerStyle.opacity === '0';
        
        if (containerIsHidden) {
          const shouldInline = shouldShowWidgetInline();
          
          container.style.setProperty('display', 'flex', 'important');
          container.style.setProperty('visibility', 'visible', 'important');
          container.style.setProperty('opacity', '1', 'important');
          
          if (shouldInline) {
            // Mobile/Tablet: Use relative positioning (inline in topic) - respect CSS
            container.style.setProperty('position', 'relative', 'important');
            container.style.setProperty('left', 'auto', 'important');
            container.style.setProperty('right', 'auto', 'important');
            container.style.setProperty('top', 'auto', 'important');
            container.style.setProperty('width', '100%', 'important');
            container.style.setProperty('max-width', '100%', 'important');
          } else {
            // Desktop: Use fixed positioning (right side)
            container.style.setProperty('position', 'fixed', 'important');
            container.style.setProperty('z-index', '500', 'important');
            container.style.setProperty('right', '5px', 'important');
            container.style.setProperty('top', '180px', 'important');
            container.style.setProperty('left', 'auto', 'important');
            // CRITICAL: Keep width fixed at 320px to prevent width changes on scroll
            container.style.setProperty('width', '320px', 'important');
            container.style.setProperty('max-width', '320px', 'important');
            // Optimize for fixed positioning
            container.style.setProperty('will-change', 'transform', 'important');
            container.style.setProperty('backface-visibility', 'hidden', 'important');
            container.style.setProperty('transform', 'translateZ(0)', 'important');
          }
        }
      }
      
      // DISABLED: No scroll-based widget initialization
      // Widgets are only initialized on page load, not on scroll
      // This prevents loaders from appearing when scrolling and prevents auto-scrolling to widgets
      return; // Early return - skip all scroll-based widget scanning
    };
    
    // Enhanced scroll handler - wraps handleScroll with additional visibility checks
    const enhancedHandleScroll = () => {
      // Call original scroll handler
      handleScroll();
      
      // Force immediate visibility check on scroll for extra safety
      requestAnimationFrame(() => {
        const allWidgets = document.querySelectorAll('.tally-status-widget-container');
        allWidgets.forEach(widget => {
          widget.style.setProperty('display', 'block', 'important');
          widget.style.setProperty('visibility', 'visible', 'important');
          widget.style.setProperty('opacity', '1', 'important');
        });
      });
    };
    
    // Only add scroll listener for detecting new lazy-loaded proposals
    // This does NOT hide/show widgets based on scroll position
    // Visibility is enforced immediately on every scroll to prevent disappearing
    // Use enhanced scroll handler with continuous visibility checking
    window.addEventListener('scroll', enhancedHandleScroll, { passive: true });
    
    // CRITICAL: Also handle resize events to ensure widget stays visible when switching screen sizes
    // This prevents widget from disappearing when going from desktop to mobile or vice versa
    let resizeTimeout;
    const handleResize = () => {
      clearTimeout(resizeTimeout);
      resizeTimeout = setTimeout(() => {
        // Force visibility and correct positioning on resize
        ensureAllWidgetsVisible();
        
        // Also update container position for screen size changes
        const container = document.querySelector('.governance-widgets-wrapper');
        if (container) {
          updateContainerPosition(container);
        }
      }, 150);
    };
    window.addEventListener('resize', handleResize);
    
    // Listen for sidebar toggle events to update widget position
    // Watch for sidebar toggle buttons and sidebar state changes
    const sidebarToggleObserver = new MutationObserver(() => {
      const container = document.getElementById('governance-widgets-wrapper');
      if (container) {
        const shouldInline = shouldShowWidgetInline();
        const currentInline = container.style.position === 'relative' || 
                              window.getComputedStyle(container).position === 'relative';
        
        // Only update if position needs to change
        if (shouldInline !== currentInline) {
          console.log(`🔵 [SIDEBAR] Sidebar state changed, updating widget position (shouldInline: ${shouldInline})`);
          handleResize();
        }
      }
    });
    
    // Observe sidebar elements and body for class changes
    const sidebar = document.querySelector('.sidebar-wrapper, .d-sidebar, .sidebar, nav.sidebar, .navigation-container');
    if (sidebar) {
      sidebarToggleObserver.observe(sidebar, { attributes: true, attributeFilter: ['class', 'style'] });
    }
    sidebarToggleObserver.observe(document.body, { attributes: true, attributeFilter: ['class'] });
    
    // Also listen for click events on sidebar toggle buttons
    document.addEventListener('click', (e) => {
      const target = e.target;
      if (target.closest('.sidebar-toggle, .toggle-sidebar, [data-toggle-sidebar], button[aria-label*="sidebar" i], button[aria-label*="menu" i]')) {
        // Wait a bit for sidebar state to update
        setTimeout(() => {
          const container = document.getElementById('governance-widgets-wrapper');
          if (container) {
            console.log(`🔵 [SIDEBAR] Sidebar toggle detected, updating widget position`);
            handleResize();
          }
        }, 100);
      }
    });
    
    // CRITICAL: Periodically ensure widgets stay visible (prevents them from being hidden by scroll or other events)
    // Only check visibility periodically, and only if cache indicates widgets might be hidden
    // This prevents unnecessary getComputedStyle calls that cause flickering
    setInterval(() => {
      const allWidgets = document.querySelectorAll('.tally-status-widget-container');
      if (allWidgets.length === 0) {
        return; // No widgets to check
      }
      
      // Quick cache check - only call expensive ensureAllWidgetsVisible if cache indicates issue
      let needsCheck = false;
      for (const widget of allWidgets) {
        const cachedState = widgetVisibilityCache.get(widget);
        if (!cachedState || cachedState.isHidden) {
          needsCheck = true;
          break;
        }
      }
      
      // Only call expensive visibility check if cache indicates widgets might be hidden
      if (needsCheck) {
        ensureAllWidgetsVisible();
      }
    }, 3000); // Check every 3 seconds, but only if cache indicates widgets might be hidden
    
    // CRITICAL: Use MutationObserver to watch for any changes to widget visibility
    // This immediately restores visibility if Discourse or other code tries to hide widgets
    // Works on ALL screen sizes (desktop, tablet, mobile)
    // Made more aggressive to catch all visibility changes including from Discourse viewport tracker
    const widgetVisibilityObserver = new MutationObserver((mutations) => {
      // Process mutations immediately without delay
      mutations.forEach((mutation) => {
        const target = mutation.target;
        const shouldInline = shouldShowWidgetInline();
        
        // Check if target is a widget or container (check both attributes and childList)
        let widget = null;
        let container = null;
        
        if (target.classList?.contains('tally-status-widget-container')) {
          widget = target;
        } else if (target.closest?.('.tally-status-widget-container')) {
          widget = target.closest('.tally-status-widget-container');
        }
        
        if (target.classList?.contains('governance-widgets-wrapper') || target.id === 'governance-widgets-wrapper') {
          container = target;
        }
        
        // CRITICAL: Prevent Discourse from adding cloaking attributes to our widgets
        if (mutation.type === 'attributes' && widget) {
          // If Discourse tries to add data-cloak="true" or remove our anti-cloak attributes, stop it
          if (mutation.attributeName === 'data-cloak') {
            const cloakValue = widget.getAttribute('data-cloak');
            if (cloakValue === 'true') {
              // Discourse tried to enable cloaking - disable it immediately
              widget.setAttribute('data-cloak', 'false');
              widget.setAttribute('data-skip-cloak', 'true');
              widget.setAttribute('data-no-cloak', 'true');
              console.log(`🔵 [OBSERVER] Prevented Discourse cloaking on widget`);
            }
          }
        }
        
        // Also check for widgets in childList changes (Discourse might be moving/hiding them)
        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
          mutation.addedNodes.forEach(node => {
            if (node.nodeType === 1) { // Element node
              if (node.classList?.contains('tally-status-widget-container')) {
                widget = node;
                // Prevent cloaking on newly added widgets
                node.setAttribute('data-cloak', 'false');
                node.setAttribute('data-skip-cloak', 'true');
                node.setAttribute('data-no-cloak', 'true');
              } else {
                const foundWidget = node.querySelector?.('.tally-status-widget-container');
                if (foundWidget) {
                  widget = foundWidget;
                  foundWidget.setAttribute('data-cloak', 'false');
                  foundWidget.setAttribute('data-skip-cloak', 'true');
                  foundWidget.setAttribute('data-no-cloak', 'true');
                }
              }
            }
          });
        }
        
        // Force widget visibility immediately if found
        if (widget) {
          const computedStyle = window.getComputedStyle(widget);
          if (computedStyle.display === 'none' || 
              computedStyle.visibility === 'hidden' || 
              computedStyle.opacity === '0') {
            console.log(`🔵 [OBSERVER] Widget visibility changed to hidden, forcing visible immediately`);
            widget.style.setProperty('display', 'block', 'important');
            widget.style.setProperty('visibility', 'visible', 'important');
            widget.style.setProperty('opacity', '1', 'important');
            widget.classList.remove('hidden', 'd-none', 'is-hidden', 'cloaked');
            // CRITICAL: Ensure cloaking is disabled
            widget.setAttribute('data-cloak', 'false');
            widget.setAttribute('data-skip-cloak', 'true');
            widget.setAttribute('data-no-cloak', 'true');
            // CRITICAL: Update cache immediately to prevent further checks
            markWidgetAsVisibleInCache(widget);
          } else {
            // Even if visible, ensure it stays visible by updating cache
            markWidgetAsVisibleInCache(widget);
          }
        }
        
        // Also check for attribute changes on widgets
        if ((mutation.type === 'attributes' && 
            (mutation.attributeName === 'style' || mutation.attributeName === 'class' || mutation.attributeName === 'data-cloak')) && widget) {
          const computedStyle = window.getComputedStyle(widget);
          if (computedStyle.display === 'none' || 
              computedStyle.visibility === 'hidden' || 
              computedStyle.opacity === '0') {
            console.log(`🔵 [OBSERVER] Widget visibility changed to hidden, forcing visible immediately`);
            widget.style.setProperty('display', 'block', 'important');
            widget.style.setProperty('visibility', 'visible', 'important');
            widget.style.setProperty('opacity', '1', 'important');
            widget.classList.remove('hidden', 'd-none', 'is-hidden', 'cloaked');
            widget.setAttribute('data-cloak', 'false');
            widget.setAttribute('data-skip-cloak', 'true');
            widget.setAttribute('data-no-cloak', 'true');
            markWidgetAsVisibleInCache(widget);
          }
        }
        
        // Also watch for container visibility changes and width changes
        if (container || (target.classList?.contains('governance-widgets-wrapper') || target.id === 'governance-widgets-wrapper')) {
          const containerEl = container || target;
          const computedStyle = window.getComputedStyle(containerEl);
          if (computedStyle.display === 'none' || 
              computedStyle.visibility === 'hidden' || 
              computedStyle.opacity === '0') {
            console.log(`🔵 [OBSERVER] Container visibility changed to hidden, forcing visible immediately`);
            containerEl.style.setProperty('display', 'flex', 'important');
            containerEl.style.setProperty('visibility', 'visible', 'important');
            containerEl.style.setProperty('opacity', '1', 'important');
            
            // Re-apply correct positioning based on screen size and sidebar state
            // Reuse shouldInline from outer scope (already declared at line 9031)
            if (shouldInline) {
              containerEl.style.setProperty('position', 'relative', 'important');
              containerEl.style.setProperty('width', '100%', 'important');
              containerEl.style.setProperty('max-width', '100%', 'important');
            } else {
              containerEl.style.setProperty('position', 'fixed', 'important');
              containerEl.style.setProperty('z-index', '500', 'important');
              // CRITICAL: Keep width fixed at 320px on desktop to prevent width changes on scroll
              containerEl.style.setProperty('width', '320px', 'important');
              containerEl.style.setProperty('max-width', '320px', 'important');
            }
          }
          
          // CRITICAL: Prevent width changes on desktop (keep fixed at 320px)
          if (!shouldInline) {
            const currentWidth = computedStyle.width;
            // If width is not 320px, restore it (prevents width flickering on scroll)
            if (currentWidth && currentWidth !== '320px' && !currentWidth.includes('320')) {
              containerEl.style.setProperty('width', '320px', 'important');
              containerEl.style.setProperty('max-width', '320px', 'important');
            }
          }
        }
      });
    });
    
    // Observe all existing widgets, container, and any new ones that get added
    const observeWidgets = () => {
      // Observe all widgets with both attributes and childList to catch all changes
      const allWidgets = document.querySelectorAll('.tally-status-widget-container');
      allWidgets.forEach(widget => {
        widgetVisibilityObserver.observe(widget, {
          attributes: true,
          attributeFilter: ['style', 'class', 'data-cloak', 'data-cloaked'], // Watch for cloaking attributes
          childList: true,
          subtree: false
        });
        
        // CRITICAL: Ensure cloaking is disabled and exclude from viewport tracking
        widget.setAttribute('data-cloak', 'false');
        widget.setAttribute('data-skip-cloak', 'true');
        widget.setAttribute('data-no-cloak', 'true');
        widget.setAttribute('data-viewport', 'false');
        widget.setAttribute('data-exclude-viewport', 'true');
        widget.setAttribute('data-no-viewport-track', 'true');
        widget.classList.add('no-viewport-track');
      });
      
      // Also observe the container wrapper with childList to catch widget additions/removals
      const container = document.querySelector('.governance-widgets-wrapper');
      if (container) {
        widgetVisibilityObserver.observe(container, {
          attributes: true,
          attributeFilter: ['style', 'class', 'data-cloak', 'data-cloaked'], // Watch for cloaking attributes
          childList: true,
          subtree: true // Watch for widgets being added/removed inside
        });
        
        // CRITICAL: Ensure cloaking is disabled and exclude from viewport tracking
        container.setAttribute('data-cloak', 'false');
        container.setAttribute('data-skip-cloak', 'true');
        container.setAttribute('data-no-cloak', 'true');
        container.setAttribute('data-viewport', 'false');
        container.setAttribute('data-exclude-viewport', 'true');
        container.setAttribute('data-no-viewport-track', 'true');
        container.classList.add('no-viewport-track');
      }
      
      // Also observe the topic body to catch widgets being moved around
      const topicBody = document.querySelector('.topic-body, .posts-wrapper, .post-stream');
      if (topicBody) {
        widgetVisibilityObserver.observe(topicBody, {
          childList: true,
          subtree: true // Watch for widgets being added/removed/moved
        });
      }
    };
    
    // Initial observation
    observeWidgets();
    
    // Also observe the document for new widgets being added
    const widgetContainerObserver = new MutationObserver(() => {
      observeWidgets();
    });
    
    // CRITICAL: Continuous visibility check ALWAYS (not just during scroll)
    // This ensures widgets stay visible even if Discourse's viewport tracker tries to hide them
    // Run continuously using requestAnimationFrame to catch any hiding immediately
    let lastVisibilityCheckTime = 0;
    const VISIBILITY_CHECK_INTERVAL = 16; // Check every ~16ms (60fps)
    
    const continuousVisibilityCheck = () => {
      const now = performance.now();
      
      // Only check if enough time has passed (throttle to ~60fps)
      if (now - lastVisibilityCheckTime < VISIBILITY_CHECK_INTERVAL) {
        requestAnimationFrame(continuousVisibilityCheck);
        return;
      }
      
      lastVisibilityCheckTime = now;
      
      // CRITICAL: Force visibility on ALL widgets EVERY frame
      // Don't check if hidden - just force visibility always to prevent any flicker
      const allWidgets = document.querySelectorAll('.tally-status-widget-container');
      if (allWidgets.length > 0) {
        allWidgets.forEach(widget => {
          const computedStyle = window.getComputedStyle(widget);
          const wasHidden = computedStyle.display === 'none' || 
                           computedStyle.visibility === 'hidden' || 
                           computedStyle.opacity === '0';
          
          // Force visibility immediately without checking - prevents any delay
          widget.style.setProperty('display', 'block', 'important');
          widget.style.setProperty('visibility', 'visible', 'important');
          widget.style.setProperty('opacity', '1', 'important');
          widget.classList.remove('hidden', 'd-none', 'is-hidden', 'cloaked');
          
          // Ensure all exclusion attributes are set
          widget.setAttribute('data-cloak', 'false');
          widget.setAttribute('data-skip-cloak', 'true');
          widget.setAttribute('data-no-cloak', 'true');
          widget.setAttribute('data-viewport', 'false');
          widget.setAttribute('data-exclude-viewport', 'true');
          widget.setAttribute('data-no-viewport-track', 'true');
          widget.classList.add('no-viewport-track');
          
          markWidgetAsVisibleInCache(widget);
          
          // Log if we had to restore visibility
          if (wasHidden) {
            console.log(`🔵 [CONTINUOUS] Widget was hidden, forced visible - display: ${computedStyle.display}, visibility: ${computedStyle.visibility}`);
          }
        });
      }
      
      // Also force container visibility every frame
      const container = document.querySelector('.governance-widgets-wrapper');
      if (container) {
        const containerStyle = window.getComputedStyle(container);
        const containerWasHidden = containerStyle.display === 'none' || 
                                   containerStyle.visibility === 'hidden' || 
                                   containerStyle.opacity === '0';
        
        container.style.setProperty('display', 'flex', 'important');
        container.style.setProperty('visibility', 'visible', 'important');
        container.style.setProperty('opacity', '1', 'important');
        container.classList.remove('cloaked', 'hidden');
        
        // Ensure all exclusion attributes are set
        container.setAttribute('data-cloak', 'false');
        container.setAttribute('data-skip-cloak', 'true');
        container.setAttribute('data-no-cloak', 'true');
        container.setAttribute('data-viewport', 'false');
        container.setAttribute('data-exclude-viewport', 'true');
        container.setAttribute('data-no-viewport-track', 'true');
        container.classList.add('no-viewport-track');
        
        if (containerWasHidden) {
          console.log(`🔵 [CONTINUOUS] Container was hidden, forced visible`);
        }
      }
      
      // Continue checking ALWAYS (not just during scroll)
      requestAnimationFrame(continuousVisibilityCheck);
    };
    
    // Start continuous visibility check immediately
    requestAnimationFrame(continuousVisibilityCheck);
    
    const topicBody = document.querySelector('.topic-body, .post-stream, .topic-post');
    if (topicBody) {
      widgetContainerObserver.observe(topicBody, {
        childList: true,
        subtree: true
      });
    }
    
    // Also observe document body for container changes
    if (document.body) {
      widgetContainerObserver.observe(document.body, {
        childList: true,
        subtree: true
      });
    }
    
    // CRITICAL: Call immediately on page load for both mobile and desktop
    // This ensures widgets appear immediately without requiring scroll
    debouncedSetupTopicWidget();
    ensureAllWidgetsVisible();
    
    // On mobile, use shorter delays for faster widget display
    // On desktop, use longer delays to catch late-loading content
    if (isMobile) {
      // Reduced delays for faster mobile display - show loading immediately, then check quickly
      setTimeout(() => {
        debouncedSetupTopicWidget();
        ensureAllWidgetsVisible();
      }, 0); // Immediate check
      setTimeout(() => {
        debouncedSetupTopicWidget();
        ensureAllWidgetsVisible();
      }, 200); // Quick follow-up
      
      // On mobile, ensure all widgets are visible after initial setup
      setTimeout(() => {
        ensureAllWidgetsVisible();
      }, 300);
      
      // Final check for any lazy-loaded content (reduced from 1000ms)
      setTimeout(() => {
        ensureAllWidgetsVisible();
      }, 500);
    } else {
      // Desktop: also call immediately (already called above, but keep for consistency)
      setTimeout(() => {
        debouncedSetupTopicWidget();
        ensureAllWidgetsVisible();
      }, 0); // Immediate check for desktop too
      setTimeout(() => {
        debouncedSetupTopicWidget();
        ensureAllWidgetsVisible();
      }, 500);
      setTimeout(() => {
        debouncedSetupTopicWidget();
        ensureAllWidgetsVisible();
      }, 1500);
      
      // Desktop: also ensure widgets are visible after delays
      setTimeout(() => {
        ensureAllWidgetsVisible();
      }, 2000);
    }
    
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
      
      // If no Tally links found at all, hide Snapshot widgets (AIP widgets remain visible)
      if (allTallyLinks.length === 0) {
        console.log("🔵 [SCROLL] No Snapshot links found on page - hiding Snapshot widgets (AIP widgets stay visible)");
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
        // No visible Snapshot proposal link found - hide Snapshot widgets (AIP widgets remain visible)
        console.log("🔵 [SCROLL] No visible Snapshot proposal link found - hiding Snapshot widgets (AIP widgets stay visible)");
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
        // CRITICAL: Always ensure AIP widgets are visible before doing any scroll tracking
        // This prevents them from being hidden by scroll events
        ensureAIPWidgetsVisible();
        
        // First, try to get current post number from Discourse timeline
        const postInfo = getCurrentPostNumber();
        
        let proposalUrl = null;
        
        if (postInfo) {
          // Use the post number from timeline to get the correct proposal
          proposalUrl = getProposalLinkFromPostNumber(postInfo.current);
          console.log("🔵 [SCROLL] IntersectionObserver - Post", postInfo.current, "/", postInfo.total);
          
          // If no Snapshot proposal in this post, hide Snapshot widgets (AIP widgets remain visible)
          if (!proposalUrl) {
            console.log("🔵 [SCROLL] Post", postInfo.current, "/", postInfo.total, "has no Snapshot proposal - hiding Snapshot widgets (AIP widgets stay visible)");
            hideWidgetIfNoProposal();
            // Ensure AIP widgets remain visible after hiding Snapshot widgets
            ensureAIPWidgetsVisible();
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
            // No Snapshot link in this post - hide Snapshot widgets (AIP widgets remain visible)
            hideWidgetIfNoProposal();
            // Ensure AIP widgets remain visible after hiding Snapshot widgets
            ensureAIPWidgetsVisible();
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
                  // Invalid data - hide widget (but keep AIP widgets visible)
                  hideWidgetIfNoProposal();
                  ensureAIPWidgetsVisible();
                }
              })
              .catch(error => {
                console.error("❌ [SCROLL] Error fetching proposal data:", error);
                hideWidgetIfNoProposal();
                ensureAIPWidgetsVisible();
              });
          } else {
            // Could not extract proposal info - hide widget (but keep AIP widgets visible)
            hideWidgetIfNoProposal();
            ensureAIPWidgetsVisible();
          }
        } else {
          // No Snapshot proposal URL found - hide Snapshot widgets (AIP widgets remain visible)
          console.log("🔵 [SCROLL] No Snapshot proposal URL found - hiding Snapshot widgets (AIP widgets stay visible)");
          hideWidgetIfNoProposal();
          // Ensure AIP widgets remain visible after hiding Snapshot widgets
          ensureAIPWidgetsVisible();
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
      // Force refresh by bypassing cache - fresh data will automatically update localStorage cache
      const freshData = await fetchProposalData(proposalId, url, proposalInfo.govId, proposalInfo.urlProposalNumber, true);
      
      if (freshData && freshData.title && freshData.title !== "Snapshot Proposal") {
        // Update widget with fresh data (status, votes, days left)
        // Note: freshData is automatically saved to localStorage cache by fetchProposalDataByType
        console.log("🔄 [REFRESH] Updating widget with fresh data from Snapshot (cache updated)");
        renderStatusWidget(freshData, url, widgetId, proposalInfo);
      }
    }, 2 * 60 * 1000); // Refresh every 2 minutes
    
    console.log("✅ [REFRESH] Auto-refresh set up for widget:", widgetId, "(every 2 minutes)");
  }

  // Handle posts (saved content) - Show simple link preview (not full widget)
  api.decorateCookedElement((element) => {
    // Use both textContent and innerHTML to catch URLs in all formats
    const text = element.textContent || element.innerText || '';
    const html = element.innerHTML || '';
    const combinedText = text + ' ' + html;
    const matches = Array.from(combinedText.matchAll(SNAPSHOT_URL_REGEX));
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
      previewContainer.setAttribute("data-tally-url", url); // Store URL for topic scanner
      
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
                console.log("🔵 [COMPOSER] Proposal data:", { title: data.title, description: data.description ? data.description.substring(0, 100) : 'NO DESCRIPTION', type: data.type });
                // Render widget only (don't modify reply box textarea)
                renderProposalWidget(widgetContainer, data, url);
                console.log("✅ [COMPOSER] Widget rendered successfully");
              } else {
                console.warn("⚠️ [COMPOSER] Invalid proposal data:", data);
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

  // Initialize global composer detection immediately
  setupGlobalComposerDetection();

  // Initialize topic widget immediately (shows first proposal found, no scroll tracking)
  // Only run on topic pages to prevent widgets from appearing on wrong pages
  // Use immediate initialization like tally widget - no setTimeout delays
  function startWidgetInitialization() {
    const isTopicPage = window.location.pathname.match(/^\/t\//);
    if (isTopicPage) {
      setupTopicWatcher();
    } else {
      console.log("🔍 [TOPIC] Not on a topic page - skipping topic widget initialization");
    }
    
    // Watch for widgets being added to DOM and immediately force visibility (works on all devices)
    // CRITICAL: Only process widgets on topic pages - remove widgets on non-topic pages
    // Also watch for widgets being REMOVED and prevent removal if on topic page
    let isRestoring = false; // Flag to prevent infinite loops
    let lastRestoreTime = 0; // Track last restore time for debouncing
    const RESTORE_DEBOUNCE_MS = 500; // Minimum time between restorations
    const restoredNodes = new WeakSet(); // Track nodes we've restored to prevent loops
    
    const widgetObserver = new MutationObserver((mutations) => {
      const isCurrentTopicPage = window.location.pathname.match(/^\/t\//);
      
      // If not on topic page, remove any widgets that get added
      if (!isCurrentTopicPage) {
        mutations.forEach((mutation) => {
          mutation.addedNodes.forEach((node) => {
            if (node.nodeType === Node.ELEMENT_NODE) {
              const widgets = node.classList?.contains('tally-status-widget-container') 
                ? [node] 
                : node.querySelectorAll?.('.tally-status-widget-container') || [];
              widgets.forEach((widget) => widget.remove());
              // Also check if node itself is the container
              if (node.id === 'governance-widgets-wrapper') {
                node.remove();
              }
            }
          });
        });
        // Also clean up any existing widgets and container
        const allWidgets = document.querySelectorAll('.tally-status-widget-container');
        allWidgets.forEach(widget => widget.remove());
        const container = document.getElementById('governance-widgets-wrapper');
        if (container) {
          container.remove();
        }
        return;
      }
      
      // On topic page: watch for widgets being removed and prevent it
      // CRITICAL: Prevent infinite loops by checking if we're already restoring
      if (isRestoring) {
        return; // Skip processing if we're currently restoring
      }
      
      mutations.forEach((mutation) => {
        // CRITICAL: Watch for widgets being removed from DOM and prevent it if on topic page
        if (mutation.type === 'childList' && mutation.removedNodes.length > 0) {
          mutation.removedNodes.forEach((node) => {
            if (node.nodeType === Node.ELEMENT_NODE) {
              // Check if this is a widget or container
              const isWidget = node.classList?.contains('tally-status-widget-container');
              const isContainer = node.classList?.contains('governance-widgets-wrapper');
              
              if (isWidget || isContainer) {
                // Check if node is already in DOM (might have been moved, not removed)
                if (node.parentNode) {
                  return; // Node is still in DOM, skip
                }
                
                // Check if we've already restored this node recently
                if (restoredNodes.has(node)) {
                  const now = Date.now();
                  if (now - lastRestoreTime < RESTORE_DEBOUNCE_MS) {
                    return; // Too soon since last restore, skip
                  }
                }
                
                // Debounce: only restore if enough time has passed
                const now = Date.now();
                if (now - lastRestoreTime < RESTORE_DEBOUNCE_MS) {
                  return; // Debounce restorations
                }
                
                // Check if this is a legitimate removal (e.g., during resize/position update)
                // If the node is being moved to a different parent, that's legitimate
                const shouldInline = shouldShowWidgetInline();
                const wasInContainer = node.parentNode?.id === 'governance-widgets-wrapper';
                const shouldBeInContainer = !shouldInline && isWidget;
                
                // If widget should be moved between container and topic body, allow it
                if (isWidget && wasInContainer !== shouldBeInContainer) {
                  return; // This is a legitimate move, don't restore
                }
                
                console.warn(`⚠️ [OBSERVER] Widget/container was removed from DOM! Attempting to restore...`);
                isRestoring = true;
                lastRestoreTime = now;
                restoredNodes.add(node);
                
                // Temporarily disconnect observer to prevent recursive calls
                widgetObserver.disconnect();
                
                try {
                  // Try to restore the widget - find appropriate location
                  let restoreTarget = null;
                  let restoreBefore = null;
                  
                  if (isWidget) {
                    // For widgets, try to restore before first post or in container
                    const firstPost = document.querySelector('.topic-post, .post, [data-post-id], article[data-post-id]');
                    const container = document.getElementById('governance-widgets-wrapper');
                    
                    if (shouldInline) {
                      // Should be inline - restore before first post
                      if (firstPost && firstPost.parentNode) {
                        restoreTarget = firstPost.parentNode;
                        restoreBefore = firstPost;
                      }
                    } else if (container) {
                      // Should be in container
                      restoreTarget = container;
                    }
                  } else if (isContainer) {
                    // For container, restore to body
                    restoreTarget = document.body;
                  }
                  
                  if (restoreTarget) {
                    if (restoreBefore) {
                      restoreTarget.insertBefore(node, restoreBefore);
                    } else {
                      restoreTarget.appendChild(node);
                    }
                    
                    console.log(`✅ [OBSERVER] Restored widget/container to DOM`);
                    
                    // Force visibility immediately
                    if (isWidget) {
                      node.style.setProperty('display', 'block', 'important');
                      node.style.setProperty('visibility', 'visible', 'important');
                      node.style.setProperty('opacity', '1', 'important');
                    } else if (isContainer) {
                      node.style.setProperty('display', 'flex', 'important');
                      node.style.setProperty('visibility', 'visible', 'important');
                      node.style.setProperty('opacity', '1', 'important');
                    }
                    }
                  } catch (e) {
                    console.error(`❌ [OBSERVER] Failed to restore widget:`, e);
                } finally {
                  // Reconnect observer after a short delay
                  setTimeout(() => {
                    isRestoring = false;
                    // Re-observe the document with same config as initial setup
                    widgetObserver.observe(document.body, {
                      childList: true,
                      subtree: true
                    });
                  }, 100);
                }
              }
            }
          });
        }
      });
      
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType === Node.ELEMENT_NODE) {
            // Check if the added node is a widget or contains widgets
            const widgets = node.classList?.contains('tally-status-widget-container') 
              ? [node] 
              : node.querySelectorAll?.('.tally-status-widget-container') || [];
            
            widgets.forEach((widget) => {
              if (widget && widget.parentNode) {
                // Check if this is an AIP widget
                const widgetType = widget.getAttribute('data-proposal-type');
                const widgetTypeAttr = widget.getAttribute('data-widget-type');
                const hasAIP = widget.querySelector('.governance-stage[data-stage="aip"]') !== null;
                const url = widget.getAttribute('data-tally-url') || '';
                const isAIPUrl = url.includes('vote.onaave.com') || url.includes('app.aave.com/governance') || url.includes('governance.aave.com/aip/');
                const isAIPWidget = widgetType === 'aip' || widgetTypeAttr === 'aip' || hasAIP || isAIPUrl;
                
                if (isAIPWidget) {
                  // Force AIP widgets to be visible immediately when added to DOM
                  const computedStyle = window.getComputedStyle(widget);
                  if (computedStyle.display === 'none' || computedStyle.visibility === 'hidden' || computedStyle.opacity === '0') {
                    console.log(`✅ [AIP] AIP widget detected in DOM but hidden, forcing visibility immediately`);
                    widget.style.setProperty('display', 'block', 'important');
                    widget.style.setProperty('visibility', 'visible', 'important');
                    widget.style.setProperty('opacity', '1', 'important');
                    widget.classList.remove('hidden', 'd-none', 'is-hidden');
                    
                    // Force reflow
                    void widget.offsetHeight;
                  }
                }
              }
            });
          }
        });
      });
      // Also check all existing AIP widgets periodically (handles cases where they get hidden after being visible)
      ensureAIPWidgetsVisible();
    });
    
    // Observe the document body for widget additions
    widgetObserver.observe(document.body, {
      childList: true,
      subtree: true
    });
    
    // Periodic check to ensure AIP widgets stay visible (prevents them from being hidden by other code)
    // CRITICAL: AIP widgets are topic-level and should ALWAYS be visible once found
    // Run more frequently to catch any hiding attempts immediately
    const aipVisibilityInterval = setInterval(() => {
      ensureAIPWidgetsVisible();
    }, 300); // Check every 300ms to keep AIP widgets visible (very aggressive)
    
    // Store interval ID so it can be cleared if needed (though it should run for the page lifetime)
    window._aipVisibilityInterval = aipVisibilityInterval;
    
    // Also watch for AIP widgets being hidden via MutationObserver
    // This catches when CSS classes or styles are changed to hide widgets
    const aipWidgetObserver = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === 'attributes' && (mutation.attributeName === 'style' || mutation.attributeName === 'class')) {
          const target = mutation.target;
          // Check if this is an AIP widget
          if (target.classList && target.classList.contains('tally-status-widget-container')) {
            const widgetType = target.getAttribute('data-proposal-type');
            const widgetTypeAttr = target.getAttribute('data-widget-type');
            const url = target.getAttribute('data-tally-url') || '';
            const isAIPUrl = url.includes('vote.onaave.com') || url.includes('app.aave.com/governance') || url.includes('governance.aave.com/aip/');
            
            if (widgetType === 'aip' || widgetTypeAttr === 'aip' || isAIPUrl) {
              // AIP widget was modified - check if it's hidden and restore visibility
              const computedStyle = window.getComputedStyle(target);
              if (computedStyle.display === 'none' || computedStyle.visibility === 'hidden' || computedStyle.opacity === '0') {
                console.warn(`⚠️ [AIP] AIP widget was hidden (${mutation.attributeName} changed), restoring visibility immediately`);
                ensureAIPWidgetsVisible();
              }
            }
          }
        }
      });
    });
    
    // Observe all AIP widgets for style/class changes
    const observeAIPWidgets = () => {
      const aipWidgets = document.querySelectorAll('.tally-status-widget-container[data-proposal-type="aip"], .tally-status-widget-container[data-widget-type="aip"]');
      aipWidgets.forEach(widget => {
        aipWidgetObserver.observe(widget, {
          attributes: true,
          attributeFilter: ['style', 'class'],
          subtree: false
        });
      });
    };
    
    // Initial observation
    observeAIPWidgets();
    
    // Re-observe periodically to catch newly added AIP widgets
    setInterval(observeAIPWidgets, 1000);
    
    console.log("✅ [AIP] Widget visibility observer, periodic check, and MutationObserver set up");
  }
  
  // Initialize immediately when DOM is ready (like tally widget)
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", startWidgetInitialization);
  } else {
    startWidgetInitialization();
  }

  // Re-initialize topic widget on page changes
  api.onPageChange(() => {
    // Reset current proposal so we can detect the first one again
    currentVisibleProposal = null;
    
    // CRITICAL: Clean up widgets if we're not on a topic page
    const isTopicPage = window.location.pathname.match(/^\/t\//);
    if (!isTopicPage) {
      console.log("🔍 [TOPIC] Page changed to non-topic page - cleaning up widgets");
      // Remove all widgets and container
      const allWidgets = document.querySelectorAll('.tally-status-widget-container');
      allWidgets.forEach(widget => widget.remove());
      const container = document.getElementById('governance-widgets-wrapper');
      if (container) {
        container.remove();
      }
      // Reset topic tracking
      widgetSetupCompleted = false;
      currentTopicId = null;
      return;
    }
    
    // CRITICAL: Check if we're navigating to a different topic
    // If same topic, preserve widgets to prevent blinking
    const topicMatch = window.location.pathname.match(/^\/t\/[^\/]+\/(\d+)/);
    const newTopicId = topicMatch ? topicMatch[1] : window.location.pathname;
    
    if (currentTopicId && currentTopicId === newTopicId) {
      console.log(`🔵 [TOPIC] Same topic (${newTopicId}) - preserving widgets to prevent blinking`);
      // Same topic - just ensure watcher is set up, but don't re-initialize widgets
      setupTopicWatcher();
      setupGlobalComposerDetection();
      return;
    }
    
    // Different topic - reset flags to allow fresh widget setup
    if (currentTopicId !== newTopicId) {
      console.log(`🔵 [TOPIC] Topic changed from ${currentTopicId} to ${newTopicId} - will re-initialize widgets`);
      widgetSetupCompleted = false;
      currentTopicId = newTopicId;
    }
    
    // Initialize immediately - no setTimeout delay
    setupTopicWatcher();
    setupGlobalComposerDetection();
  });
});



