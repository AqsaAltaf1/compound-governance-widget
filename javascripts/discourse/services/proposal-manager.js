import { tracked } from "@glimmer/tracking";
import Service from "@ember/service";

export default class ProposalManager extends Service {
  @tracked selectedProposals = [];

  setProposals(proposals) {
    this.selectedProposals = proposals || [];
    console.log(
      `✅ [SERVICE] Updated proposals: ${this.selectedProposals.length} proposal(s)`
    );
  }

  clearProposals() {
    this.selectedProposals = [];
    console.log("✅ [SERVICE] Cleared proposals");
  }
}
