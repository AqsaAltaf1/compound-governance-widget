import { ethers } from "ethers";
import fetch from "node-fetch";

const GRAPH_API_KEY = "9e7b4a29889ac6c358b235230a5fe940";
const SUBGRAPH_ID = "A7QMszgomC9cnnfpAcqZVLr2DffvkGNfimD8iUSMiurK";
const SUBGRAPH_URL = `https://gateway.thegraph.com/api/${GRAPH_API_KEY}/subgraphs/id/${SUBGRAPH_ID}`;

// Aave Governance V3 Contract Addresses by Chain
// The subgraph might be indexing a different chain, so we'll try all of them
//
// To find the correct contract addresses:
// 1. Check Aave Governance V3 GitHub: https://github.com/aave-dao/aave-governance-v3
// 2. Look in the deployments/ folder or documentation
// 3. Check The Graph subgraph metadata to see which chain it indexes
// 4. The contract address might be the same across chains, or different
//
// NOTE: If proposals aren't found, the subgraph proposal IDs might not match
// on-chain proposal IDs, or the subgraph might be indexing a different contract
const AAVE_GOVERNANCE_V3_CONTRACTS = {
  ethereum: {
    address: "0xEC568fffba86c094cf06b22134B23074DFE2252c",
    rpc: "https://eth.llamarpc.com",
    name: "Ethereum Mainnet",
  },
  polygon: {
    address: "0xEC568fffba86c094cf06b22134B23074DFE2252c", // Same address on Polygon
    rpc: "https://polygon-rpc.com", // Public Polygon RPC
    name: "Polygon",
  },
  avalanche: {
    address: "0xEC568fffba86c094cf06b22134B23074DFE2252c", // Same address on Avalanche
    rpc: "https://api.avax.network/ext/bc/C/rpc", // Public Avalanche RPC
    name: "Avalanche",
  },
};

// Legacy support - flatten addresses for backward compatibility
const AAVE_GOVERNANCE_V3_ADDRESSES = Object.values(
  AAVE_GOVERNANCE_V3_CONTRACTS
).map((c) => c.address);
// eslint-disable-next-line no-unused-vars
const _AAVE_GOVERNANCE_V3_ADDRESS = AAVE_GOVERNANCE_V3_ADDRESSES[0];

// Simplified ABI for getProposal - returns: (id, creator, startTime, endTime, forVotes, againstVotes, state, executed, canceled)
const AAVE_GOVERNANCE_V3_ABI = [
  "function getProposal(uint256 proposalId) view returns (uint256 id, address creator, uint40 startTime, uint40 endTime, uint256 forVotes, uint256 againstVotes, uint8 state, bool executed, bool canceled)",
];

// Default RPC endpoint (will be overridden per chain)
// eslint-disable-next-line no-unused-vars
const _DEFAULT_RPC_URL = "https://eth.llamarpc.com";

// --- Change this to the ID you want to find ---
const TARGET_ID = "422";

// GraphQL Introspection Query - Discover all available fields
// eslint-disable-next-line no-unused-vars
const _INTROSPECTION_QUERY = `
  query IntrospectSchema {
    __schema {
      types {
        name
        kind
        fields {
          name
          type {
            name
            kind
            ofType {
              name
              kind
            }
          }
        }
      }
    }
  }
`;

// Introspection query for Proposal type specifically
const PROPOSAL_INTROSPECTION_QUERY = `
  query IntrospectProposal {
    __type(name: "Proposal") {
      name
      kind
      fields {
        name
        description
        type {
          name
          kind
          ofType {
            name
            kind
            ofType {
              name
              kind
            }
          }
        }
      }
    }
  }
`;

// Introspection query for ProposalMetadata type
const METADATA_INTROSPECTION_QUERY = `
  query IntrospectProposalMetadata {
    __type(name: "ProposalMetadata") {
      name
      kind
      fields {
        name
        description
        type {
          name
          kind
          ofType {
            name
            kind
          }
        }
      }
    }
  }
`;

// Introspection query for ProposalVotes type
const VOTES_INTROSPECTION_QUERY = `
  query IntrospectProposalVotes {
    __type(name: "ProposalVotes") {
      name
      kind
      fields {
        name
        description
        type {
          name
          kind
          ofType {
            name
            kind
          }
        }
      }
    }
  }
`;

// Introspection queries for nested objects
const VOTING_PORTAL_INTROSPECTION_QUERY = `
  query IntrospectVotingPortal {
    __type(name: "VotingPortal") {
      name
      kind
      fields {
        name
        description
        type {
          name
          kind
          ofType {
            name
            kind
          }
        }
      }
    }
  }
`;

const VOTING_CONFIG_INTROSPECTION_QUERY = `
  query IntrospectVotingConfig {
    __type(name: "VotingConfig") {
      name
      kind
      fields {
        name
        description
        type {
          name
          kind
          ofType {
            name
            kind
          }
        }
      }
    }
  }
`;

const PROPOSAL_TRANSACTIONS_INTROSPECTION_QUERY = `
  query IntrospectProposalTransactions {
    __type(name: "ProposalTransactions") {
      name
      kind
      fields {
        name
        description
        type {
          name
          kind
          ofType {
            name
            kind
          }
        }
      }
    }
  }
`;

const CONSTANTS_INTROSPECTION_QUERY = `
  query IntrospectConstants {
    __type(name: "Constants") {
      name
      kind
      fields {
        name
        description
        type {
          name
          kind
          ofType {
            name
            kind
          }
        }
      }
    }
  }
`;

// Introspection query for TransactionData type
const TRANSACTION_DATA_INTROSPECTION_QUERY = `
  query IntrospectTransactionData {
    __type(name: "TransactionData") {
      name
      kind
      fields {
        name
        description
        type {
          name
          kind
          ofType {
            name
            kind
          }
        }
      }
    }
  }
`;

// AIP Query will be built dynamically based on introspection results
// This ensures we only fetch fields that actually exist in the schema

// Snapshot GraphQL Query (same as widget uses)
const SNAPSHOT_GRAPHQL_ENDPOINT = "https://hub.snapshot.org/graphql";
// eslint-disable-next-line no-unused-vars
const _SNAPSHOT_SPACE = "aave.eth"; // Example space
// eslint-disable-next-line no-unused-vars
const _SNAPSHOT_PROPOSAL_ID = "0x1234..."; // Example proposal ID

const SNAPSHOT_QUERY = `
  query Proposal($id: String!) {
    proposal(id: $id) {
      # Basic proposal info
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
      updated
      link
      app
      type
      network
      symbol
      privacy
      discussion
      
      # Space information (all possible fields)
      space {
        id
        name
        about
        avatar
        network
        symbol
        members
        followersCount
        private
        verified
        plugins
        filters
        treasuries {
          name
          address
          network
        }
        voting {
          delay
          period
          quorum
          type
          hideAbstain
        }
        strategies {
          name
          network
          params
        }
        validation {
          name
          params
        }
        categories
        admins
        moderators
        followers
        parent
        children
        guidelines
        terms
        twitter
        github
        website
        email
        skin
        domain
      }
      
      # Voting data
      scores
      scores_by_strategy
      scores_total
      scores_updated
      votes
      quorum
      plugins
      flagged
      flaggedReason
      ipfs
      
      # Strategies
      strategies {
        name
        network
        params
      }
      
      # Validation
      validation {
        name
        params
      }
    }
  }
`;

// Alternative: Try to fetch from IPFS metadata
async function fetchFromIPFS(ipfsHash) {
  if (!ipfsHash || ipfsHash === "0x0" || ipfsHash.startsWith("0x0000")) {
    return null;
  }

  try {
    // Convert hex IPFS hash to base58 if needed, or try direct IPFS gateway
    // IPFS hashes are usually base58, but this might be hex-encoded

    // If it's a hex string starting with 0x, try to decode it
    if (ipfsHash.startsWith("0x")) {
      // Try multiple IPFS gateways
      const gateways = [
        `https://ipfs.io/ipfs/${ipfsHash.slice(2)}`,
        `https://gateway.pinata.cloud/ipfs/${ipfsHash.slice(2)}`,
        `https://cloudflare-ipfs.com/ipfs/${ipfsHash.slice(2)}`,
      ];

      for (const gateway of gateways) {
        try {
          console.log(`   🔍 Trying IPFS gateway: ${gateway}`);
          const response = await fetch(gateway, {
            method: "GET",
            headers: { Accept: "application/json" },
            signal: AbortSignal.timeout(5000), // 5 second timeout
          });

          if (response.ok) {
            const data = await response.json();
            console.log(`   ✅ Found IPFS metadata!`);
            return data;
          }
        } catch {
          // Try next gateway
          continue;
        }
      }
    }

    return null;
  } catch (err) {
    console.warn(`   ⚠️  IPFS fetch error: ${err.message}`);
    return null;
  }
}

async function fetchFromOnChain(proposalId) {
  // Convert proposalId to number (ethers expects BigNumber or number)
  const proposalIdNum =
    typeof proposalId === "string" ? parseInt(proposalId, 10) : proposalId;

  if (isNaN(proposalIdNum)) {
    console.warn(`⚠️  Invalid proposal ID: ${proposalId}`);
    return null;
  }

  console.log(
    `\n🔵 Attempting to fetch proposal ${proposalIdNum} from on-chain...`
  );
  console.log(`   Trying multiple chains to find the correct one...`);

  let lastError = null;

  // Try each chain
  for (const [chainName, chainConfig] of Object.entries(
    AAVE_GOVERNANCE_V3_CONTRACTS
  )) {
    console.log(`\n   🔗 Trying ${chainConfig.name}...`);
    console.log(`      Contract: ${chainConfig.address}`);
    console.log(`      RPC: ${chainConfig.rpc}`);

    try {
      // Create provider with timeout
      const provider = new ethers.JsonRpcProvider(chainConfig.rpc, undefined, {
        staticNetwork: true, // Skip network detection to avoid delays
      });

      // Set a timeout for the RPC call
      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error("RPC timeout")), 10000)
      );

      const governanceContract = new ethers.Contract(
        chainConfig.address,
        AAVE_GOVERNANCE_V3_ABI,
        provider
      );

      // Try to fetch the proposal with timeout
      const proposal = await Promise.race([
        governanceContract.getProposal(proposalIdNum),
        timeoutPromise,
      ]);

      // Check if proposal exists and has valid data
      if (!proposal) {
        console.log(`      ❌ Proposal returned null`);
        lastError = new Error(`Proposal returned null on ${chainName}`);
        continue; // Try next chain
      }

      // Verify the proposal ID matches
      const returnedId = proposal.id ? Number(proposal.id) : null;
      if (returnedId !== proposalIdNum) {
        console.log(
          `      ⚠️  Proposal ID mismatch: requested ${proposalIdNum}, got ${returnedId}`
        );
        lastError = new Error(
          `Proposal ${proposalIdNum} not found on ${chainName}`
        );
        continue; // Try next chain
      }

      // Check if startTime and endTime are valid (non-zero)
      const startTime = Number(proposal.startTime);
      const endTime = Number(proposal.endTime);

      console.log(
        `      ✅ Found proposal! startTime: ${startTime}, endTime: ${endTime}`
      );

      if (startTime === 0 || endTime === 0) {
        console.warn(
          `      ⚠️  Proposal has zero timestamps (may not have started voting)`
        );
        lastError = new Error(`Proposal has zero timestamps on ${chainName}`);
        continue; // Try next chain
      }

      // Success! Return the data
      console.log(
        `      ✅ Successfully fetched on-chain data from ${chainConfig.name}!`
      );
      return {
        startTime,
        endTime,
        executed: proposal.executed,
        canceled: proposal.canceled,
        chain: chainName,
      };
    } catch (err) {
      lastError = err;
      if (err.code === "CALL_EXCEPTION") {
        console.log(
          `      ❌ Proposal not found on ${chainName} (contract call reverted)`
        );
      } else if (
        err.message?.includes("network") ||
        err.message?.includes("timeout") ||
        err.message?.includes("RPC timeout") ||
        err.code === "ENOTFOUND"
      ) {
        console.log(
          `      ❌ Network/RPC error on ${chainName}: ${err.message || err.code}`
        );
        console.log(`      (RPC endpoint might be down or incorrect)`);
      } else {
        console.log(
          `      ❌ Error on ${chainName}: ${err.code || err.message}`
        );
      }

      // Continue to next chain
      continue;
    }
  }

  // All chains failed
  if (lastError) {
    console.warn(`\n⚠️  Proposal ${proposalId} not found on any chain`);
    console.warn(
      `   Tried chains: ${Object.keys(AAVE_GOVERNANCE_V3_CONTRACTS).join(", ")}`
    );
    console.warn(`   This usually means:`);
    console.warn(
      `     - The proposal was cancelled before voting started (no on-chain record)`
    );
    console.warn(
      `     - The proposal doesn't exist on any of the chains we checked`
    );
    console.warn(`     - The contract addresses might need to be updated`);
  }

  return null;
}

// Function to introspect the schema and discover available fields
async function introspectSchema() {
  try {
    console.log(
      "\n🔍 [INTROSPECTION] Discovering available fields in the schema..."
    );

    // Introspect Proposal type
    console.log("\n📋 [INTROSPECTION] Fetching Proposal type fields...");
    const proposalRes = await fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: PROPOSAL_INTROSPECTION_QUERY }),
    });

    const proposalData = await proposalRes.json();
    if (proposalData.data?.__type) {
      console.log("\n✅ [PROPOSAL FIELDS] Available fields in Proposal type:");
      proposalData.data.__type.fields.forEach((field) => {
        const typeName =
          field.type.name || field.type.ofType?.name || field.type.kind;
        console.log(
          `   - ${field.name}: ${typeName}${field.description ? ` (${field.description})` : ""}`
        );
      });
    }

    // Introspect ProposalMetadata type
    console.log(
      "\n📋 [INTROSPECTION] Fetching ProposalMetadata type fields..."
    );
    const metadataRes = await fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: METADATA_INTROSPECTION_QUERY }),
    });

    const metadataData = await metadataRes.json();
    if (metadataData.data?.__type) {
      console.log(
        "\n✅ [METADATA FIELDS] Available fields in ProposalMetadata type:"
      );
      metadataData.data.__type.fields.forEach((field) => {
        const typeName =
          field.type.name || field.type.ofType?.name || field.type.kind;
        console.log(
          `   - ${field.name}: ${typeName}${field.description ? ` (${field.description})` : ""}`
        );
      });
    }

    // Introspect ProposalVotes type
    console.log("\n📋 [INTROSPECTION] Fetching ProposalVotes type fields...");
    const votesRes = await fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: VOTES_INTROSPECTION_QUERY }),
    });

    const votesData = await votesRes.json();
    if (votesData.data?.__type) {
      console.log(
        "\n✅ [VOTES FIELDS] Available fields in ProposalVotes type:"
      );
      votesData.data.__type.fields.forEach((field) => {
        const typeName =
          field.type.name || field.type.ofType?.name || field.type.kind;
        console.log(
          `   - ${field.name}: ${typeName}${field.description ? ` (${field.description})` : ""}`
        );
      });
    }

    // Save full introspection data
    console.log("\n📋 [FULL INTROSPECTION] Complete Proposal type definition:");
    console.log(JSON.stringify(proposalData.data, null, 2));

    console.log(
      "\n📋 [FULL INTROSPECTION] Complete ProposalMetadata type definition:"
    );
    console.log(JSON.stringify(metadataData.data, null, 2));

    console.log(
      "\n📋 [FULL INTROSPECTION] Complete ProposalVotes type definition:"
    );
    console.log(JSON.stringify(votesData.data, null, 2));

    // Introspect nested objects
    console.log("\n📋 [INTROSPECTION] Fetching VotingPortal type fields...");
    const portalRes = await fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: VOTING_PORTAL_INTROSPECTION_QUERY }),
    });
    const portalData = await portalRes.json();
    if (portalData.data?.__type) {
      console.log("\n✅ [VOTING PORTAL FIELDS] Available fields:");
      portalData.data.__type.fields.forEach((field) => {
        const typeName =
          field.type.name || field.type.ofType?.name || field.type.kind;
        console.log(`   - ${field.name}: ${typeName}`);
      });
    }

    console.log("\n📋 [INTROSPECTION] Fetching VotingConfig type fields...");
    const configRes = await fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: VOTING_CONFIG_INTROSPECTION_QUERY }),
    });
    const configData = await configRes.json();
    if (configData.data?.__type) {
      console.log("\n✅ [VOTING CONFIG FIELDS] Available fields:");
      configData.data.__type.fields.forEach((field) => {
        const typeName =
          field.type.name || field.type.ofType?.name || field.type.kind;
        console.log(`   - ${field.name}: ${typeName}`);
      });
    }

    console.log(
      "\n📋 [INTROSPECTION] Fetching ProposalTransactions type fields..."
    );
    const txnRes = await fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        query: PROPOSAL_TRANSACTIONS_INTROSPECTION_QUERY,
      }),
    });
    const txnData = await txnRes.json();
    if (txnData.data?.__type) {
      console.log("\n✅ [TRANSACTIONS FIELDS] Available fields:");
      txnData.data.__type.fields.forEach((field) => {
        const typeName =
          field.type.name || field.type.ofType?.name || field.type.kind;
        console.log(`   - ${field.name}: ${typeName}`);
      });
    }

    console.log("\n📋 [INTROSPECTION] Fetching Constants type fields...");
    const constantsRes = await fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: CONSTANTS_INTROSPECTION_QUERY }),
    });
    const constantsData = await constantsRes.json();
    if (constantsData.data?.__type) {
      console.log("\n✅ [CONSTANTS FIELDS] Available fields:");
      constantsData.data.__type.fields.forEach((field) => {
        const typeName =
          field.type.name || field.type.ofType?.name || field.type.kind;
        console.log(`   - ${field.name}: ${typeName}`);
      });
    }

    console.log("\n📋 [INTROSPECTION] Fetching TransactionData type fields...");
    const transactionDataRes = await fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: TRANSACTION_DATA_INTROSPECTION_QUERY }),
    });
    const transactionDataData = await transactionDataRes.json();
    if (transactionDataData.data?.__type) {
      console.log("\n✅ [TRANSACTION DATA FIELDS] Available fields:");
      transactionDataData.data.__type.fields.forEach((field) => {
        const typeName =
          field.type.name || field.type.ofType?.name || field.type.kind;
        console.log(`   - ${field.name}: ${typeName}`);
      });
    }

    return {
      proposal: proposalData.data?.__type,
      metadata: metadataData.data?.__type,
      votes: votesData.data?.__type,
      votingPortal: portalData.data?.__type,
      votingConfig: configData.data?.__type,
      transactions: txnData.data?.__type,
      constants: constantsData.data?.__type,
    };
  } catch (error) {
    console.error("❌ [INTROSPECTION] Error:", error.message);
    return null;
  }
}

// Build query dynamically based on introspection results
function buildQueryFromIntrospection(schemaInfo) {
  let query = `{
  proposals(where: { proposalId: "${TARGET_ID}" }) {
    id
    proposalId
    state
    creator
    accessLevel
    ipfsHash
    votingDuration
    snapshotBlockHash
    
    proposalMetadata {
      id
      proposalId
      title
      rawContent
    }
    
    votes {
      id
      forVotes
      againstVotes
    }`;

  // Add nested objects if we have their field info from introspection
  if (
    schemaInfo?.votingPortal?.fields &&
    schemaInfo.votingPortal.fields.length > 0
  ) {
    const portalFields = schemaInfo.votingPortal.fields
      .map((f) => f.name)
      .join("\n      ");
    query += `
    votingPortal {
      ${portalFields}
    }`;
  }

  if (
    schemaInfo?.votingConfig?.fields &&
    schemaInfo.votingConfig.fields.length > 0
  ) {
    const configFields = schemaInfo.votingConfig.fields
      .map((f) => f.name)
      .join("\n      ");
    query += `
    votingConfig {
      ${configFields}
    }`;
  }

  if (
    schemaInfo?.transactions?.fields &&
    schemaInfo.transactions.fields.length > 0
  ) {
    // For transactions, we need to fetch nested TransactionData fields
    // Based on introspection, TransactionData has: id, timestamp, blockNumber (no transactionHash)
    query += `
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
      queued {
        id
        timestamp
        blockNumber
      }
      executed {
        id
        timestamp
        blockNumber
      }
      failed {
        id
        timestamp
        blockNumber
      }
      canceled {
        id
        timestamp
        blockNumber
      }
    }`;
  }

  if (schemaInfo?.constants?.fields && schemaInfo.constants.fields.length > 0) {
    const constantsFields = schemaInfo.constants.fields
      .map((f) => f.name)
      .join("\n      ");
    query += `
    constants {
      ${constantsFields}
    }`;
  }

  // Payloads is an array, fetch it directly
  query += `
    payloads
  }
}`;

  return query;
}

async function fetchById() {
  try {
    // First, introspect the schema to see available fields
    const schemaInfo = await introspectSchema();

    // Build query with all available fields
    const dynamicQuery = buildQueryFromIntrospection(schemaInfo);

    // Now fetch the actual proposal with all valid fields
    console.log("\n📡 [AIP] Fetching proposal from The Graph API");
    console.log("📍 [PAYLOAD] Request URL:", SUBGRAPH_URL);
    console.log("📍 [PAYLOAD] Request Method: POST");
    console.log("📍 [PAYLOAD] Request Headers:", {
      "Content-Type": "application/json",
    });

    const requestBody = { query: dynamicQuery };
    console.log(
      "📍 [PAYLOAD] Request Body:",
      JSON.stringify(requestBody, null, 2)
    );

    const res = await fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(requestBody),
    });

    console.log("📍 [PAYLOAD] Response Status:", res.status, res.statusText);
    const json = await res.json();
    console.log("📍 [PAYLOAD] Response Body:", JSON.stringify(json, null, 2));

    if (json.errors) {
      console.error("GraphQL Errors:", JSON.stringify(json.errors, null, 2));
      return;
    }

    const proposals = json.data.proposals;

    // Log all available fields from the response
    if (proposals && proposals.length > 0) {
      console.log("\n📋 [ALL FIELDS] Complete proposal object:");
      console.log(JSON.stringify(proposals[0], null, 2));
      console.log(
        "\n📋 [FIELD LIST] All top-level fields:",
        Object.keys(proposals[0])
      );

      if (proposals[0].proposalMetadata) {
        console.log(
          "📋 [METADATA FIELDS]:",
          Object.keys(proposals[0].proposalMetadata)
        );
      }

      if (proposals[0].votes) {
        if (Array.isArray(proposals[0].votes)) {
          console.log(
            "📋 [VOTES] Array with",
            proposals[0].votes.length,
            "items"
          );
          if (proposals[0].votes.length > 0) {
            console.log(
              "📋 [VOTE FIELDS]:",
              Object.keys(proposals[0].votes[0])
            );
          }
        } else {
          console.log("📋 [VOTES FIELDS]:", Object.keys(proposals[0].votes));
        }
      }
    }

    if (!proposals || proposals.length === 0) {
      console.log(`\n❌ No proposal found with ID: ${TARGET_ID}`);
      return;
    }

    const p = proposals[0];
    const decimals = BigInt(10 ** 18);
    const forVotes = (
      BigInt(p.votes?.forVotes || 0) / decimals
    ).toLocaleString();
    const againstVotes = (
      BigInt(p.votes?.againstVotes || 0) / decimals
    ).toLocaleString();

    // Fetch startTime and endTime from on-chain
    // Convert TARGET_ID to number for on-chain call
    const proposalIdNum =
      typeof TARGET_ID === "string" ? parseInt(TARGET_ID, 10) : TARGET_ID;
    const onChainData = await fetchFromOnChain(proposalIdNum);

    // Also try fetching from IPFS metadata as fallback
    let ipfsData = null;
    if (p.ipfsHash) {
      console.log(`\n🔵 Attempting to fetch metadata from IPFS...`);
      ipfsData = await fetchFromIPFS(p.ipfsHash);
    }

    // Extract discussion URL from IPFS metadata and rawContent
    const discussionUrl = extractDiscussionUrlFromAaveProposal(p, ipfsData);

    // Format timestamps
    // Calculate votingActivationTimestamp from transactions.active.timestamp
    // This is when the proposal moves to 'Active' state
    let votingActivationTimestamp = null;
    let startTime, endTime, timeRemaining;

    // Try to get votingActivationTimestamp from transactions.active
    if (p.transactions?.active?.timestamp) {
      votingActivationTimestamp = Number(p.transactions.active.timestamp);
      console.log(
        `   ✅ Found votingActivationTimestamp from transactions.active: ${votingActivationTimestamp}`
      );
    } else if (
      p.transactions?.created?.timestamp &&
      p.votingConfig?.cooldownBeforeVotingStart
    ) {
      // Calculate: created timestamp + cooldown period = activation timestamp
      const createdTimestamp = Number(p.transactions.created.timestamp);
      const cooldown = Number(p.votingConfig.cooldownBeforeVotingStart);
      votingActivationTimestamp = createdTimestamp + cooldown;
      console.log(
        `   ✅ Calculated votingActivationTimestamp: created (${createdTimestamp}) + cooldown (${cooldown}) = ${votingActivationTimestamp}`
      );
    }

    // Calculate end date: votingActivationTimestamp + votingDuration
    if (votingActivationTimestamp && p.votingDuration) {
      const votingDuration = Number(p.votingDuration);
      const endTimestamp = votingActivationTimestamp + votingDuration;

      startTime = new Date(votingActivationTimestamp * 1000).toLocaleString();
      endTime = new Date(endTimestamp * 1000).toLocaleString();
      const now = Date.now();
      timeRemaining = formatTimeRemaining(endTimestamp * 1000 - now);

      console.log(`\n   ✅ CALCULATED DATES FROM TRANSACTION DATA:`);
      console.log(`      ┌─────────────────────────────────────────────────┐`);
      console.log(`      │ Open for Voting (votingActivationTimestamp):     │`);
      console.log(`      │   ${startTime}`);
      console.log(`      │   Timestamp: ${votingActivationTimestamp}`);
      console.log(`      ├─────────────────────────────────────────────────┤`);
      console.log(`      │ End Date (votingActivationTimestamp + duration): │`);
      console.log(`      │   ${endTime}`);
      console.log(
        `      │   Calculation: ${votingActivationTimestamp} + ${votingDuration}s`
      );
      console.log(
        `      │   = ${endTimestamp} (${votingDuration / 86400} days later)`
      );
      console.log(`      ├─────────────────────────────────────────────────┤`);
      console.log(`      │ Time Remaining: ${timeRemaining}`);
      console.log(`      └─────────────────────────────────────────────────┘`);
    } else if (onChainData?.startTime && onChainData?.endTime) {
      // Use on-chain data if available (fallback)
      startTime = new Date(onChainData.startTime * 1000).toLocaleString();
      endTime = new Date(onChainData.endTime * 1000).toLocaleString();
      const now = Date.now();
      const endTimestamp = onChainData.endTime * 1000;
      timeRemaining = formatTimeRemaining(endTimestamp - now);
    } else if (ipfsData) {
      // Try to extract timestamps from IPFS metadata
      // IPFS metadata format varies, try common field names
      const ipfsStart =
        ipfsData.start ||
        ipfsData.startTime ||
        ipfsData.created ||
        ipfsData.createdAt;
      const ipfsEnd = ipfsData.end || ipfsData.endTime || ipfsData.endsAt;

      if (ipfsStart && ipfsEnd) {
        const startTimestamp =
          typeof ipfsStart === "string"
            ? new Date(ipfsStart).getTime() / 1000
            : ipfsStart;
        const endTimestamp =
          typeof ipfsEnd === "string"
            ? new Date(ipfsEnd).getTime() / 1000
            : ipfsEnd;

        startTime = new Date(startTimestamp * 1000).toLocaleString();
        endTime = new Date(endTimestamp * 1000).toLocaleString();
        const now = Date.now();
        timeRemaining = formatTimeRemaining(endTimestamp * 1000 - now);
        console.log(`   ✅ Using timestamps from IPFS metadata`);
      } else {
        // IPFS data found but no timestamps
        if (p.votingDuration && p.votingDuration !== null) {
          const durationDays = Math.floor(p.votingDuration / 86400);
          const durationHours = Math.floor((p.votingDuration % 86400) / 3600);
          const durationMinutes = Math.floor((p.votingDuration % 3600) / 60);
          startTime = "N/A (IPFS metadata found but no timestamp fields)";
          endTime = `Voting duration: ~${durationDays}d ${durationHours}h ${durationMinutes}m`;
          timeRemaining = "N/A (cannot calculate without start time)";
        } else {
          startTime = "N/A (IPFS metadata found but no timestamp fields)";
          endTime = "N/A (IPFS metadata found but no timestamp fields)";
          timeRemaining = "N/A (cannot calculate)";
        }
      }
    } else {
      // No on-chain data available
      if (p.state === 6) {
        // Cancelled
        startTime = "N/A (proposal was cancelled before voting started)";
        endTime = "N/A (proposal was cancelled before voting started)";
        timeRemaining = "N/A (proposal cancelled)";
      } else if (p.votingDuration && p.votingDuration !== null) {
        // Show voting duration but can't calculate exact times without start time
        const durationDays = Math.floor(p.votingDuration / 86400);
        const durationHours = Math.floor((p.votingDuration % 86400) / 3600);
        const durationMinutes = Math.floor((p.votingDuration % 3600) / 60);
        startTime =
          "N/A (on-chain fetch failed - proposal may be on different chain)";
        endTime = `Voting duration: ~${durationDays}d ${durationHours}h ${durationMinutes}m (exact times unavailable)`;
        timeRemaining = "N/A (cannot calculate without start time)";
      } else {
        startTime = "N/A (on-chain data unavailable)";
        endTime = "N/A (on-chain data unavailable)";
        timeRemaining = "N/A (cannot calculate)";
      }
    }

    console.log(`\n--- Found Proposal #${p.proposalId} ---`);
    console.log(`Title:         ${p.proposalMetadata?.title || "N/A"}`);
    console.log(`State:         ${translateState(p.state)}`);
    console.log(`Creator:       ${p.creator}`);
    console.log(`IPFS:          ${p.ipfsHash}`);
    console.log(
      `Discussion:    ${discussionUrl || "N/A (not found in metadata)"}`
    );
    console.log(`Votes:         👍 ${forVotes} AAVE | 👎 ${againstVotes} AAVE`);
    console.log(`Duration:      ${p.votingDuration} seconds`);
    console.log(`Started:       ${startTime}`);
    console.log(`Ends:          ${endTime}`);
    console.log(`Time Left:     ${timeRemaining}`);
    if (onChainData) {
      console.log(
        `Chain:         ${onChainData.chain ? AAVE_GOVERNANCE_V3_CONTRACTS[onChainData.chain].name : "Unknown"}`
      );
      console.log(`Executed:      ${onChainData.executed ? "Yes" : "No"}`);
      console.log(`Canceled:      ${onChainData.canceled ? "Yes" : "No"}`);
    }
    console.log("---------------------------------------\n");
  } catch (err) {
    console.error("Script Error:", err.message);
  }
}

function translateState(state) {
  const states = {
    0: "Null",
    1: "Created",
    2: "Active",
    3: "Queued",
    4: "Executed",
    5: "Failed",
    6: "Cancelled",
    7: "Expired",
  };
  return states[state] || `Unknown (${state})`;
}

function formatTimeRemaining(ms) {
  if (ms <= 0) {
    return "Ended";
  }

  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (days > 0) {
    return `${days} day${days !== 1 ? "s" : ""}, ${hours % 24} hour${hours % 24 !== 1 ? "s" : ""}`;
  }
  if (hours > 0) {
    return `${hours} hour${hours !== 1 ? "s" : ""}, ${minutes % 60} minute${minutes % 60 !== 1 ? "s" : ""}`;
  }
  if (minutes > 0) {
    return `${minutes} minute${minutes !== 1 ? "s" : ""}, ${seconds % 60} second${seconds % 60 !== 1 ? "s" : ""}`;
  }
  return `${seconds} second${seconds !== 1 ? "s" : ""}`;
}

// Regex pattern for matching Aave forum URLs
const AAVE_FORUM_URL_REGEX =
  /https?:\/\/(?:www\.)?governance\.aave\.com\/t\/[^\s<>"']+/gi;

/**
 * Extract discussion/reference links from Aave proposal data
 * Checks IPFS metadata and rawContent for forum URLs
 * Returns an array of discussion URLs found
 */
function extractDiscussionUrlFromAaveProposal(proposal, ipfsData) {
  console.log(
    `\n🔍 [DISCUSSION] Extracting discussion URL from Aave proposal #${proposal?.proposalId || "unknown"}...`
  );

  const discussionUrls = [];

  // Check 1: IPFS metadata (if available)
  if (ipfsData) {
    console.log(
      `   📋 [DISCUSSION] Checking IPFS metadata for discussion URLs...`
    );

    // Check common fields in IPFS metadata
    const fieldsToCheck = [
      ipfsData.discussion,
      ipfsData.discussionUrl,
      ipfsData.discussion_url,
      ipfsData.forumLink,
      ipfsData.forum_link,
      ipfsData.link,
      ipfsData.reference,
      ipfsData.referenceUrl,
    ];

    // Also check if the entire metadata is a string
    if (typeof ipfsData === "string") {
      fieldsToCheck.push(ipfsData);
    } else {
      // Check entire JSON string representation
      try {
        fieldsToCheck.push(JSON.stringify(ipfsData));
      } catch {
        // Ignore JSON stringify errors
      }
    }

    for (const fieldValue of fieldsToCheck) {
      if (fieldValue && typeof fieldValue === "string") {
        AAVE_FORUM_URL_REGEX.lastIndex = 0; // Reset regex
        const matches = fieldValue.match(AAVE_FORUM_URL_REGEX);
        if (matches && matches.length > 0) {
          console.log(
            `   ✅ [DISCUSSION] Found forum URLs in IPFS metadata:`,
            matches
          );
          discussionUrls.push(...matches);
        }
      }
    }
  }

  // Check 2: proposalMetadata.rawContent
  if (proposal?.proposalMetadata?.rawContent) {
    console.log(
      `   📋 [DISCUSSION] Checking proposalMetadata.rawContent for discussion URLs...`
    );
    const rawContent = proposal.proposalMetadata.rawContent;

    if (typeof rawContent === "string") {
      AAVE_FORUM_URL_REGEX.lastIndex = 0; // Reset regex
      const matches = rawContent.match(AAVE_FORUM_URL_REGEX);
      if (matches && matches.length > 0) {
        console.log(
          `   ✅ [DISCUSSION] Found forum URLs in rawContent:`,
          matches
        );
        discussionUrls.push(...matches);
      }
    }
  }

  // Check 3: Check if rawContent is JSON and parse it
  if (proposal?.proposalMetadata?.rawContent) {
    try {
      const parsed = JSON.parse(proposal.proposalMetadata.rawContent);
      if (parsed && typeof parsed === "object") {
        // Check common fields in parsed JSON
        const parsedFields = [
          parsed.discussion,
          parsed.discussionUrl,
          parsed.discussion_url,
          parsed.link,
          parsed.reference,
          parsed.body,
          parsed.description,
        ];

        for (const fieldValue of parsedFields) {
          if (fieldValue && typeof fieldValue === "string") {
            AAVE_FORUM_URL_REGEX.lastIndex = 0; // Reset regex
            const matches = fieldValue.match(AAVE_FORUM_URL_REGEX);
            if (matches && matches.length > 0) {
              console.log(
                `   ✅ [DISCUSSION] Found forum URLs in parsed rawContent:`,
                matches
              );
              discussionUrls.push(...matches);
            }
          }
        }
      }
    } catch {
      // rawContent is not JSON, ignore
    }
  }

  // Normalize and deduplicate links
  const normalizedLinks = discussionUrls
    .map((link) => {
      // Remove query parameters (?) and fragments (#) but keep the path
      let normalized = link.split("?")[0].split("#")[0];
      // Remove trailing slash
      normalized = normalized.replace(/\/$/, "");
      return normalized;
    })
    .filter((link, index, self) => self.indexOf(link) === index);

  if (normalizedLinks.length > 0) {
    console.log(
      `   ✅ [DISCUSSION] Final extracted discussion URLs:`,
      normalizedLinks
    );
  } else {
    console.log(
      `   ❌ [DISCUSSION] No discussion URLs found in IPFS metadata or rawContent`
    );
  }

  return normalizedLinks.length > 0 ? normalizedLinks[0] : null; // Return first match or null
}

// Example: Fetch Snapshot proposal (uncomment to test)
// eslint-disable-next-line no-unused-vars
async function _fetchSnapshotProposal(space, proposalId) {
  try {
    console.log("\n📡 [SNAPSHOT] Fetching proposal from Snapshot API");
    console.log("📍 [PAYLOAD] Request URL:", SNAPSHOT_GRAPHQL_ENDPOINT);
    console.log("📍 [PAYLOAD] Request Method: POST");
    console.log("📍 [PAYLOAD] Request Headers:", {
      "Content-Type": "application/json",
    });

    // Try format: {space}/{proposal-id}
    const fullProposalId = `${space}/${proposalId}`;
    const requestBody = {
      query: SNAPSHOT_QUERY,
      variables: { id: fullProposalId },
    };

    console.log(
      "📍 [PAYLOAD] Request Body:",
      JSON.stringify(requestBody, null, 2)
    );

    const res = await fetch(SNAPSHOT_GRAPHQL_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(requestBody),
    });

    console.log("📍 [PAYLOAD] Response Status:", res.status, res.statusText);
    const json = await res.json();
    console.log("📍 [PAYLOAD] Response Body:", JSON.stringify(json, null, 2));

    if (json.errors) {
      console.error(
        "❌ [SNAPSHOT] GraphQL Errors:",
        JSON.stringify(json.errors, null, 2)
      );
      return null;
    }

    const proposal = json.data?.proposal;

    // Log all available fields from the response
    if (proposal) {
      console.log("\n📋 [ALL FIELDS] Complete Snapshot proposal object:");
      console.log(JSON.stringify(proposal, null, 2));
      console.log(
        "\n📋 [FIELD LIST] All top-level fields:",
        Object.keys(proposal)
      );

      if (proposal.space) {
        console.log("📋 [SPACE FIELDS]:", Object.keys(proposal.space));
      }

      if (proposal.strategies && Array.isArray(proposal.strategies)) {
        console.log(
          "📋 [STRATEGIES] Array with",
          proposal.strategies.length,
          "items"
        );
        if (proposal.strategies.length > 0) {
          console.log(
            "📋 [STRATEGY FIELDS]:",
            Object.keys(proposal.strategies[0])
          );
        }
      }

      if (proposal.validation) {
        console.log(
          "📋 [VALIDATION FIELDS]:",
          Object.keys(proposal.validation)
        );
      }
    }

    return proposal;
  } catch (error) {
    console.error("❌ [SNAPSHOT] Error:", error.message);
    return null;
  }
}

// Main execution
// Uncomment to only introspect schema (discover all fields):
// introspectSchema().then(() => process.exit(0));

// Or run full fetch (includes introspection first):
fetchById();

// Uncomment to test Snapshot fetch:
// fetchSnapshotProposal(SNAPSHOT_SPACE, SNAPSHOT_PROPOSAL_ID);
