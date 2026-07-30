# AWS Architecture Icons — reusable subset

Official AWS Architecture Service Icons (48px, "Arch_" category-square style),
extracted from the full package Jay chose to download in Week 9:
https://d1.awsstatic.com/onedam/marketing-channels/website/aws/en_US/architecture/approved/architecture-icons/Icon-package_04302026.4705b90f5aa45b019271a2699e9ce9b97b941ee1.zip

Each file is a 64x64 viewBox SVG: a colored background rect (AWS's official
per-category color) + a white icon path. Embed as an inline `<symbol>` in a
diagram's `<defs>`, then `<use href="#id" width="28" height="28"/>` next to
each node's label — see `week-09-ecs-fargate-self-service`'s blog post for
the working pattern (inline hex colors matching the blog's own theme, not
the visualize-widget's c-* ramp classes, since the published blog page
doesn't load that CSS).

| File | AWS category color |
|---|---|
| `lambda.svg` | Compute — `#ED7100` |
| `ecs.svg` | Compute — `#ED7100` |
| `ecr.svg` | Compute — `#ED7100` |
| `api-gateway.svg` | Networking & Content Delivery — `#8C4FFF` |
| `vpc.svg` | Networking & Content Delivery — `#8C4FFF` |
| `elb.svg` | Networking & Content Delivery — `#8C4FFF` |
| `step-functions.svg` | Application Integration — `#E7157B` |
| `cloudwatch.svg` | Management Tools — `#E7157B` (added Week 10) |
| `organizations.svg` | Management Tools — `#E7157B` (added Week 10) |
| `eventbridge.svg` | Application Integration — `#E7157B` (added Week 10) |
| `sns.svg` | Application Integration — `#E7157B` (added Week 10) |
| `securityhub.svg` | Security, Identity & Compliance — `#DD344C` (added Week 11) |
| `guardduty.svg` | Security, Identity & Compliance — `#DD344C` (added Week 11) |
| `sqs.svg` | Application Integration — `#E7157B` (added Week 11) |
| `config.svg` | Management Tools — `#E7157B` (added Week 12) |
| `systems-manager.svg` | Management Tools — `#E7157B` (added Week 12) |
| `s3.svg` | Storage — `#7AA116` (added Week 12) |

**Adding a new service icon for a future week:** don't re-download the full
14MB package if you still have it locally. If not, re-download from the URL
above (or check AWS's architecture-icons page for the current package —
filenames are date-stamped and change), extract, and copy the specific
`Architecture-Service-Icons_*/Arch_<Category>/48/Arch_<Service>_48.svg` file
you need into this folder with a short lowercase name, then update the table
above.
