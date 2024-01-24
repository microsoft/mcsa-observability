namespace Observability.Utils.Data
{
    public class Tenant
    {
        public string ClientId { get; set; }
         public string Tenantid { get; set; }

         public string ClientSecret { get; set; }
        
        

        public Tenant()
        {
            ClientId =  "";
            Tenantid =  "";
            ClientSecret = "";
        }
    }
}