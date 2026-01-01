import Component from "@glimmer/component";
import { inject as service } from "@ember/service";
import { action } from "@ember/object";
import { renderMultiStageWidget } from "../lib/dom/multi-stage-widget";

export default class GovernanceWidgetContainer extends Component {
  @service("proposal-manager") proposalManager;

  get hasProposals() {
    return this.proposalManager?.selectedProposals?.length > 0;
  }

  get proposals() {
    return this.proposalManager?.selectedProposals || [];
  }

  @action
  renderWidgets(element) {
    // Clear any existing widgets in this container
    element.innerHTML = "";
    
    if (!this.hasProposals) {
      return;
    }
    
    // Create a Set to track rendering URLs (prevent duplicates)
    const renderingUrls = new Set();
    const fetchingUrls = new Set();
    
    // Render each proposal widget
    this.proposals.forEach((proposal, index) => {
      if (renderingUrls.has(proposal.url)) {
        console.log(`🔵 [COMPONENT] URL ${proposal.url} is already being rendered, skipping duplicate`);
        return;
      }
      
      renderingUrls.add(proposal.url);
      
      const stage = proposal.stage || proposal.type || 'arfc';
      const widgetId = `${stage}-widget-${index}-${Date.now()}`;
      
      // Create a container div for this widget
      const widgetContainer = document.createElement("div");
      widgetContainer.className = "governance-widget-item";
      element.appendChild(widgetContainer);
      
      // Render based on proposal type
      if (proposal.type === 'aip') {
        renderMultiStageWidget({
          tempCheck: null,
          tempCheckUrl: null,
          arfc: null,
          arfcUrl: null,
          aip: proposal.data,
          aipUrl: proposal.url
        }, widgetId, index, renderingUrls, fetchingUrls, widgetContainer);
      } else {
        // Snapshot proposal
        renderMultiStageWidget({
          tempCheck: stage === 'temp-check' ? proposal.data : null,
          tempCheckUrl: stage === 'temp-check' ? proposal.url : null,
          arfc: (stage === 'arfc' || stage === 'snapshot') ? proposal.data : null,
          arfcUrl: (stage === 'arfc' || stage === 'snapshot') ? proposal.url : null,
          aip: null,
          aipUrl: null
        }, widgetId, index, renderingUrls, fetchingUrls, widgetContainer);
      }
    });
  }
}

