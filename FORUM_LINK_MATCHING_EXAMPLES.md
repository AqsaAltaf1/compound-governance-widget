# Forum Link Matching Examples

## How It Works

The system matches forum links by:
1. **Extracting** discussion links from proposals (Snapshot/AIP)
2. **Normalizing** both the current forum URL and proposal's discussion links
3. **Comparing** normalized URLs for exact match

---

## URL Normalization

All forum URLs are normalized to: `https://governance.aave.com/t/slug/topicId`

### Normalization Process:
- Removes query parameters (`?page=2`, `?filter=all`)
- Removes fragments (`#post-123`)
- Removes trailing paths
- Converts to lowercase
- Removes `www.` prefix
- Extracts: `protocol://host/t/slug/topicId`

---

## Example Scenarios

### ✅ **MATCHING - Exact Match**

**Current Forum Page:**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Proposal Discussion Link:**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Normalized (both):**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Result:** ✅ **MATCH** - Widget will be displayed

---

### ✅ **MATCHING - With Query Parameters**

**Current Forum Page:**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Proposal Discussion Link:**
```
https://governance.aave.com/t/temp-check-proposal/12345?page=2&filter=all
```

**Normalized (both):**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Result:** ✅ **MATCH** - Query parameters are ignored, widget will be displayed

---

### ✅ **MATCHING - With Fragment**

**Current Forum Page:**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Proposal Discussion Link:**
```
https://governance.aave.com/t/temp-check-proposal/12345#post-5
```

**Normalized (both):**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Result:** ✅ **MATCH** - Fragment is ignored, widget will be displayed

---

### ✅ **MATCHING - With www Prefix**

**Current Forum Page:**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Proposal Discussion Link:**
```
https://www.governance.aave.com/t/temp-check-proposal/12345
```

**Normalized (both):**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Result:** ✅ **MATCH** - www prefix is removed, widget will be displayed

---

### ✅ **MATCHING - HTTP vs HTTPS**

**Current Forum Page:**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Proposal Discussion Link:**
```
http://governance.aave.com/t/temp-check-proposal/12345
```

**Normalized (both):**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Result:** ✅ **MATCH** - Protocol is normalized to https, widget will be displayed

---

### ❌ **NOT MATCHING - Different Topic ID**

**Current Forum Page:**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Proposal Discussion Link:**
```
https://governance.aave.com/t/temp-check-proposal/67890
```

**Normalized:**
- Current: `https://governance.aave.com/t/temp-check-proposal/12345`
- Proposal: `https://governance.aave.com/t/temp-check-proposal/67890`

**Result:** ❌ **NO MATCH** - Different topic IDs, widget will NOT be displayed

---

### ❌ **NOT MATCHING - Different Slug**

**Current Forum Page:**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Proposal Discussion Link:**
```
https://governance.aave.com/t/arfc-proposal/12345
```

**Normalized:**
- Current: `https://governance.aave.com/t/temp-check-proposal/12345`
- Proposal: `https://governance.aave.com/t/arfc-proposal/12345`

**Result:** ❌ **NO MATCH** - Different slugs, widget will NOT be displayed

---

### ❌ **NOT MATCHING - No Forum Link in Proposal**

**Current Forum Page:**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Proposal Discussion Link:**
```
(null - no forum link found in proposal)
```

**Result:** ❌ **NO MATCH** - No forum link found, widget will NOT be displayed (prevents false positives)

---

### ❌ **NOT MATCHING - Different Forum Domain**

**Current Forum Page:**
```
https://governance.aave.com/t/temp-check-proposal/12345
```

**Proposal Discussion Link:**
```
https://forum.example.com/t/temp-check-proposal/12345
```

**Normalized:**
- Current: `https://governance.aave.com/t/temp-check-proposal/12345`
- Proposal: `https://forum.example.com/t/temp-check-proposal/12345`

**Result:** ❌ **NO MATCH** - Different domains, widget will NOT be displayed

---

## Real-World Scenarios

### Scenario 1: Correct Proposal on Forum Topic

**Situation:**
- User is viewing forum topic: `https://governance.aave.com/t/temp-check-aave-v3-upgrade/12345`
- Snapshot proposal has discussion link: `https://governance.aave.com/t/temp-check-aave-v3-upgrade/12345`

**Result:** ✅ Widget displayed - URLs match exactly

---

### Scenario 2: Proposal Mentioned in Discussion (False Positive Prevention)

**Situation:**
- User is viewing forum topic: `https://governance.aave.com/t/temp-check-aave-v3-upgrade/12345`
- Someone in the discussion mentions another proposal's link: `https://governance.aave.com/t/arfc-something-else/67890`
- That other proposal's discussion link points to: `https://governance.aave.com/t/arfc-something-else/67890`

**Result:** ❌ Widget NOT displayed - The mentioned proposal's link doesn't match current forum topic

---

### Scenario 3: Proposal Without Forum Link

**Situation:**
- User is viewing forum topic: `https://governance.aave.com/t/temp-check-aave-v3-upgrade/12345`
- Snapshot proposal exists but has NO discussion link field populated

**Result:** ❌ Widget NOT displayed - No forum link to match against (prevents false positives)

---

### Scenario 4: Multiple Discussion Links in Proposal

**Situation:**
- User is viewing forum topic: `https://governance.aave.com/t/temp-check-aave-v3-upgrade/12345`
- Snapshot proposal has multiple discussion links:
  - `https://governance.aave.com/t/old-topic/11111`
  - `https://governance.aave.com/t/temp-check-aave-v3-upgrade/12345` ✅
  - `https://governance.aave.com/t/other-topic/22222`

**Result:** ✅ Widget displayed - One of the links matches the current forum topic

---

## Where Discussion Links Are Extracted From

### Snapshot Proposals:
1. `proposal.data.discussion` - Direct discussion field
2. `proposal.data.plugins` - Discourse plugin field
3. `proposal.data._rawProposal.discussion` - Raw proposal discussion
4. `proposal.data._rawProposal.plugins` - Raw proposal plugins
5. `proposal.data.body` or `proposal.data.description` - Text search (fallback)

### AIP Proposals:
1. `proposal.data.discussion` - Direct discussion field
2. `proposal.data.metadata.discussion` - Metadata discussion field
3. `proposal.data._rawProposal.discussion` - Raw proposal discussion
4. `proposal.data.description` or `proposal.data.body` - Text search (fallback)
5. `proposal.data.metadata` - Metadata field (JSON string search)

**Note:** Only Aave forum URLs (`governance.aave.com/t/...`) are extracted - other URLs are ignored.

---

## Console Logs to Watch For

### Successful Match:
```
✅ [VALIDATE] Snapshot proposal is related to forum topic (found matching discussion link: https://governance.aave.com/t/...)
```

### No Match (has link):
```
⚠️ [VALIDATE] Snapshot proposal is NOT related to current forum topic - will show with discussion link
   Found discussion links: https://governance.aave.com/t/other-topic/67890
⚠️ [RENDER] Skipping widget - discussion URL does not match current forum topic
```

### No Match (no link):
```
⚠️ [VALIDATE] Snapshot proposal is NOT related to current forum topic
   No discussion links found in proposal
⚠️ [RENDER] Skipping widget - no forum discussion link found in proposal (preventing false positives)
```

---

## Summary

✅ **Widget WILL be displayed if:**
- Proposal has a forum discussion link that matches the current forum topic URL (after normalization)

❌ **Widget will NOT be displayed if:**
- Proposal has no forum discussion link (prevents false positives)
- Proposal has a forum discussion link that doesn't match the current forum topic
- Proposal is on a different forum topic (different topic ID or slug)

This ensures only proposals explicitly linked to the current forum topic are shown, preventing false positives when other proposal links are mentioned in discussions.

