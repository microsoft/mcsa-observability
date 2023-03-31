using Azure;
using Azure.Identity;
using Azure.Monitor.Query;
using Azure.Monitor.Query.Models;
using Observability.Utils.Data;
using System.Diagnostics;
//TODO: Is sppsettings.json file in this project needed still?
namespace Observability.Utils
{
    public class AzureMonitorHelper
    {
        MetricsQueryClient metricsClient;
        public AzureMonitorHelper()
        {
            metricsClient = new MetricsQueryClient(new DefaultAzureCredential());
        }

        public async Task RunBatchQuery(Message message)
        {
            string resourceId = message.Resources[0].ID;

            Response<MetricsQueryResult> results = await metricsClient.QueryResourceAsync(resourceId, new[] { "Microsoft.OperationalInsights/workspaces" });

            foreach (var metric in results.Value.Metrics)
            {
                Debug.WriteLine(metric.Name);
                foreach (var element in metric.TimeSeries)
                {
                    Debug.WriteLine("Dimensions: " + string.Join(",", element.Metadata));

                    foreach (var metricValue in element.Values)
                    {
                        Debug.WriteLine(metricValue);
                    }
                }
            }
        }
    }
}