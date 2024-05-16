using Azure.Storage;
using Azure.Identity;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Blobs.Specialized;
using Kusto.Data;
using Kusto.Data.Common;
using Kusto.Data.Net.Client;
using Kusto.Ingest;
using System.Text;
using static System.Net.WebRequestMethods;

namespace Observability.Utils
{
    public class AdxClientHelper
    {
        private readonly IConfiguration _config;
        private ILogger log;
        private readonly string clusterUri;
        private readonly string ingestionUri;
        private readonly string databaseName;
        private readonly string containerName;
        private readonly string storageAccountName;
        private readonly string msiClientId;
        private readonly string msiObjectId;
        private readonly string keyVaultName;
        private static HashSet<string> seenFilePrefixes = new HashSet<string>();


        public AdxClientHelper(IConfiguration config, ILogger log)
        {
            this.log = log;
            this._config = config;
            this.clusterUri = _config.GetValue<string>("adxConnectionString"); // TODO: Confirm if this is ingeston uri or cluster uri
            this.ingestionUri = _config.GetValue<string>("adxIngestionURI");
            this.databaseName = _config.GetValue<string>("metricsdbName");
            this.storageAccountName = _config.GetValue<string>("storageAccountName");
            this.containerName = _config.GetValue<string>("rawDataContainerName");
            this.msiClientId = _config.GetValue<string>("msiclientId");
            this.msiObjectId = _config.GetValue<string>("msiObjectId");
            this.keyVaultName = _config.GetValue<string>("keyVaultName");
        }

        public KustoConnectionStringBuilder GetClient()
        {
            //var kcsb = new KustoConnectionStringBuilder(this.clusterUri, this.databaseName).WithAadSystemManagedIdentity();
            var kcsb = new KustoConnectionStringBuilder(clusterUri, databaseName).WithAadUserManagedIdentity(msiClientId);
            return kcsb;
        }

        public async Task IngestSubscriptionNameAsync(string subscriptionId, string subscriptionName)
        {
            var kcsb = GetClient();
            var kustoClient = KustoClientFactory.CreateCslAdminProvider(kcsb); //TODO: Why created in every method, could be in class constructor?

            var ingestQuery = $".ingest inline into table Subscription_Names <| {subscriptionId}, {subscriptionName}";
            await kustoClient.ExecuteControlCommandAsync(databaseName, ingestQuery);
        }

        public async Task IngestSubscriptionDateAsync(string subscriptionId, DateTime processedTime)
        {
            var kcsb = GetClient();

            var kustoClient = KustoClientFactory.CreateCslAdminProvider(kcsb); //TODO: Why created in every method, could be in class constructor?

            var ingestQuery = $".ingest inline into table Subscriptions_Processed <| {subscriptionId},{processedTime}";
            await kustoClient.ExecuteControlCommandAsync(databaseName, ingestQuery);
        }

        public async Task IngestToAdxAsync(string batchResponse, string tableName)
        {
            string fileName = string.Format(@"{0}.json", Guid.NewGuid());

            await AppendToBlobAsync(batchResponse, fileName);

            var kcsb = GetClient();

            var kustoClient = KustoClientFactory.CreateCslAdminProvider(kcsb);

            //// Ingest the JSON data multijson format (meaning one large JSON object and not an object per line)
            var ingestCommand = $".ingest into table {tableName}_Raw('https://{storageAccountName}.blob.core.windows.net/{containerName}/{fileName}') with '{{\"format\":\"multijson\", \"ingestionMappingReference\":\"RawMetricsMapping\"}}'";
            await kustoClient.ExecuteControlCommandAsync(databaseName, ingestCommand);
        }

        private async Task AppendToBlobAsync(string jsonData, string filePrefix)
        {

            if (seenFilePrefixes.Contains(filePrefix))
            {
                log.LogInformation($"File prefix {filePrefix} has already been uploaded. Skipping upload to storage container.");
                return;
            }

            seenFilePrefixes.Add(filePrefix);
            log.LogInformation($"Adding file prefix {filePrefix} to seen prefixes");

            string fileName = string.Format(@"{0}.json", filePrefix);

            // Create a ManagedIdentityCredential object
            var managedIdentityCredential = new ManagedIdentityCredential(msiClientId);
            // Create a BlobServiceClient object which is used to create a container client
            var blobServiceEndpoint = $"https://{storageAccountName}.blob.core.windows.net/";
            BlobServiceClient blobServiceClient = new BlobServiceClient(new Uri(blobServiceEndpoint), managedIdentityCredential);

            BlobContainerClient containerClient = null;
            bool bContainerExists = false;

            // Create the container and return a container client object
            foreach (BlobContainerItem blobContainerItem in blobServiceClient.GetBlobContainers())
            {
                if (blobContainerItem.Name == containerName)
                {
                    bContainerExists = true;
                    break;
                }
            }

            // Create or use existing Azure container as client.
            if (!bContainerExists)
            {
                containerClient = blobServiceClient.CreateBlobContainer(containerName);
            }
            else
                containerClient = blobServiceClient.GetBlobContainerClient(containerName);

            BlobClient blobClient = containerClient.GetBlobClient(fileName);

           try
            {
                // Try to upload the blob only if it doesn't already exist
                var stream = new MemoryStream(Encoding.UTF8.GetBytes(jsonData));
                stream.Position = 0;
                await blobClient.UploadAsync(stream, new BlobUploadOptions { Conditions = new BlobRequestConditions { IfNoneMatch = Azure.ETag.All } });
            }
            catch (Azure.RequestFailedException ex) when (ex.ErrorCode == BlobErrorCode.BlobAlreadyExists)
            {
                log.LogInformation($"Blob {fileName} already exists in the container {containerName}. Skipping upload.");
            }
        }

        public async Task IngestToAdx2Async(string batchResponse, string tableName, string filePrefix)
        {
            string fileName = string.Format(@"{0}.json", filePrefix);

            await AppendToBlobAsync(batchResponse, filePrefix);

            log.LogInformation($"IngestionUri: {ingestionUri}");
            var ingestConnectionStringBuilder = new KustoConnectionStringBuilder(ingestionUri, databaseName).WithAadUserManagedIdentity(msiClientId);

            // Client should be static
            // Create a disposable client that will execute the ingestion
            //TODO: Is above something that needs to be done?
            using (IKustoQueuedIngestClient client = KustoIngestFactory.CreateQueuedIngestClient(ingestConnectionStringBuilder))
            {
                log.LogInformation($"IngestClient: {client}");
                //Ingest from blobs according to the required properties
                var kustoIngestionProperties = new KustoQueuedIngestionProperties(databaseName: databaseName, tableName: $"{tableName}_Raw")
                {
                    Format = DataSourceFormat.multijson,
                    IngestionMapping = new IngestionMapping()
                    {
                        IngestionMappingReference = "RawMetricsMapping"
                    },
                    FlushImmediately = false
                };

                var sourceOptions = new StorageSourceOptions()
                {
                    DeleteSourceOnSuccess = false
                };

                await client.IngestFromStorageAsync($"https://{storageAccountName}.blob.core.windows.net/{containerName}/{fileName};managed_identity={msiObjectId}", ingestionProperties: kustoIngestionProperties, sourceOptions);
                log.LogInformation($"Ingested data from {fileName} to {tableName}_Raw with MSI Object Id {msiObjectId}");
            }
        }
    }
}
