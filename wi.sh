
YOURPORJECT="gke-project"
# Enable APIs for your project

gcloud services enable \
   --project=$YOURPORJECT \
   container.googleapis.com \
   gkeconnect.googleapis.com \
   gkehub.googleapis.com \
   cloudresourcemanager.googleapis.com \
   iam.googleapis.com

#0 Create GKE Cluster
gcloud container clusters create-auto wi \
    --region=us-west1
#1 Register to fleet
gcloud container fleet memberships register default \
 --gke-uri=https://container.googleapis.com/v1/projects/$YOURPORJECT/locations/us-west1/clusters/wi \
 --enable-workload-identity

# Get Workload Pool Identity
# gcloud container clusters describe wi --format="value(workloadIdentityConfig.workloadPool)" --region us-west1

#2 Get the values of WORKLOAD_IDENTITY_POOL and IDENTITY_PROVIDER for your registered cluster by retrieving the cluster's fleet membership details
gcloud container fleet memberships describe default

# output authority:
#   identityProvider: https://container.googleapis.com/v1/projects/$YOURPORJECT/locations/us-west1/clusters/wi
#   issuer: https://container.googleapis.com/v1/projects/$YOURPORJECT/locations/us-west1/clusters/wi
#   workloadIdentityPool: $YOURPORJECT.svc.id.goog

#3 Create SA 
gcloud iam service-accounts create impersonate1 --project=$YOURPORJECT

#output impersonate@$YOURPORJECT.iam.gserviceaccount.com

#4 Grant Persmission to impersonate@$YOURPORJECT.iam.gserviceaccount.com as Storage Admin
gcloud projects add-iam-policy-binding $YOURPORJECT --member='serviceAccount:impersonate1@$YOURPORJECT.iam.gserviceaccount.com' --role='roles/storage.admin'
#5 Creatre KSA
kubectl create serviceaccount access-storage1 \
    --namespace default
#5 Authorize your application's workload identity to impersonate the service account by creating an IAM policy binding
gcloud iam service-accounts add-iam-policy-binding \
  impersonate1@$YOURPORJECT.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser \
  --member="serviceAccount:$YOURPORJECT.svc.id.goog[default/access-storage1]"
#output Updated IAM policy for serviceAccount [impersonate@$YOURPORJECT.iam.gserviceaccount.com].
# bindings:
# - members:
#   - serviceAccount:$YOURPORJECT.svc.id.goog[default/access-storage]
#   role: roles/iam.workloadIdentityUser
# etag: BwX3dp5xc6o=
# version: 1

#6 Create a ConfigMap that contains the application default credentials file for your workload.
# This file tells the client library compiled into your workload how to authenticate to Google. 
# "audience": "identitynamespace:WORKLOAD_IDENTITY_POOL:IDENTITY_PROVIDER",
# "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/GSA_NAME@GSA_PROJECT_ID.iam.gserviceaccount.com:generateAccessToken",

cat <<ENDOFFILE | kubectl apply -f -
kind: ConfigMap
apiVersion: v1
metadata:
  namespace: default
  name: my-cloudsdk-config1
data:
  config: |
    {
      "type": "external_account",
      "audience": "identitynamespace:$YOURPORJECT.svc.id.goog:https://container.googleapis.com/v1/projects/$YOURPORJECT/locations/us-west1/clusters/wi",
      "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/impersonate1@$YOURPORJECT.iam.gserviceaccount.com:generateAccessToken",
      "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
      "token_url": "https://sts.googleapis.com/v1/token",
      "credential_source": {
        "file": "/var/run/secrets/tokens/gcp-ksa/token"
      }
    }
ENDOFFILE

#7 ConfigMap from the previous step is mounted in the container's filesystem 
# as google-application-credentials.json, alongside a projected service account token file
# , in /var/run/secrets/tokens/gcp-ksa 

cat <<ENDOFFILE | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: demo-pod
  namespace:  default
spec:
  serviceAccountName: access-storage1
  containers:
  - name: workload-identity-test
    image: us-west1-docker.pkg.dev/$YOURPORJECT/fancy/listbuckets:latest
    env:
      - name: GOOGLE_APPLICATION_CREDENTIALS
        value: /var/run/secrets/tokens/gcp-ksa/google-application-credentials.json
    volumeMounts:
    - name: gcp-ksa
      mountPath: /var/run/secrets/tokens/gcp-ksa
      readOnly: true
  volumes:
  - name: gcp-ksa
    projected:
      defaultMode: 420
      sources:
      - serviceAccountToken:
          path: token
          audience: $YOURPORJECT.svc.id.goog
          expirationSeconds: 172800
      - configMap:
          name: my-cloudsdk-config1
          optional: false
          items:
            - key: "config"
              path: "google-application-credentials.json"
ENDOFFILE

# Test POD
kubectl exec -it demo-pod -- /bin/bash
cat /var/run/secrets/tokens/gcp-ksa/google-application-credentials.json 
cat /var/run/secrets/tokens/gcp-ksa/token

kubectl logs demo-pod
# Shoud list buckets