# Database-driven X12 Validator

Lua prototype that uses database metadata to interpret X12 segments and loops and validate message structure.

## Design

Rule tables describe segment groups, identifiers, ordering, optionality, and repeat limits. The module uses those rules to build a group hierarchy, compare input segments, and produce validation details intended for IK3 segments in a 999 acknowledgment.

## Entry point

`segValidate.tsSegmentStructure(tsMsg, dataType)` returns a validation result and error details. The recovered input convention prefixes `ST*` and the transaction type internally; confirm the expected message fragment before integration.

## Recovery status

This repository is an incomplete historical prototype. It is not a runnable validator distribution or a claim of X12 standards conformance.

Missing dependencies:

- Iguana runtime APIs, including X12 parsing and string extensions.
- `X12_270.dbHelper`, `X12.querycache`, and `X12_270.Config`.
- Matching `Lookup_Segment_Listing_<dataType>` rule tables.
- `x12_270_5010_V1_Repeating.vmd`.

## Cleanup

Normalized whitespace, removed exploratory trace/print statements, kept helper functions local, and checked the public entry-point types.

## Known limitations

Syntax validation passes locally. Behavioral validation needs the missing helpers and rule fixtures and has not been performed.

Recovered project by Meer Ushter.
