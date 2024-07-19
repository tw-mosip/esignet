#!/bin/bash
# Installs all esignet helm charts
## Usage: ./install.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

SOFTHSM_NS=softhsm
SOFTHSM_CHART_VERSION=12.0.1

echo Create $SOFTHSM_NS namespace
kubectl create ns $SOFTHSM_NS

NS=esignet
CHART_VERSION=1.4.1

ESIGNET_HOST=$(kubectl get cm global -o jsonpath={.data.mosip-esignet-host})

echo Create $NS namespace
kubectl create ns $NS

function installing_esignet() {

  echo Istio label
  kubectl label ns $SOFTHSM_NS istio-injection=enabled --overwrite
  helm repo add mosip https://mosip.github.io/mosip-helm
  helm repo update

  echo Installing Softhsm for esignet
  helm -n $SOFTHSM_NS install softhsm-esignet mosip/softhsm -f softhsm-values.yaml --version $SOFTHSM_CHART_VERSION --wait
  echo Installed Softhsm for esignet

  echo Copy configmaps
  ./copy_cm_func.sh configmap global default config-server

  echo Copy secrets
  ./copy_cm_func.sh secret softhsm-esignet softhsm config-server

  kubectl -n config-server set env --keys=mosip-esignet-host --from configmap/global deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  kubectl -n config-server set env --keys=security-pin --from secret/softhsm-esignet deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_SOFTHSM_ESIGNET_
  kubectl -n config-server rollout restart deploy config-server
  kubectl -n config-server get deploy -o name |  xargs -n1 -t  kubectl -n config-server rollout status

  ./keycloak-init.sh

  echo Please enter the recaptcha admin site key for domain $ESIGNET_HOST
  read ESITE_KEY
  echo Please enter the recaptcha admin secret key for domain $ESIGNET_HOST
  read ESECRET_KEY

  echo Setting up captcha secrets
  kubectl -n $NS create secret generic esignet-captcha --from-literal=esignet-captcha-site-key=$ESITE_KEY --from-literal=esignet-captcha-secret-key=$ESECRET_KEY --dry-run=client -o yaml | kubectl apply -f -

  echo Setting up dummy values for esignet misp license key
  kubectl create secret generic esignet-misp-onboarder-key -n $NS --from-literal=mosip-esignet-misp-key='' --dry-run=client -o yaml | kubectl apply -f -

  ./copy_cm_func.sh secret esignet-misp-onboarder-key esignet config-server

  echo Copy configmaps
  ./copy_cm.sh

  echo copy secrets
  ./copy_secrets.sh

  kubectl -n config-server set env --keys=esignet-captcha-site-key --from secret/esignet-captcha deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  kubectl -n config-server set env --keys=esignet-captcha-secret-key --from secret/esignet-captcha deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_
  kubectl -n config-server set env --keys=mosip-esignet-misp-key --from secret/esignet-misp-onboarder-key deployment/config-server --prefix=SPRING_CLOUD_CONFIG_SERVER_OVERRIDES_

  kubectl -n config-server get deploy -o name |  xargs -n1 -t  kubectl -n config-server rollout status

  echo "Do you have public domain & valid SSL? (Y/n) "
  echo "Y: if you have public domain & valid ssl certificate"
  echo "n: If you don't have a public domain and a valid SSL certificate. Note: It is recommended to use this option only in development environments."
  read -p "" flag

  if [ -z "$flag" ]; then
    echo "'flag' was provided; EXITING;"
    exit 1;
  fi
  ENABLE_INSECURE=''
  if [ "$flag" = "n" ]; then
    ENABLE_INSECURE='--set enable_insecure=true';
  fi

  default_enable_volume=false
  read -p "Would you like to enable volume (true/false) : [ default : false ] : " enable_volume
  enable_volume=${enable_volume:-$default_enable_volume}

  ESIGNET_HELM_ARGS=''
  if [[ $enable_volume == 'true' ]]; then

    default_volume_size=100M
    read -p "Provide the size for volume [ default : 100M ]" volume_size
    volume_size=${volume_size:-$default_volume_size}

    default_volume_mount_path='/home/mosip/config/'
    read -p "Provide the mount path for volume [ default : '/home/mosip/config/' ] : " volume_mount_path
    volume_mount_path=${volume_mount_path:-$default_volume_mount_path}

    PVC_CLAIM_NAME='esignet'
    ESIGNET_HELM_ARGS="--set persistence.enabled=true  \
                   --set volumePermissions.enabled=true \
                   --set persistence.mountDir=\"$volume_mount_path\" \
                   --set persistence.size=$volume_size \
                   --set springConfigNameEnv='esignet' \
                   --set activeProfileEnv=default     \
                   --set persistence.pvc_claim_name=\"$PVC_CLAIM_NAME\"  \
                   --set extraEnvVarsCM={'global','config-server-share','artifactory-share'} \
                  "
  fi
  echo "ESIGNET HELM ARGS $ESIGNET_HELM_ARGS"


  echo Installing esignet
  helm -n $NS install esignet mosip/esignet $ESIGNET_HELM_ARGS --version $CHART_VERSION $ENABLE_INSECURE

  kubectl -n $NS  get deploy -o name |  xargs -n1 -t  kubectl -n $NS rollout status

  echo Installed esignet service
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
installing_esignet   # calling function
