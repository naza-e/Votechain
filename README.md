# Votechain

## Overview

Votechain is a decentralized governance framework that enables token holders to propose, vote on, and execute protocol-level decisions. Built around SIP-010 token standards, it provides a structured, transparent, and secure on-chain system for managing community-driven upgrades, parameter changes, treasury operations, and administrative settings.

## Key Features

* Creation and management of governance motions with configurable categories and voting rules.
* On-chain voting with weighted voting power based on token balances.
* Automated quorum checks and majority thresholds for proposal approval.
* Execution pipeline for enacting approved motions after a governance-defined delay.
* Configurable protocol settings stored on-chain, modifiable only through successful governance actions.
* Support for attaching custom actions to motions, including parameter changes and fund transfers.

## Contract Components

### Governance Data Structures

* **protocol-settings:** Stores configurable governance parameters including voting delay, duration, quorum requirements, simple majority threshold, and execution delay.
* **community-motions:** Tracks full metadata for each motion such as proposer, category, status, timelines, vote tallies, and thresholds.
* **motion-actions:** Stores the actions attached to a motion that will be executed once the motion passes.
* **ballot-records:** Records voter selections, voting power, and timestamps per motion.
* **motion-counter:** Auto-incremented identifier for new motions.
* **min-motion-deposit:** Token deposit required to create a motion.

### Motion Lifecycle

1. **Creation:** Users with sufficient token balance can draft a motion and set its details.
2. **Action Attachment:** Proposer can attach one or more actions, such as parameter updates or fund transfers.
3. **Activation:** Motion becomes active and voting can begin after the configured voting delay.
4. **Voting:** Token holders cast ballots weighted by their token balance.
5. **Finalization:** After voting ends, quorum and majority are evaluated to determine if the motion passes.
6. **Execution:** Passed motions can be executed after the execution delay, applying all configured actions.

### Voting Logic

* Supports “yes”, “no”, and “abstain” ballot types.
* Automatically adjusts vote tallies when a user recasts a vote.
* Validates all voting rules including timing, status, and token balance.
* Calculates approval rate and quorum participation using basis-point thresholds.

### Governance-Limited Controls

* **update-protocol-setting:** Allows modification of governance parameters exclusively through approved governance calls.
* **is-governance-call:** Ensures protocol changes cannot be made directly by users or unauthorized contracts.

### Read-Only Queries

* **get-motion-details:** Retrieves full motion metadata.
* **get-protocol-setting:** Returns stored protocol configuration.
* **get-ballot-details:** Shows a voter’s ballot for a motion.
* **check-motion-status:** Returns the current status of a motion.

## Summary

Votechain provides a comprehensive, rules-based, on-chain governance framework tailored for decentralized organizations. It delivers a complete proposal, voting, and execution workflow backed by token-weighted governance and robust validation. With customizable parameters and modular action execution, Votechain supports scalable protocol evolution without centralized control.
