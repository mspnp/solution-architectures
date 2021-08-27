# Computer forensics chain of custody in Azure

This content supports the [Computer forensics Chain of Custody in Azure](https://docs.microsoft.com/azure/architecture/example-scenario/forensics/) Azure Architecture Center article. For information about these files please see that article.

## Contents

* [Copy‑VmDigitalEvidenceWin](./Copy‑VmDigitalEvidenceWin.ps1) runbook for Windows Hybrid RunBook Worker.
* [Copy‑VmDigitalEvidence](./Copy‑VmDigitalEvidence.ps1) runbook for Linux Hybrid RunBook Worker. The Hybrid Runbook Worker must have PowerShell Core installed and the `sha256sum` program available, to calculate the disk snapshots' SHA-256 hash values.