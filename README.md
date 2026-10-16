# Database-driven X12 Validator

Lua module that uses database metadata to interpret X12 segments and loops and validate message structure.

## Design

Rule tables describe segment groups, identifiers, ordering, optionality, and repeat limits. The module uses those rules to build a group hierarchy, compare input segments, and produce validation details intended for IK3 segments in a 999 acknowledgment.

## Entry point

`segValidate.tsSegmentStructure(tsMsg, dataType)` returns a validation result and error details. The input convention prefixes `ST*` and the transaction type internally; confirm the expected message fragment before integration.

## Setup

Runs within Iguana using its X12 parser and string helpers. Configure these generic integration names for your environment:

- `rules.db_helper`: database connection (`conn`).
- `rules.query_cache`: query interface (`query`).
- `rules.config`: table prefix (`dbprefix`).
- `segment_rules_<dataType>`: segment and loop metadata.
- `transaction_structure.vmd`: VMD used for repeat checks.

The repeat-check path uses transaction type 270. Match the VMD and rule configuration to the transaction being evaluated.
