source tools/format.sh
step=$1
clusterInfo=$(rosa list clusters -o json)
CONSOLE_URL=$(echo "$clusterInfo" | jq -r '.[].console.url')
APP_URL=$(echo "$CONSOLE_URL" | cut -d\. -f2-)
SCRATCH_PATH="$(pwd)/scratch/"

__ "Install AI Demo App" 1

if [[ -z "$step" || "$step" == "1" ]]; then 
  __ "Step 1 - Pre-requisites" 2
  
  __ "Setup Scratch Environment" 3
  cmd "mkdir -p $SCRATCH_PATH"
  
  oc status 2>&1 
  if [ $? -ne 0 ]; then
  __ "Log into OpenShift Cluster as cluster-admin" 3
    _? "What is the cluster-admin password" API_PWD $API_PWD
    cmd oc login -u cluster-admin -p "$API_PWD" "$API_URL"
  fi
  
  __ "Collect Demo App details" 3
  step=2
fi

if [[ -n "$step" && "$step" == "2" ]]; then 
  __ "Step 2 - Setup Project/Namespace" 2
  _? "What is the namespace for the AI demo app: " NAMESPACE demo

  oc get ns $NAMESPACE 2>&1 
  if [ $? -ne 0 ]; then
    __ "Setup App namespace" 3
    cmd "oc new-project $NAMESPACE"
  fi
  cmd "oc project $NAMESPACE"
  
  step=3
fi

if [[ -n "$step" && "$step" == "3" ]]; then 
  __ "Step 3 - Install Red Hat Keycloak" 2
  __ "Create SSL Certificate" 3
  cmd "openssl req -subj '/CN=keycloak-${NAMESPACE}.${APP_URL}/O=Test Keycloak./C=US' -newkey rsa:2048 -nodes 
        -x509 -days 365 
        -keyout ${SCRATCH_PATH}key.pem
        -out    ${SCRATCH_PATH}certificate.pem"
  __ "Copy SSL Certificate into secret" 3
  cmd "oc create secret -n $NAMESPACE tls keycloak-tls-secret --cert ${SCRATCH_PATH}certificate.pem --key ${SCRATCH_PATH}key.pem"
fi
