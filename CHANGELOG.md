# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-05-23

### Added
- Authentication & token refresh (EU region)
- `getVehicles()` — list vehicles linked to account
- `getVehicleStatus(vin)` — GPS, lock state, mileage, full vehicle status
- Built-in cache with configurable TTL + 600s cooldown enforcement
- Single-session conflict detection
- Full AES-128-CBC + HMAC-SHA-256 crypto pipeline
- Tested in production on MG3 Hybrid EU
