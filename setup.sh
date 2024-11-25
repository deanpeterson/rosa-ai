source tools/format.sh
step=$1
if [[ -z "$step" || "$step" == "1" ]]; then 
  __ "ROSA AI Starter configuration tool" 1
  __ "Set up ROSA cluster using demo.redhat.com - ROSA Workshop" 2
  ___ "Wait until the environment has been provisioned."

  __ "Step 1 - Connect to Bastion" 3
  __ "Collecting initial provisioning data for automation:" 4
  _? "What is the bastion ssh host for your demo environment" BASTION $BASTION
  __ "Setup bastion connection and continue there" 4
  __ "Provide bastion ssh password to copy keys when prompted" 5
  ssh-copy-id -o StrictHostKeyChecking=accept-new rosa@$BASTION
  __ "Connect to bastion via ssh using -A flag" 4
  # Checkout dependencies
  ssh -A rosa@$BASTION "git clone ssh://git@gitlab.consulting.redhat.com:2222/ai-odyssey-2025/assist4real/demo-project.git ai-starter"
  # rsync -va ./ rosa@$BASTION:ai-starter/
  ssh -A rosa@$BASTION "cd ai-starter && pwd && ./setup.sh 2"
  exit 0
fi
clusterInfo=$(rosa list clusters -o json)
if [[ -n "$step" && "$step" == "2" ]]; then 
  __ "Step 2 - Setup ROSA" 3
  API_URL=$(echo "$clusterInfo" | jq -r '.[].api.url')
  __ "Collecting additional provisioning data for automation:" 4
  _? "What is the rosa admin password" API_PWD
  _? "What is the rosa api url" API_URL "" $API_URL
  cmd oc login -u cluster-admin -p "$API_PWD" "$API_URL"
  __ "Create ROSA admin account - should exist" 4
  cmd "rosa create admin --cluster rosa-$GUID"
  __ "Setup scratch folder for artifacts" 4
  cmd "mkdir -p scratch/"
  step=3
fi
if [[ -n "$step" && "$step" == "3" ]]; then 
  __ "Step 3 - Configure ROSA machine pool" 3
  _? "What is the instance type to use" instanceType m7i.4xlarge
  _? "What is the number of minimum replicas" minReplicas 1
  _? "What is the number of maximum replicas" maxReplicas 10
  __ "Add $instanceType machine pool with $minReplicas <= n <= $maxReplicas nodes" 4
  cmd "rosa create machinepool -c rosa-$GUID --name=customNodePool --min-replicas=$minReplicas --max-replicas=$maxReplicas --instance-type=$instanceType --enable-autoscaling --labels nodes=ai"
  step=4
fi
if [[ -n "$step" && "$step" == "4" ]]; then 
  # todo: while recommended version, upgrade
  __ "Step 4 - Upgrade ROSA" 3
  currentRosaVersion=$(echo "$clusterInfo" | jq -r '.[].openshift_version')
  nextRosaVersion=$(rosa list upgrades -c rosa-$GUID -o json | jq -r '.[0]')
  __ "Current     ROSA version: $currentRosaVersion" 5
  __ "Recommended ROSA version: $nextRosaVersion" 5
  _? "What version of ROSA" rosaVersion $nextRosaVersion
  cmd rosa upgrade cluster -c rosa-$GUID --control-plane --schedule-date $(date -d "+5 minutes 30 seconds" +"%Y-%m-%d") --schedule-time $(date -d "+6 minutes" +"%H:%M") -m auto -y --version $rosaVersion 
  __ "Wait for upgrade to finish" 4
  oo 1 "echo \$(( 1 - \$(rosa list upgrades -c rosa-$GUID | grep recommended | grep '$rosaVersion' | wc -l) ))"
  step=5
fi
if [[ -n "$step" && "$step" == "5" ]]; then 
  __ "Step 5 - Finish Openshift Setup" 3
  __ "Wait for machinepool to be ready" 4
  cmd "oc wait --for=jsonpath='{.status.phase}'=Active node -l nodes=ai"
  __ "Switch to AI machine pool" 4
  cmd "rosa update machinepool -c rosa-$GUID --replicas 0 workers"
  __ "Verify machine pools" 4
  cmd "rosa list machinepools -c rosa-$GUID"
  step=6
fi
if [[ -n "$step" && "$step" == "6" ]]; then 
  __ "Set up OpenShift AI" 2
  __ "Step 6 - Install Operators" 3
  __ "Web Terminal Operator" 4
  cmd oc apply -f configs/web-terminal-subscription.yaml
  __ "OpenShift Service Mesh" 4
  cmd oc create ns istio-system
  cmd oc create -f configs/servicemesh-subscription.yaml
  __ "OpenShift Serverless" 4
  cmd oc create -f configs/serverless-operator.yaml
  __ "Authorino" 4
  cmd oc create -f configs/authorino-subscription.yaml
  __ "Verify dependencies" 4
  cmd oc get subscriptions -A
  __ "OpenShift AI >2.11 via OLM on ROSA" 4
  cmd oc create -f configs/rhoai-operator-ns.yaml
  cmd oc create -f configs/rhoai-operator-group.yaml
  cmd oc create -f configs/rhoai-operator-subscription.yaml
  __ "Verify dependencies are installed" 5
  oo 3 'oc get projects | grep -E "redhat-ods|rhods" | wc -l'
  cmd oc create -f configs/rhoai-operator-dsc.yaml
  __ "Verify dependencies are installed" 5
  cmd oc get DSCInitialization,FeatureTracker -n redhat-ods-operator
  oo 4 "oc get DSCInitialization,FeatureTracker -n redhat-ods-operator | egrep -i 'DSCInitialization|FeatureTracker' | grep -iv Progressing | wc -l"
  __ "Install following operator with defaults using UI" 3
  __ "OpenShift Pipelines" 4
  ___ "Continue"
  __ "Red Hat OpenShift Dev Spaces" 4
  ___ "Continue"
  __ "Install operator, create CheCluster" 4
  ___ "Continue"
  __ "Patch CheCluster to never idle" 4
  patch='{"spec": {"devEnvironments": {"secondsOfInactivityBeforeIdling": -1,"secondsOfRunBeforeIdling": -1}}}'
  cmd "oc patch checluster devspaces -n openshift-operators --type='merge' -p='$patch'"
  step=7
fi
# Have a default storage class
if [[ -n "$step" && "$step" == "7" ]]; then 
  __ "Set up Teams" 2
  __ "Create namespace for each team, setup groups and roles" 3
  __ "Provision S3 Storage (endpoint requires protocol, valid cert via public url)" 4
  __ "Create groups for each team with 10 users" 5
  __ "Create Data Science Project" 6
  __ "Application Routes" 6
  __ "Create Workbench" 6
  cmd ./rosa-create-users-groups.sh 3
fi
exit 0;
# Available images: oc get imagestream -n redhat-ods-applications
