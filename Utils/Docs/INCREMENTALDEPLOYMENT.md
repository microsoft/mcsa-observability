# Deploy Feature Enhancements
Note : if date on the wsl is incorrect fix this before proceeding - [this](#fix-date-out-of-sync-issue).

## Based on your requirements, take either of the steps below :
1. If tfstate files from previous deployments are deleted.
2. If tfstate files from previous deployment are available.

## 1. If tfstate files from previous deployments are deleted

a. Login to the azure portal and navigate to ADX tables in the deployed resource group

![tfstate1](../Images/adx.png)

b. Export the following database tables as CSVs

![tfstate2](../Images/adxtables.png)
			
c. Follow the steps to deploy the infrastructure as detailed here:

1. [install-using-terraform | Azure-Samples/observabilitymetrics-demo](https://github.com/Azure-Samples/observabilitymetrics-demo/tree/main#install-using-terraform)

2. Post installation

	a. Before performing the post installation steps import the CSVs that we exported in step [1(b)](#b.-Export-the-following-database-tables-as-CSVs) above into the respective tables in the newly created ADX tables

	b. [post-installation | Azure-Samples/observabilitymetrics-demo](https://github.com/Azure-Samples/observabilitymetrics-demo/tree/main#post-installation)

d. Wait for 15-30 minutes for the data to populate in the grafana instance.

## 2. If tfstate files from previous deployment are available
a. Copy over tfstate files from folders resources, grafana-datasource and grafana-dashboard

![tfstate2](../Images/tfstatecompare.png)

b. Run the steps for terraform deployment as detailed here
		
1. [install-using-terraform | Azure-Samples/observabilitymetrics-demo](https://github.com/Azure-Samples/observabilitymetrics-demo/tree/main#install-using-terraform)

	i.  Be sure to use the same arguments you did originally so that you deploy upgrades to the same subscription, resource group: prefix, subscriptiontId, location.

2.  [post-installation | Azure-Samples/observabilitymetrics-demo](https://github.com/Azure-Samples/observabilitymetrics-demo/tree/main#post-installation)

c. Store the generated tfstate files in a permanent storage so that newer features can be installed on top of existing deployments in the future.

## fix date out of sync issue

If the date on the wsl is incorrect (not in sync with the system clock) this can make scripts fail with unclear messages. To fix do the following:

	1. Check date and time by running "date"

	2. If out of sync run " sudo hwlock -s"

	3. Check if date is not correct. If not try a couple more times.

	4. If that does not work then run "apt install ntp"

	5. And then "ntpdate -u "in.pool.ntp.org"

