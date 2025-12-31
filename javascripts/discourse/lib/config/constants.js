// Configuration constants

export const SNAPSHOT_GRAPHQL_ENDPOINT = "https://hub.snapshot.org/graphql";
export const SNAPSHOT_TESTNET_GRAPHQL_ENDPOINT = "https://testnet.hub.snapshot.org/graphql";
export const SNAPSHOT_URL_REGEX = /https?:\/\/(?:www\.)?(?:snapshot\.org|testnet\.snapshot\.box)\/#\/[^\s<>"']+/gi;

export const AAVE_FORUM_URL_REGEX = /https?:\/\/(?:www\.)?governance\.aave\.com\/t\/[^\s<>"']+/gi;
export const AAVE_GOVERNANCE_PORTAL = "https://app.aave.com/governance";
export const AIP_URL_REGEX = /https?:\/\/(?:www\.)?(?:governance\.aave\.com|app\.aave\.com\/governance|vote\.onaave\.com)\/[^\s<>"']+/gi;

export const GRAPH_API_KEY = "9e7b4a29889ac6c358b235230a5fe940";
export const SUBGRAPH_ID = "A7QMszgomC9cnnfpAcqZVLr2DffvkGNfimD8iUSMiurK";
export const AAVE_V3_SUBGRAPH = `https://gateway.thegraph.com/api/${GRAPH_API_KEY}/subgraphs/id/${SUBGRAPH_ID}`;

