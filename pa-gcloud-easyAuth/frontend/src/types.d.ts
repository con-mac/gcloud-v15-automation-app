// Additional type definitions for the application

// Extend Proposal type to include sections
import type { Proposal as BaseProposal, Section } from './types';

export interface ProposalWithSections extends BaseProposal {
  sections: Section[];
  created_by_name?: string;
}

// Extend the base types
export * from './types';

