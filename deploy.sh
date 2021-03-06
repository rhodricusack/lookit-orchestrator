#!/usr/bin/env bash

# Set defaults and tell the user what we're doing.
echo "Build ID: ${BUILD_ID:=anonymous_build}"
echo "Commit SHA: $COMMIT_SHA"
echo "Short SHA: $SHORT_SHA"
echo "Branch: $BRANCH_NAME"
echo "Tag: ${TAG_NAME:=latest}"

# Kustomization dirs.
PRODUCTION_KUSTOMIZATIONS=kubernetes/lookit/environments/production
STAGING_KUSTOMIZATIONS=kubernetes/lookit/environments/staging
MANIFESTS=kubernetes/manifests

# 1) Get proper kustomizations dir.
# Branches --> environment directories.
declare -A BRANCH_ENV_MAP=(
    [master]="$PRODUCTION_KUSTOMIZATIONS"
    [develop]="$STAGING_KUSTOMIZATIONS"
)
TARGET_KUSTOMIZATIONS=${BRANCH_ENV_MAP[$BRANCH_NAME]}
printf "\ntarget kustomizations directory: %s\n" "$TARGET_KUSTOMIZATIONS"

# 2) Get correct manifests dir.
# Branches --> manifest directories.
declare -A BRANCH_MANIFESTS_MAP=(
    [master]="$MANIFESTS/production"
    [develop]="$MANIFESTS/staging"
)
MANIFESTS_TARGET="${BRANCH_MANIFESTS_MAP[$BRANCH_NAME]}"
mkdir -p "$MANIFESTS_TARGET"
printf "\ntarget manifests directory: %s\n" "$MANIFESTS_TARGET"

# 3) Get correct Makefile target for secret decryption.
# Branches --> Makefile targets.
declare -A BRANCH_DECRYPTER_MAP=(
    [master]="decrypt-prod"
    [develop]="decrypt-staging"
)
DECRYPTER_MAKE_TARGET="${BRANCH_DECRYPTER_MAP[$BRANCH_NAME]}"
make "${DECRYPTER_MAKE_TARGET}"


# 4) Generate top-level kustomization from build env vars.
# FYI: We can also use kustomize edit to propogate build vars.
# https://github.com/kubernetes-sigs/kustomize/blob/master/docs/eschewedFeatures.md#build-time-side-effects-from-cli-args-or-env-variables
# but for now we're just doing environment variable templating.
envsubst \
  < kubernetes/lookit/base/kustomization.template.yaml \
  > kubernetes/lookit/base/kustomization.yaml

envsubst \
  < kubernetes/lookit/transformers/dynamic-labels.template.yaml \
  > kubernetes/lookit/transformers/dynamic-labels.yaml

# 5) Generate the actual configs.
kustomize build --reorder none -o "$MANIFESTS_TARGET" "${TARGET_KUSTOMIZATIONS}"

# 6) Deploy to the correct cluster.
# Branches --> Clusters.
declare -A BRANCH_CLUSTERS_MAP=(
    [master]="lookit-production"
    [develop]="lookit-staging"
)

TARGET_CLUSTER="${BRANCH_CLUSTERS_MAP[$BRANCH_NAME]}"
printf "\ntarget cluster for deployment: %s\n" "$TARGET_CLUSTER"

gcloud container clusters get-credentials "$TARGET_CLUSTER" --zone=us-east1-d
# TODO: Figure out a better way than nuking the jobs every time.
kubectl -n default delete job --all
kubectl apply -f "$MANIFESTS_TARGET"
