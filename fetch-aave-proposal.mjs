/**
 * Aave Governance V3 Proposal Fetcher
 * 
 * Fetches proposal data from The Graph subgraph for Aave Governance V3
 * 
 * Usage:
 *   node fetch-aave-proposal.mjs [proposalId]
 *   node fetch-aave-proposal.mjs [url]
 * 
 * Examples:
 *   node fetch-aave-proposal.mjs 411
 *   node fetch-aave-proposal.mjs "https://app.aave.com/governance/v3/proposal/?proposalId=411"
 */

const GRAPH_API_KEY = "9e7b4a29889ac6c358b235230a5fe940";
const SUBGRAPH_ID = "A7QMszgomC9cnnfpAcqZVLr2DffvkGNfimD8iUSMiurK";
const SUBGRAPH_URL = `https://gateway.thegraph.com/api/${GRAPH_API_KEY}/subgraphs/id/${SUBGRAPH_ID}`;

/**
 * Extract proposal ID from various Aave governance URL formats
 * @param {string} input - URL or proposal ID
 * @returns {string|null} - Extracted proposal ID or null
 */
function extractProposalId(input) {
  if (!input) return null;
  
  // If it's just a number, return it
  if (/^\d+$/.test(input.trim())) {
    return input.trim();
  }
  
  // Try to extract from URL patterns
  const urlPatterns = [
    /proposalId[=:](\d+)/i,
    /\/proposal\/\?.*proposalId=(\d+)/i,
    /\/governance\/v3\/proposal\/\?.*proposalId=(\d+)/i,
    /\/governance\/(\d+)/i,
    /\/t\/[^\/]+\/(\d+)/i,
    /proposal[\/\-](\d+)/i,
  ];
  
  for (const pattern of urlPatterns) {
    const match = input.match(pattern);
    if (match && match[1]) {
      return match[1];
    }
  }
  
  return null;
}

/**
 * Translate state enum to human-readable string
 * @param {number} state - State enum value (0-7)
 * @returns {string} - Human-readable state
 */
function translateState(state) {
  const states = {
    0: "Null",
    1: "Created",
    2: "Active",
    3: "Queued",
    4: "Executed",
    5: "Failed",
    6: "Cancelled",
    7: "Expired"
  };
  return states[state] || `Unknown (${state})`;
}

/**
 * Format AAVE token amount (divide by 10^18)
 * @param {string|number} amount - Raw amount in wei
 * @returns {string} - Formatted amount with commas
 */
function formatAAVE(amount) {
  const decimals = BigInt(10 ** 18);
  const value = BigInt(amount || 0);
  return (value / decimals).toLocaleString();
}

/**
 * Format duration in seconds to human-readable format
 * @param {number|null} seconds - Duration in seconds
 * @returns {string} - Formatted duration
 */
function formatDuration(seconds) {
  if (!seconds || seconds === null) return "N/A";
  
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  
  const parts = [];
  if (days > 0) parts.push(`${days} day${days !== 1 ? 's' : ''}`);
  if (hours > 0) parts.push(`${hours} hour${hours !== 1 ? 's' : ''}`);
  if (minutes > 0) parts.push(`${minutes} minute${minutes !== 1 ? 's' : ''}`);
  
  return parts.length > 0 ? parts.join(', ') : `${seconds} seconds`;
}

/**
 * Fetch proposal data from The Graph subgraph
 * @param {string} proposalId - Proposal ID to fetch
 * @returns {Promise<Object|null>} - Proposal data or null if not found
 */
async function fetchProposalById(proposalId) {
  const QUERY = `
    {
      proposals(where: { proposalId: "${proposalId}" }) {
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
      }
    }
  `;

  try {
    const res = await fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: QUERY })
    });

    const json = await res.json();

    if (json.errors) {
      console.error("GraphQL Errors:", JSON.stringify(json.errors, null, 2));
      return null;
    }

    const proposals = json.data?.proposals;

    if (!proposals || proposals.length === 0) {
      return null;
    }

    return proposals[0];
  } catch (err) {
    console.error("Fetch Error:", err.message);
    return null;
  }
}

/**
 * Display proposal information in a formatted way
 * @param {Object} proposal - Proposal data object
 */
function displayProposal(proposal) {
  const p = proposal;
  const forVotes = formatAAVE(p.votes?.forVotes || 0);
  const againstVotes = formatAAVE(p.votes?.againstVotes || 0);
  const duration = formatDuration(p.votingDuration);

  console.log(`\n${'='.repeat(50)}`);
  console.log(`📋 Aave Governance Proposal #${p.proposalId}`);
  console.log(`${'='.repeat(50)}`);
  console.log(`Title:     ${p.proposalMetadata?.title || "N/A"}`);
  console.log(`State:     ${translateState(p.state)}`);
  console.log(`Creator:   ${p.creator}`);
  console.log(`IPFS Hash: ${p.ipfsHash || "N/A"}`);
  console.log(`Duration:  ${duration}`);
  console.log(`\nVoting Results:`);
  console.log(`  👍 For:      ${forVotes} AAVE`);
  console.log(`  👎 Against:  ${againstVotes} AAVE`);
  console.log(`${'='.repeat(50)}\n`);
}

/**
 * Main function
 */
async function main() {
  // Get proposal ID from command line argument
  const input = process.argv[2];

  if (!input) {
    console.error("❌ Error: Please provide a proposal ID or URL");
    console.log("\nUsage:");
    console.log("  node fetch-aave-proposal.mjs <proposalId>");
    console.log("  node fetch-aave-proposal.mjs <url>");
    console.log("\nExamples:");
    console.log('  node fetch-aave-proposal.mjs 411');
    console.log('  node fetch-aave-proposal.mjs "https://app.aave.com/governance/v3/proposal/?proposalId=411"');
    process.exit(1);
  }

  // Extract proposal ID from input (handles both IDs and URLs)
  const proposalId = extractProposalId(input);

  if (!proposalId) {
    console.error(`❌ Error: Could not extract proposal ID from: ${input}`);
    console.log("\nSupported formats:");
    console.log("  - Proposal ID: 411");
    console.log("  - URL: https://app.aave.com/governance/v3/proposal/?proposalId=411");
    console.log("  - URL: https://app.aave.com/governance/411");
    console.log("  - URL: https://governance.aave.com/t/slug/411");
    process.exit(1);
  }

  console.log(`🔍 Fetching proposal #${proposalId}...`);

  const proposal = await fetchProposalById(proposalId);

  if (!proposal) {
    console.log(`\n❌ No proposal found with ID: ${proposalId}`);
    process.exit(1);
  }

  displayProposal(proposal);
}

// Run the script
main().catch((err) => {
  console.error("❌ Script Error:", err.message);
  process.exit(1);
});

