﻿namespace Observability.Utils.Data
{
    public class Message
    {
        public string Type { get; set; }
        public string SubscriptionID { get; set; }
        public string Location { get; set; }
        public DateTime From { get; set; }
        public DateTime To { get; set; }
        public string ResultTable { get; set; }
        public List<AzureResource> Resources { get; set; }
        
        public string TenantId {get; set; }

        public Message()
        {
            SubscriptionID = Location = Type = ResultTable = TenantId =  "";
            Resources = new List<AzureResource>();
        }
    }
}