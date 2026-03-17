# Architecture Decision: Use DTOs for LWC Communication

**Date:** 2026-03-17
**Status:** Accepted

## Problem

In a managed package with namespace prefix (`OpenSF__`), sObject field names returned from Apex to LWC get prefixed (e.g., `OpenSF__Status__c`). This breaks JS code that references `Status__c` directly. Even using `Map<String, Object>` has inconsistencies with serialization.

## Decision

All Apex methods called by LWC components should return **inner class DTOs** (Data Transfer Objects) instead of sObjects or Maps. DTOs:

- Have predictable camelCase property names
- Are namespace-agnostic
- Serialize cleanly to JSON for LWC consumption
- Provide a clear contract between Apex and LWC

## Pattern

```apex
public class QRNGSetupController {
    public class BackendHealthDTO {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Integer qubits;
        // ...
    }

    @AuraEnabled
    public static List<BackendHealthDTO> getAllBackendHealth() {
        // Query sObjects, map to DTOs, return
    }
}
```
