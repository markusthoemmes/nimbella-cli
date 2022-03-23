<!--
 * DigitalOcean, LLC CONFIDENTIAL
 * ------------------------------
 *
 *   2021 - present DigitalOcean, LLC
 *   All Rights Reserved.
 *
 * NOTICE:
 *
 * All information contained herein is, and remains the property of
 * DigitalOcean, LLC and its suppliers, if any.  The intellectual and technical
 * concepts contained herein are proprietary to DigitalOcean, LLC and its
 * suppliers and may be covered by U.S. and Foreign Patents, patents
 * in process, and are protected by trade secret or copyright law.
 *
 * Dissemination of this information or reproduction of this material
 * is strictly forbidden unless prior written permission is obtained
 * from DigitalOcean, LLC.
-->

### The `nimcli` Repository

This repository contains the build scripts for the DigitalOcean-specific build of `nimbella-cli`.

The `nimbella-cli` repo itself is open source and its build is more generic.  The scripts here reach into that repo to do the build in a more tailored way.

The internal build options are described in initial comments in `build.sh` in this repository.

### CI/CD 

This repository is fetched during CI of the serverless platform in Concourse. There are three places where this repo will impact a CI pipeline:
- `prod`: the CLI tests in this pipeline should reflect the state of the system in production, which may be backlevel from staging and development clusters. To accomodate this drift, the CI pipeline pulls this repo from the `prod` branch, which means this branch should be synchronized with `master` from time to time.
- `pre-prod`: the CLI tests run in the `pre-prod` CI pipeline with the goal of publishing releases ready for promotion to production. This pipeline pulls the `master` branch from this repo.
- `testing`: when running the CLI tests against pull requests from the `main` serverless platform repo, it may be necessary to stage commits against this repo that are not ready for `pre-prod` or `prod`. In this case, it is necessary to create a separate branch for the PR testing pipeline. This change is typically done by changing the [`branch` in the `pr-pipeline` configuration found in `main`](https://github.internal.digitalocean.com/serverless/main/blob/646ed5956adbc3f4ce653c3b36f7f906dbca8a48/ci/pr-pipeline.yml#L63).
