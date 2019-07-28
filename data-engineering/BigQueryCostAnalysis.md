# Working out BigQuery Costing using BigQuery

## StackDriver

Select `stackdriver` from the [GCP Console menu](https://console.cloud.google.com) and click on `Logs`. Select the resource type as `BigQuery`.
Add the filter as

```javascript
resource.type="bigquery_resource"
protoPayload.methodName="jobservice.jobcompleted"
```

Click on `CREATE EXPORT` and add a `sink name`. Set the sink destination to be `BigQuery` and select either a new or existing `Dataset`.

Use the following custom SQL in your favorite [Visualisation platform](https://datastudio.google.com) paying attention to the correct project and dataset names in the `FROM` clause:

```sql
SELECT
  protopayload_auditlog.authenticationInfo.principalEmail as user,
  sha512(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query) as linehash,
protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query as query,
  protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes as totalbilledbytes,
timestamp
FROM
  `<PROJECT>.<DATASET>.cloudaudit_googleapis_com_data_access_*`
```
