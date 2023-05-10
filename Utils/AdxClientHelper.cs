using Azure.Storage;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Blobs.Specialized;
using Azure.Storage.Sas;
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
        private readonly string storageSasToken;
        private readonly string blobConnectionString;

        public AdxClientHelper(IConfiguration config, ILogger log)
        {
            this.log = log;
            this._config = config;
            this.clusterUri = _config.GetValue<string>("adxConnectionString"); // TODO: Confirm if this is ingeston uri or cluster uri
            this.ingestionUri = _config.GetValue<string>("adxIngestionURI");
            this.databaseName = _config.GetValue<string>("metricsdbName");
            this.storageAccountName = _config.GetValue<string>("storageAccountName");
            this.containerName = _config.GetValue<string>("rawDataContainerName");
            this.storageSasToken = _config.GetValue<string>("storagesas");
            this.blobConnectionString = _config.GetValue<string>("blobConnectionString");
        }

        public KustoConnectionStringBuilder GetClient()
        {
            //var kcsb = new KustoConnectionStringBuilder(this.clusterUri, this.databaseName).WithAadSystemManagedIdentity();
            var kcsb = new KustoConnectionStringBuilder(clusterUri, databaseName).WithAadUserManagedIdentity(_config.GetValue<string>("msiclientId"));
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

        private async Task AppendToBlobAsync(string jsonData, string fileName)
        {
            // Create a BlobServiceClient object which is used to create a container client
            BlobServiceClient blobServiceClient = new BlobServiceClient(blobConnectionString);

            BlobContainerClient containerClient = null;
            bool bContainerExists = false;

            // Create the container and return a container client object
            foreach (Azure.Storage.Blobs.Models.BlobContainerItem blobContainerItem in blobServiceClient.GetBlobContainers())
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

            var stream = new MemoryStream(Encoding.UTF8.GetBytes(jsonData));

            stream.Position = 0;

            await blobClient.UploadAsync(stream, false);
        }

        public async Task IngestToAdx2Async(string batchResponse, string tableName)
        {
            string fileName = string.Format(@"{0}.json", Guid.NewGuid());

            await AppendToBlobAsync(batchResponse, fileName);

            log.LogInformation($"IngestionUri: {ingestionUri}");
            var ingestConnectionStringBuilder = new KustoConnectionStringBuilder(ingestionUri, databaseName).WithAadUserManagedIdentity(_config.GetValue<string>("msiclientId"));

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
                log.LogInformation($"https://{storageAccountName}.blob.core.windows.net/{containerName}/{fileName}{storageSasToken}",storageAccountName, containerName, fileName, storageSasToken);
                await client.IngestFromStorageAsync($"https://{storageAccountName}.blob.core.windows.net/{containerName}/{fileName}{storageSasToken}", ingestionProperties: kustoIngestionProperties, sourceOptions);
            }
        }
    }
}