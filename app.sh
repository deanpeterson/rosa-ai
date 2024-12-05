source tools/format.sh
step=$1
NAMESPACE=attempt9
clusterName="rosa-$GUID"
clusterInfo=$(rosa list clusters -o json)
CONSOLE_URL=$(echo "$clusterInfo" | jq -r '.[].console.url')
API_URL=$(echo "$clusterInfo" | jq -r '.[].api.url')
APP_URL=$(echo "$CONSOLE_URL" | cut -d\. -f2-)
BASE_DOMAIN=$(echo "$CONSOLE_URL" | cut -d\. -f3-)
SETUP_PATH=$(pwd)
PROJECT_PATH=$(dirname $SETUP_PATH)
DEMO_PATH=$PROJECT_PATH/demo-app/
SCRATCH_PATH="$DEMO_PATH/scratch/"
GITOPS_PATH="$DEMO_PATH/gitops/"
__ "Install AI Demo App" 1

if [[ -z "$step" || "$step" == "1" ]]; then 
  __ "Step 1 - Pre-requisites" 2

  __ "Checkout AI Starter Kit" 3
  cmd "git clone https://github.com/purefield-demo-team/ai-hackathon-starter.git $DEMO_PATH"
  
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
  _? "What is the namespace for the AI demo app: " NAMESPACE $NAMESPACE

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
  __ "Generate SSL Certificate" 4
  cmd "openssl req -subj '/CN=keycloak-${NAMESPACE}.${APP_URL}/O=Test Keycloak./C=US' -newkey rsa:2048 -nodes -x509 -days 365 -keyout ${SCRATCH_PATH}key.pem -out    ${SCRATCH_PATH}certificate.pem"

  __ "Copy SSL Certificate into secret" 4
  cmd "oc create secret -n $NAMESPACE tls keycloak-tls-secret --cert ${SCRATCH_PATH}certificate.pem --key ${SCRATCH_PATH}key.pem"

  __ "Configure postgresql variables" 3
  postgresqlConfig=${GITOPS_PATH}rhbk/keycloak-postgresql-chart/values.yaml
  baseDomain=$(echo $BASE_DOMAIN | cut -d\. -f2-)
  podSelector="-l name=keycloak-postgresql -n $NAMESPACE"
  cmd "perl -pe 's/(\s+name:) salamander/\$1 rosa/' -i $postgresqlConfig"
  cmd "perl -pe 's/(\s+domain:) aiml.*?$/\$1 $baseDomain/' -i $postgresqlConfig"

  __ "Run helm charts for postgresql" 3
  cmd "helm install keycloak-postgresql ${GITOPS_PATH}rhbk/keycloak-postgresql-chart/"

  __ "Wait for keycloak-postgres pod to be present" 4
  oo 1 "oc get pod $podSelector -o name | wc -l"
  cmd "oc wait pod $podSelector --for=condition=ready"

  __ "Restore the keycloak.backup file in the gitops/rhbk folder to postgresql" 3
  pod=$(oc get pod $podSelector -o name | cut -d\/ -f2-)
  # oc rsh pod/$pod /bin/bash -c 'pg_dump -d keycloak -U postgres -F t -f /var/lib/pgsql/data/userdata/keycloak.backup
  cmd "rsync --rsh='oc rsh' ${GITOPS_PATH}rhbk/keycloak.backup $pod:/var/lib/pgsql/data/userdata/"
  cmd "oc rsh pod/$pod /bin/bash -c 'ls -rtla /var/lib/pgsql/data/userdata/keycloak.backup'"
  cmd "oc rsh pod/$pod /bin/bash -c 'pg_restore -d keycloak -U postgres /var/lib/pgsql/data/userdata/keycloak.backup'"
  cmd "oc rsh pod/$pod /bin/bash -c 'rm -f /var/lib/pgsql/data/userdata/keycloak.backup*'"

  __ "Configure keycloak variables" 3
  keycloakConfig=${GITOPS_PATH}rhbk/keycloak-chart/values.yaml
  baseDomain=$(echo $BASE_DOMAIN | cut -d\. -f2-)
  cmd "perl -pe 's/(\s+name:) salamander/\$1 rosa/' -i $keycloakConfig"
  cmd "perl -pe 's/(\s+domain:) aiml.*?$/\$1 $baseDomain/' -i $keycloakConfig"

  __ "Run helm charts" 3
  cmd "helm install keycloak ${GITOPS_PATH}rhbk/keycloak-chart/"

  step=4
fi

if [[ -n "$step" && "$step" == "4" ]]; then 
  __ "Step 4 - Install Strapi" 2
  strapiConfig=${GITOPS_PATH}strapi/values.yaml
  baseDomain=$(echo $BASE_DOMAIN | cut -d\. -f2-)
  podSelector="-l name=strapi-postgresql -n $NAMESPACE"
  cmd "perl -pe 's/(\s+name:) salamander/\$1 rosa/' -i $strapiConfig"
  cmd "perl -pe 's/(\s+domain:) aiml.*?$/\$1 $baseDomain/' -i $strapiConfig"

  __ "Run helm charts for strapi" 3
  cmd "helm install strapi ${GITOPS_PATH}strapi/"

  __ "Wait for strapi-postgres pod to be present" 4
  oo 1 "oc get pod $podSelector -o name | wc -l"
  cmd "oc wait pod $podSelector --for=condition=ready --timeout=3m"
  pod=$(oc get pod $podSelector -o name | cut -d\/ -f2-)

  __ "Restore the strapi.backup file in the gitops/strapi folder to postgresql" 3
  cmd "rsync --rsh='oc rsh' ${GITOPS_PATH}strapi/strapi.backup $pod:/var/lib/pgsql/data/userdata/"
  cmd "oc rsh pod/$pod /bin/bash -c 'ls -rtla /var/lib/pgsql/data/userdata/strapi.backup'"
  cmd "oc rsh pod/$pod /bin/bash -c 'pg_restore -d strapi -U postgres /var/lib/pgsql/data/userdata/strapi.backup'"
  cmd "oc rsh pod/$pod /bin/bash -c 'rm -f /var/lib/pgsql/data/userdata/strapi.backup*'"

  __ "Update Keycloak url and namespace" 3
  export sql="update strapi_core_store_settings set value=REPLACE(REPLACE(REPLACE(value, 'salamander', 'rosa'), 'aimlworkbench.com', '$baseDomain'), 'restore-db-test', '$NAMESPACE') where id = 20"
  cmd 'oc rsh '$pod'  /bin/bash -c "psql -U postgres -d strapi -c \"$sql\""'
  unset sql
  
  __ "Update Vector-ask-short url" 3
  export sql="update strapi_webhooks set url=REPLACE(url, 'vector-ask-short.aimlworkbench.com', 'vector-ask-$NAMESPACE.apps.rosa.$baseDomain') where id in (2,3,5)"
  cmd 'oc rsh '$pod'  /bin/bash -c "psql -U postgres -d strapi -c \"$sql\""'
  unset sql

  __ "Build strapi app" 3
  cmd "oc start-build strapi"
  __ "Wait for strapi build to complete" 4
  cmd "oc wait builds -l buildconfig=strapi --for=condition=complete --timeout=3m"

  step=5
fi

if [[ -n "$step" && "$step" == "5" ]]; then 
  __ "Step 5 - ..." 2
  __ "Update Vector-ask-short url" 3
  podSelector="-l name=strapi-postgresql -n $NAMESPACE"
  pod=$(oc get pod $podSelector -o name | cut -d\/ -f2-)
  baseDomain=$(echo $BASE_DOMAIN | cut -d\. -f2-)

fi
if [[ -n "$step" && "$step" == "6" ]]; then 
  __ "Step 6 - ..." 2
fi
