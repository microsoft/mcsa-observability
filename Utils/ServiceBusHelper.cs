using Azure.Messaging.ServiceBus;
using System.Threading.Tasks;

namespace Observability.Utils
{
    public class ServiceBusHelper
    {
        private readonly IConfiguration _config;

        public ServiceBusHelper(IConfiguration config)
        {
            _config = config;
        }

        //public async ServiceBusSender GetSenderAsync()
        //{
        //    string queueName = _config.GetValue<string>("queueName");
        //    string connectionString = _config.GetValue<string>("ServiceBusConnection");

        //    var clientOptions = new ServiceBusClientOptions()
        //    {
        //        TransportType = ServiceBusTransportType.AmqpWebSockets
        //    };

        //    await using ServiceBusClient client = new ServiceBusClient(connectionString); 
        //    var sender = client.CreateSender(queueName);
        //    return sender;
        //}
    }
}