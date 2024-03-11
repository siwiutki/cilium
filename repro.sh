#!/bin/bash -e

# feel free to change this config if you need so
CILIUM_CLI="./cilium-cli"
CILIUM_CLI_SHA256="5ff93edac14bd3b152b56ddb130b7e9352c1a452a4be9cf8ddc1555ce976b6c8"
COLLECT_SYSDUMP=0
ALWAYS_REBUILD=0
# modes:
# - 'local-all': cilium, operator, relay use locally built latest images for
#                upgrade and pre-pull v1.15 for install / downgrade from quay.io/cilium/*
# - 'ci-all': cilium, operator, relay use CI images for all steps
# - 'ci-cilium': cilium behaves as in 'ci-all', operator and relay as in 'local-all'
# TODO: it makes more sense to just have separate variables for things, like cilium, operator
#       and relay here, since adding new combinations makes the number of modes grow
#       exponentially, but I'm too sleepy to change it
TEST_MODE=local-all
if [[ "$#" -ge 1 ]]; then
      TEST_MODE=$1
      echo "Test mode provided in arguments, using $TEST_MODE mode..."
else
      echo "No test mode provided in arguments, using $TEST_MODE mode..."
fi

# this is bound to a particular CI run
CI_IMAGE_TAG="a31dbe8d1466d1100db801547979aa2d8011ea77"

# taken from CI failed run:
# https://github.com/cilium/cilium/actions/runs/8202718564/job/22434061383
# Changes:
# - s#./untrusted/cilium-downgrade/#./#g
# - s#./untrusted/cilium-newest/#./#g
# - add --helm-set=hubble.relay.enabled=true
# - depending on mode:
#   - change cilium image repository from quay.io/cilium/cilium-ci to quay.io/cilium/cilium
#   - remove operator image suffix
#   - change cilium image repository from quay.io/cilium/hubble-relay-ci to quay.io/cilium/hubble-relay
#   - use locally built cilium / operator / relay images with latest tag instead of images from CI
#   - set pull policy to Never to cilium / operator / relay
#   - upgrade / downgrade only cilium, operator / relay images are always latest
CILIUM_COMMON_OPTIONS="--wait     --chart-directory=./install/kubernetes/cilium     --helm-set=debug.enabled=true     --helm-set=debug.verbose=envoy     --helm-set=hubble.eventBufferCapacity=65535     --helm-set=bpf.monitorAggregation=none     --helm-set=cluster.name=default     --helm-set=authentication.mutual.spire.enabled=false     --nodes-without-cilium=kind-worker3     --helm-set-string=kubeProxyReplacement=disabled     --set='bpfClockProbe=false,cni.uninstall=false'     --helm-set-string=routingMode=native     --helm-set-string=autoDirectNodeRoutes=true --helm-set-string=ipv4NativeRoutingCIDR=10.244.0.0/16     --helm-set-string=ipv6NativeRoutingCIDR=fd00:10:244::/56     --helm-set=ipv6.enabled=true     --helm-set=encryption.enabled=true     --helm-set=encryption.type=ipsec     --helm-set=hubble.relay.enabled=true"
CILIUM_REPOSITORY_OPTIONS_LOCAL_ALL='--helm-set=image.repository=quay.io/cilium/cilium     --helm-set=image.useDigest=false     --helm-set=image.pullPolicy=Never     --helm-set=operator.image.repository=quay.io/cilium/operator     --helm-set=operator.image.suffix=     --helm-set=operator.image.useDigest=false     --helm-set=operator.image.pullPolicy=Never     --helm-set=hubble.relay.image.repository=quay.io/cilium/hubble-relay     --helm-set=hubble.relay.image.useDigest=false     --helm-set=hubble.relay.image.pullPolicy=Never'
CILIUM_REPOSITORY_OPTIONS_CI_ALL='--helm-set=image.repository=quay.io/cilium/cilium-ci     --helm-set=image.useDigest=false     --helm-set=operator.image.repository=quay.io/cilium/operator     --helm-set=operator.image.suffix=-ci     --helm-set=operator.image.useDigest=false     --helm-set=hubble.relay.image.repository=quay.io/cilium/hubble-relay-ci     --helm-set=hubble.relay.image.useDigest=false'
CILIUM_REPOSITORY_OPTIONS_CI_CILIUM='--helm-set=image.repository=quay.io/cilium/cilium-ci     --helm-set=image.useDigest=false     --helm-set=operator.image.repository=quay.io/cilium/operator     --helm-set=operator.image.suffix=     --helm-set=operator.image.useDigest=false     --helm-set=operator.image.pullPolicy=Never     --helm-set=hubble.relay.image.repository=quay.io/cilium/hubble-relay     --helm-set=hubble.relay.image.useDigest=false     --helm-set=hubble.relay.image.pullPolicy=Never'

CILIUM_1_15_OPTIONS_LOCAL_ALL="${CILIUM_COMMON_OPTIONS} ${CILIUM_REPOSITORY_OPTIONS_LOCAL_ALL} --helm-set=image.tag=v1.15.0 --helm-set=operator.image.tag=latest --helm-set=hubble.relay.image.tag=latest"
CILIUM_LATEST_OPTIONS_LOCAL_ALL="${CILIUM_COMMON_OPTIONS} ${CILIUM_REPOSITORY_OPTIONS_LOCAL_ALL} --helm-set=image.tag=latest --helm-set=operator.image.tag=latest --helm-set=hubble.relay.image.tag=latest"
CILIUM_1_15_OPTIONS_CI_ALL="${CILIUM_COMMON_OPTIONS} ${CILIUM_REPOSITORY_OPTIONS_CI_ALL} --helm-set=image.tag=v1.15 --helm-set=operator.image.tag=v1.15 --helm-set=hubble.relay.image.tag=v1.15"
CILIUM_LATEST_OPTIONS_CI_ALL="${CILIUM_COMMON_OPTIONS} ${CILIUM_REPOSITORY_OPTIONS_CI_ALL} --helm-set=image.tag=${CI_IMAGE_TAG} --helm-set=operator.image.tag=${CI_IMAGE_TAG} --helm-set=hubble.relay.image.tag=${CI_IMAGE_TAG}"
CILIUM_1_15_OPTIONS_CI_CILIUM="${CILIUM_COMMON_OPTIONS} ${CILIUM_REPOSITORY_OPTIONS_CI_CILIUM} --helm-set=image.tag=v1.15 --helm-set=operator.image.tag=latest --helm-set=hubble.relay.image.tag=latest"
CILIUM_LATEST_OPTIONS_CI_CILIUM="${CILIUM_COMMON_OPTIONS} ${CILIUM_REPOSITORY_OPTIONS_CI_CILIUM} --helm-set=image.tag=${CI_IMAGE_TAG} --helm-set=operator.image.tag=latest --helm-set=hubble.relay.image.tag=latest"

CILIUM_1_15_OPTIONS=""
CILIUM_LATEST_OPTIONS=""
if [[ ${TEST_MODE} == 'local-all' ]]; then
      CILIUM_1_15_OPTIONS="${CILIUM_1_15_OPTIONS_LOCAL_ALL}"
      CILIUM_LATEST_OPTIONS="${CILIUM_LATEST_OPTIONS_LOCAL_ALL}"
elif [[ ${TEST_MODE} == 'ci-all' ]]; then
      CILIUM_1_15_OPTIONS="${CILIUM_1_15_OPTIONS_CI_ALL}"
      CILIUM_LATEST_OPTIONS="${CILIUM_LATEST_OPTIONS_CI_ALL}"
elif [[ ${TEST_MODE} == 'ci-cilium' ]]; then
      CILIUM_1_15_OPTIONS="${CILIUM_1_15_OPTIONS_CI_CILIUM}"
      CILIUM_LATEST_OPTIONS="${CILIUM_LATEST_OPTIONS_CI_CILIUM}"
else
      echo "Invalid test mode, correct modes: local-all, ci-all, ci-cilium"
      exit 42
fi

# just some quick verification that cilium-cli path is valid and cli is release v0.16.0,
# since this is the version used by CI
GET_CILIUM_CLI_PROMPT="echo -e Run this to install cli:\n\nwget https://github.com/cilium/cilium-cli/releases/download/v0.16.0/cilium-linux-amd64.tar.gz\ntar xzvf cilium-linux-amd64.tar.gz\nmv cilium $CILIUM_CLI\nrm -f cilium-linux-amd64.tar.gz"

if [[ ! -f "${CILIUM_CLI}" ]]; then
      echo "Cilium CLI not found, ${CILIUM_CLI} does not exist"
      ${GET_CILIUM_CLI_PROMPT}
      exit 42
fi

if [[ ! `sha256sum "${CILIUM_CLI}" | awk '{ print $1 }'` == "${CILIUM_CLI_SHA256}" ]]; then
      echo "Invalid Cilium CLI sha256"
      ${GET_CILIUM_CLI_PROMPT}
      exit 42
fi

declare -a targets=()
if [[ ${TEST_MODE} == local-all ]]; then
      targets=("cilium" "operator-generic" "hubble-relay")
elif [[ ${TEST_MODE} == ci-cilium ]]; then
      targets=("operator-generic" "hubble-relay")
fi

if [[ "${#targets[@]}" -ne 0 ]]; then
      # check if docker images with latest tag are present, if not - build them
      for target in "${targets[@]}"; do
            if [[ $ALWAYS_REBUILD -ne 0 ]] || [[ `docker images -f reference=quay.io/cilium/${target}:latest | tail -n +2 | wc -l` -eq 0 ]]; then
                  make docker-${target}-image
            fi
      done

      # check for v1.15 images, pull if not present
      for target in "${targets[@]}"; do
            if [[ `docker images -f reference=quay.io/cilium/${target}:v1.15.0 | tail -n +2 | wc -l` -eq 0 ]]; then
                  docker pull quay.io/cilium/${target}:v1.15.0
            fi
      done

      # echo used images
      echo "Using the following images tagged as latest"
      filters=""
      for target in "${targets[@]}"; do
            filters="${filters} -f reference=quay.io/cilium/${target}:latest"
      done
      docker images ${filters}
fi

# setup kind cluster
echo "Creating kind cluster..."
./contrib/scripts/kind.sh "" 3 "" "" "iptables" "dual"
if [[ "${#targets[@]}" -ne 0 ]]; then
      for target in "${targets[@]}"; do
            kind load docker-image quay.io/cilium/${target}:latest
            kind load docker-image quay.io/cilium/${target}:v1.15.0
      done
fi
kubectl create -n kube-system secret generic cilium-ipsec-keys \
      --from-literal=keys="3 rfc4106(gcm(aes)) $(echo $(dd if=/dev/urandom count=20 bs=1 2> /dev/null | xxd -p -c 64)) 128"

# install cilium
echo "Installing Cilium v1.15..."
${CILIUM_CLI} install ${CILIUM_1_15_OPTIONS}
${CILIUM_CLI} status --wait

# upgrade cilium
echo "Upgrading Cilium..."
${CILIUM_CLI} upgrade ${CILIUM_LATEST_OPTIONS}
${CILIUM_CLI} status --wait

# prepare for conn-disrupt-test
echo "Preparing conn-disrupt-test..."
${CILIUM_CLI} connectivity test --include-conn-disrupt-test --conn-disrupt-test-setup

# downgrade cilium to v1.15
echo "Downgrading Cilium to v1.15..."
${CILIUM_CLI} upgrade ${CILIUM_1_15_OPTIONS}
${CILIUM_CLI} status --wait

# Run no-unexpected-packet-drops test
echo "Run conn-disrupt-test..."
if [ ${COLLECT_SYSDUMP} -ne 0 ]; then
  ${CILIUM_CLI} connectivity test --test no-unexpected-packet-drops --collect-sysdump-on-failure --flush-ct --sysdump-hubble-flows-count=1000000 --sysdump-hubble-flows-timeout=5m --sysdump-output-filename "sysdumps/cilium-sysdump-ipsec-downgrade-1-<ts>"
else
  ${CILIUM_CLI} connectivity test --test no-unexpected-packet-drops
fi
