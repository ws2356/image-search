# Monorepo Agent Guide

## Terminology
- AuSearch: Desktop app for image search; Pairs with AuBackup iOS & Android for mobile album backup.
- AuBackup: iOS & Android app for file backup
- InstantShare: Desktop & iOS app for one-shot file sharing
- SnapGet: Branding name for InstantShare
- Mobile folder: The term specific to AuSearch desktop app refering to backup feature.

This repository contains multiple products/platform combinations.

| Product | Location |
|----------|----------|
| AuSearch Desktop | dt_image_search |
| AuBackup iOS | mobile/ios |
| AuBackup Android | mobile/rn |
| SnapGet Desktop | dt_image_search |
| SnapGet iOS | mobile/instant-share |

## Product Specs

Desktop/iOS/Android implement the same backup & sharing protocol.

Specifications:

- Backup Spec (manually maintained): docs/mobile-folder/
- Sharing Spec (maintained by the superpowers skill): docs/superpowers/

## Shared Engineering Principles

- Ask for clarification if requirements are ambiguous.
- Prefer maintainable solutions over quick fixes.
- Do not duplicate documentation.
- Build must pass before task completion.
- Think critically.
- Keep commits small.