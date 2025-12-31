// URL parsing utilities for Snapshot and AIP proposals

/**
 * Extract Snapshot proposal info from URL
 * Format: https://snapshot.org/#/{space}/{proposal-id}
 * Example: https://snapshot.org/#/aave.eth/0x1234...
 * Testnet format: https://testnet.snapshot.box/#/s-tn:{space}/{proposal-id}
 */
export function extractSnapshotProposalInfo(url) {
  console.log("🔍 Extracting Snapshot proposal info from URL:", url);
  
  try {
    // Check if it's a testnet URL
    const isTestnet = url.includes('testnet.snapshot.box');
    
    // Match pattern for testnet: testnet.snapshot.box/#/s-tn:{space}/proposal/{proposal-id}
    if (isTestnet) {
      const testnetProposalMatch = url.match(/testnet\.snapshot\.box\/#\/([^\/]+)\/proposal\/([a-zA-Z0-9]+)/i);
      if (testnetProposalMatch) {
        let space = testnetProposalMatch[1];
        const proposalId = testnetProposalMatch[2];
        // Handle s-tn: prefix - keep it for API calls
        console.log("✅ Extracted Snapshot testnet format:", { space, proposalId });
        return { space, proposalId, type: 'snapshot', isTestnet: true };
      }
      
      // Match pattern: testnet.snapshot.box/#/s-tn:{space}/{proposal-id} (without /proposal/)
      const testnetDirectMatch = url.match(/testnet\.snapshot\.box\/#\/([^\/]+)\/([a-zA-Z0-9]+)/i);
      if (testnetDirectMatch) {
        let space = testnetDirectMatch[1];
        const proposalId = testnetDirectMatch[2];
        // Skip if proposalId is "proposal"
        if (proposalId.toLowerCase() !== 'proposal') {
          console.log("✅ Extracted Snapshot testnet format (direct):", { space, proposalId });
          return { space, proposalId, type: 'snapshot', isTestnet: true };
        }
      }
    }
    
    // Match pattern: snapshot.org/#/{space}/proposal/{proposal-id}
    const proposalMatch = url.match(/snapshot\.org\/#\/([^\/]+)\/proposal\/([a-zA-Z0-9]+)/i);
    if (proposalMatch) {
      const space = proposalMatch[1];
      const proposalId = proposalMatch[2];
      console.log("✅ Extracted Snapshot format:", { space, proposalId });
      return { space, proposalId, type: 'snapshot', isTestnet: false };
    }
    
    // Match pattern: snapshot.org/#/{space}/{proposal-id} (without /proposal/)
    const directMatch = url.match(/snapshot\.org\/#\/([^\/]+)\/([a-zA-Z0-9]+)/i);
    if (directMatch) {
      const space = directMatch[1];
      const proposalId = directMatch[2];
      // Skip if proposalId is "proposal"
      if (proposalId.toLowerCase() !== 'proposal') {
        console.log("✅ Extracted Snapshot format (direct):", { space, proposalId });
        return { space, proposalId, type: 'snapshot', isTestnet: false };
      }
    }
    
    console.warn("❌ Could not extract Snapshot proposal info from URL:", url);
    return null;
  } catch (e) {
    console.warn("❌ Error extracting Snapshot proposal info:", e);
    return null;
  }
}

/**
 * Extract AIP proposal ID from URL (robust approach)
 * Supports:
 * - app.aave.com/governance/v3/proposal/?proposalId=420
 * - app.aave.com/governance/?proposalId=420
 * - vote.onaave.com/proposal/?proposalId=420
 * - governance.aave.com/t/{slug}/{id}
 * - app.aave.com/governance/{id}
 */
export function extractAIPProposalInfo(url) {
  console.log("🔍 Extracting AIP proposal ID from URL:", url);
  
  try {
    let proposalId = null;
    let urlSource = 'app.aave.com'; // Default to app.aave.com (Aave V3 enum mapping)
    
    // Step 1: Try to extract from query parameter (most reliable)
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
    const voteMatch = url.match(/vote\.onaave\.com\/proposal\/\?.*proposalId=(\d+)/i);
    if (voteMatch) {
      proposalId = voteMatch[1];
      urlSource = 'vote.onaave.com';
      console.log("✅ Extracted from vote.onaave.com:", proposalId);
      return { proposalId, type: 'aip', urlSource };
    }
    
    const appV3Match = url.match(/app\.aave\.com\/governance\/v3\/proposal\/\?.*proposalId=(\d+)/i);
    if (appV3Match) {
      proposalId = appV3Match[1];
      urlSource = 'app.aave.com';
      console.log("✅ Extracted from app.aave.com/governance/v3:", proposalId);
      return { proposalId, type: 'aip', urlSource };
    }
    
    const forumMatch = url.match(/governance\.aave\.com\/t\/[^\/]+\/(\d+)/i);
    if (forumMatch) {
      proposalId = forumMatch[1];
      urlSource = 'app.aave.com';
      console.log("✅ Extracted from governance.aave.com forum:", proposalId);
      return { proposalId, type: 'aip', urlSource };
    }
    
    const appMatch = url.match(/app\.aave\.com\/governance\/(?:proposal\/)?(\d+)/i);
    if (appMatch) {
      proposalId = appMatch[1];
      urlSource = 'app.aave.com';
      console.log("✅ Extracted from app.aave.com/governance:", proposalId);
      return { proposalId, type: 'aip', urlSource };
    }
    
    const aipMatch = url.match(/governance\.aave\.com\/aip\/(\d+)/i);
    if (aipMatch) {
      proposalId = aipMatch[1];
      urlSource = 'app.aave.com';
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

/**
 * Extract proposal info from URL (wrapper function that detects type)
 */
export function extractProposalInfo(url) {
  if (!url) {
    return null;
  }
  
  // Try Snapshot first
  const snapshotInfo = extractSnapshotProposalInfo(url);
  if (snapshotInfo) {
    return {
      ...snapshotInfo,
      urlProposalNumber: snapshotInfo.proposalId,
      internalId: snapshotInfo.proposalId
    };
  }
  
  // Try AIP
  const aipInfo = extractAIPProposalInfo(url);
  if (aipInfo) {
    return {
      ...aipInfo,
      proposalId: aipInfo.proposalId,
      urlProposalNumber: aipInfo.proposalId,
      internalId: aipInfo.proposalId,
      topicId: aipInfo.proposalId
    };
  }
  
  console.warn("❌ Could not extract proposal info from URL:", url);
  return null;
}

