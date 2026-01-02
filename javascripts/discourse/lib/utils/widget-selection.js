export function getStatePriority(status) {
  const normalizedStatus = (status || "").toLowerCase().trim();

  if (
    normalizedStatus === "active" ||
    normalizedStatus === "open" ||
    normalizedStatus === "voting"
  ) {
    return 1;
  }

  if (normalizedStatus === "created") {
    return 2;
  }

  if (
    normalizedStatus === "pending" ||
    normalizedStatus === "pendingexecution" ||
    normalizedStatus.includes("pending execution") ||
    normalizedStatus === "queued"
  ) {
    return 3;
  }

  if (
    normalizedStatus === "executed" ||
    normalizedStatus === "crosschainexecuted" ||
    normalizedStatus === "completed" ||
    normalizedStatus === "passed"
  ) {
    return 4;
  }

  if (
    normalizedStatus === "closed" ||
    normalizedStatus === "ended" ||
    normalizedStatus === "expired"
  ) {
    return 5;
  }

  if (
    normalizedStatus === "failed" ||
    normalizedStatus === "defeated" ||
    normalizedStatus === "defeat" ||
    normalizedStatus === "rejected" ||
    normalizedStatus.includes("quorum not reached") ||
    normalizedStatus === "cancelled"
  ) {
    return 6;
  }

  return 7;
}

export function selectTopProposals(proposalsList) {
  const sorted = proposalsList.sort((a, b) => {
    const priorityA = getStatePriority(a.status);
    const priorityB = getStatePriority(b.status);

    if (priorityA !== priorityB) {
      return priorityA - priorityB;
    }

    return a.originalOrder - b.originalOrder;
  });

  const allTypes = sorted.map((p) => {
    const proposalType = p.stage || p.type || "arfc";
    return proposalType === "temp-check"
      ? "tempcheck"
      : proposalType === "aip"
        ? "aip"
        : "arfc";
  });
  const uniqueTypes = [...new Set(allTypes)];
  const isSingleType = uniqueTypes.length === 1;

  const selected = [];
  const typeCounts = { tempcheck: 0, arfc: 0, aip: 0 };
  const maxPerType = isSingleType ? 3 : 2;

  for (const proposal of sorted) {
    if (selected.length >= 3) {
      break;
    }

    const proposalType = proposal.stage || proposal.type || "arfc";
    const typeKey =
      proposalType === "temp-check"
        ? "tempcheck"
        : proposalType === "aip"
          ? "aip"
          : "arfc";

    const canAdd =
      typeCounts[typeKey] < maxPerType ||
      (selected.length < 3 &&
        Object.values(typeCounts).every((count) => count === 0));

    if (canAdd) {
      selected.push(proposal);
      typeCounts[typeKey]++;
    }
  }

  console.log(
    `🔵 [SELECTION] Selected ${selected.length} proposal(s) from ${proposalsList.length} total (${isSingleType ? "single type - showing all 3" : "multiple types - max 2 per type"}):`
  );
  selected.forEach((p, idx) => {
    const type = p.stage || p.type || "arfc";
    console.log(
      `  [${idx + 1}] ${p.title?.substring(0, 50)}... (${type}, status: ${p.status}, priority: ${getStatePriority(p.status)})`
    );
  });

  return selected;
}
