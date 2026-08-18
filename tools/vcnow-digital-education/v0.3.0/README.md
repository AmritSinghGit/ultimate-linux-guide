# VCNow Digital Education convergence v0.3.0

This installer handles the verified v0.3.0 package downloaded into the Mac
`Downloads` folder from the owner handoff.

```bash
curl -fsSL https://raw.githubusercontent.com/AmritSinghGit/ultimate-linux-guide/main/tools/vcnow-digital-education/v0.3.0/install-from-downloads.sh | bash
```

It verifies the exact package SHA-256, preserves an earlier extracted copy,
verifies the complete internal file manifest, and starts the local integrated
website + WordPress bridge + AMS/LMS review.

Expected package:

```text
VCNOW_DIGITAL_EDUCATION_CONVERGENCE_v0.3.0.zip
SHA-256: f7f85f4973b4544f53dfda33fa286929c38ecbb15925febbad7b57c516112a69
```

The command does not merge a VCNow pull request, deploy, change DNS, mutate live
WordPress, call external providers, or apply a production migration.
