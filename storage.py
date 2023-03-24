from google.cloud import storage
import time
def authenticate_implicit_with_adc(project_id):
    storage_client = storage.Client(project=project_id)
    buckets = storage_client.list_buckets()
    print("Buckets:")
    for bucket in buckets:
        print(bucket.name)
    print("Listed all storage buckets.")

try:
    authenticate_implicit_with_adc("gke-projects-372400")
except:
    print("Unable to list the buckets")

while True:
    time.sleep(2)