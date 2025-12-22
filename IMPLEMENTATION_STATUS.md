# Implementation Status: URL Matching vs Title Matching

## Summary

**Title Matching: NOT IMPLEMENTED** ✅
- The function `compareTopicSlugWithTitle()` exists in the code but is **never called**
- It's marked as unused (eslint-disable-line no-unused-vars)
- **No title matching logic is active**

**URL Matching: IMPLEMENTED** ✅
- URL matching is the **only active matching mechanism**
- Implemented in two validation functions:
  - `validateSnapshotProposalForForum()` (lines 5971-6016)
  - `validateAIPProposalForForum()` (lines 6030-6093)

---

## Current Implementation Details

### 1. URL Matching Logic

#### For Snapshot Proposals (`validateSnapshotProposalForForum`):
1. Gets current forum URL via `getCurrentForumTopicUrl()`
2. Extracts discussion links from proposal via `extractDiscussionLinksFromSnapshot()`
3. Normalizes both URLs using `normalizeForumUrl()`
4. Compares normalized URLs for exact match
5. Returns `{ isRelated: true/false, discussionLink: string|null }`

#### For AIP Proposals (`validateAIPProposalForForum`):
1. Gets current forum URL via `getCurrentForumTopicUrl()`
2. Extracts discussion links from proposal via `extractDiscussionLinksFromAIP()`
3. Normalizes both URLs using `normalizeForumUrl()`
4. Compares normalized URLs for exact match
5. **Also checks**: If AIP proposal ID matches forum topic ID (special case)
6. Returns `{ isRelated: true/false, discussionLink: string|null }`

### 2. URL Normalization (`normalizeForumUrl`)

Normalizes forum URLs to format: `protocol://host/t/slug/topicId`
- Removes query parameters, fragments, trailing paths
- Converts to lowercase
- Removes `www.` prefix
- Extracts pattern: `https?://[host]/t/[slug]/[topicId]`

Example:
- Input: `https://governance.aave.com/t/temp-check-proposal/12345?page=2#post-1`
- Output: `https://governance.aave.com/t/temp-check-proposal/12345`

### 3. Discussion Link Extraction

#### From Snapshot Proposals (`extractDiscussionLinksFromSnapshot`):
Checks these fields in order:
1. `proposal.data.discussion` - Direct discussion link field
2. `proposal.data.plugins` - Discourse plugin field
3. `proposal.data._rawProposal.discussion` - Raw proposal discussion
4. `proposal.data._rawProposal.plugins` - Raw proposal plugins
5. `proposal.data.body` or `proposal.data.description` - Fallback text search

**Only extracts Aave forum URLs** (matches `AAVE_FORUM_URL_REGEX`)

#### From AIP Proposals (`extractDiscussionLinksFromAIP`):
Checks these fields in order:
1. `proposal.data.discussion` - Direct discussion link
2. `proposal.data.metadata.discussion` - Metadata discussion field
3. `proposal.data._rawProposal.discussion` - Raw proposal discussion
4. `proposal.data.description` or `proposal.data.body` - Fallback text search
5. `proposal.data.metadata` - Metadata field (JSON string search)

**Only extracts Aave forum URLs** (matches `AAVE_FORUM_URL_REGEX`)

### 4. Filtering Logic (What Gets Displayed)

**Location**: Lines 6679-6682 (Snapshot) and 6847-6849 (AIP)

```javascript
// Skip rendering if proposal has a discussion URL that doesn't match current forum
if (validation.discussionLink && !validation.isRelated) {
  console.log(`⚠️ [RENDER] Skipping widget - discussion URL does not match current forum topic`);
  return; // Widget is NOT rendered
}
```

**Behavior**:
- ✅ **Proposal IS shown** if:
  - `isRelated === true` (URL matches current forum)
  - `discussionLink === null` (no discussion link found in proposal)
  
- ❌ **Proposal is NOT shown** if:
  - `discussionLink !== null` AND `isRelated === false` (has discussion link but doesn't match)

---

## Potential Issues

### Issue 1: Discussion Links Not Being Extracted
If proposals don't have discussion links in the expected fields, `extractDiscussionLinksFromSnapshot()` or `extractDiscussionLinksFromAIP()` will return empty arrays, causing:
- `discussionLink === null`
- Proposal will be shown (because no discussion link to compare)

### Issue 2: URL Normalization Mismatch
If URLs are normalized differently, they won't match even if they point to the same topic:
- Current forum URL normalization might differ from proposal discussion link normalization
- Check console logs for normalized URLs to verify

### Issue 3: Regex Pattern Issues
The `AAVE_FORUM_URL_REGEX` might not be matching all forum URL formats in proposals. Check if:
- URLs in proposals use different formats
- URLs are encoded differently
- URLs are in unexpected fields

---

## Code Locations

| Function | Purpose | Lines |
|----------|---------|-------|
| `validateSnapshotProposalForForum()` | Validates Snapshot proposals | 5971-6016 |
| `validateAIPProposalForForum()` | Validates AIP proposals | 6030-6093 |
| `normalizeForumUrl()` | Normalizes forum URLs for comparison | 5339-5366 |
| `getCurrentForumTopicUrl()` | Gets current forum topic URL | 5373-5418 |
| `extractDiscussionLinksFromSnapshot()` | Extracts URLs from Snapshot proposals | 5584-5695 |
| `extractDiscussionLinksFromAIP()` | Extracts URLs from AIP proposals | 5850-5958 |
| `compareTopicSlugWithTitle()` | **UNUSED** - Title matching (not called) | 5554-5578 |

---

## Debugging Steps

1. **Check console logs** for:
   - `🔍 [VALIDATE] Validating...` - Shows validation process
   - `🔍 [DISCUSSION] Extracting discussion links...` - Shows URL extraction
   - `✅ [VALIDATE] ... is related...` - Shows successful match
   - `⚠️ [VALIDATE] ... is NOT related...` - Shows failed match

2. **Verify discussion links are being extracted**:
   - Look for `✅ [DISCUSSION] Found forum links...` in console
   - If you see `❌ [DISCUSSION] No discussion links found`, that's the issue

3. **Check URL normalization**:
   - Compare normalized URLs in console logs
   - Both should be in format: `https://governance.aave.com/t/slug/topicId`

4. **Verify current forum URL detection**:
   - Look for `🔵 [VALIDATE] Current forum topic URL: ...` in console
   - Should match the actual page URL

---

## Conclusion

**What's Actually Live:**
- ✅ URL matching ONLY (no title matching)
- ✅ URL normalization for comparison
- ✅ Discussion link extraction from proposals
- ✅ Filtering: Proposals with non-matching discussion links are hidden

**What's NOT Live:**
- ❌ Title matching (function exists but unused)
- ❌ Slug-based matching (function exists but unused)

**If URL matching isn't working, the issue is likely:**
1. Discussion links not being extracted from proposals
2. URL normalization producing different results
3. Discussion links in unexpected formats/fields

