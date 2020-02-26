# Replacement Labs for Data to Insights

First pin the public datasets to your project by going to:
[GCP Console](https://console.cloud.google.com/bigquery?project=bigquery-public-data)
You will get a jobs error (its not your project!). Click on the project on the middle left of the console and then click `pin project` middle right. This will make the project always appear in your list. Now go to the top blue bar and click on `select project` and set back to your qwiklabs project.

## Create dataset

Be aware of dataset locality, choose US for this lab.
Use the UI to create a dataset in your project called `Demo`.

## Instructor set-up

The instructor can set up a subset of the data (the full datat set is 112M records, which is not required for the lab), 1M records should do.

```sql
CREATE OR REPLACE TABLE
  Demo.stage1 AS
SELECT
  sha512(CONCAT(CAST(pickup_datetime AS string),CAST(dropoff_datetime AS string))) AS trip_id,
  pickup_datetime,
  dropoff_datetime,
  passenger_count,
  rate_code,
  pickup_location_id,
  dropoff_location_id,
  fare_amount
FROM
  `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2018`
LIMIT
  1000000
```

Now split the pickup and dropoff into two separate rows so the student can learn to rebuild the data into arrays of sructs.

```sql
CREATE OR REPLACE TABLE
  Demo.taxi_lab AS (
  SELECT
    trip_id,
    "Pickup" AS type,
    pickup_datetime AS event_datetime,
    passenger_count,
    NULL AS rate_code,
    pickup_location_id AS location_id,
    NULL AS fare_amount
  FROM
    Demo.stage1
  UNION ALL
  SELECT
    trip_id,
    "Dropoff" AS type,
    dropoff_datetime AS event_datetime,
    NULL AS passenger_count,
    rate_code,
    dropoff_location_id AS location_id,
    fare_amount
  FROM
    Demo.stage1 )
```

## Demonstrations and labs

Now, share the Demo dataset will `AllAuthenticatedUsers` and get the students to access the data using your qwiklabs project id exactly the same way they did with the public datasets. This demonstrates creating a public dataset and sharing across projects.

### Building structs and arrays

Students need to analyse the source data schema and build the output table with schema:

Field name | Type | Mode 
:--- | ---: | ---: 
trip_id | BYTES | NULLABLE 
passenger_count | INTEGER | NULLABLE	
rate_code | STRING | NULLABLE	
fare_amount | NUMERIC | NULLABLE	
event | RECORD | REPEATED	
event.type | STRING | NULLABLE	
event.event_datetime | DATETIME | NULLABLE	
event.location_id | STRING | NULLABLE	

And save the output as a view, say `Demo.nest_taxi_data`. You can demostrate authorized views at this point. There is a large problem with the below query (and we'll use it to demonstrate query optimization later)

#### Sample Solution

```sql
SELECT
  trip_id,
  MAX(passenger_count) as passenger_count,
  MAX(rate_code) as rate_code,
  MAX(fare_amount) as fare_amount,
  array_agg(struct(type,event_datetime,location_id)) as event
FROM
  `Demo.taxi_lab`
GROUP BY
  trip_id
```

### Join data with public dataset without moving it into your project

Because the taxi data does not contain actual locations but a location id, we need to find a dataset that will provide this information. Have a poke around the `bigquery-public-datasets`. 

Once you find it you'll need to work out how to measure the approximate distance between pickup and dropoff. Save this as a view called `Demo.location_ids`. You'll need the `zone_id`, `zone_name` and store the `CENTROID` of the zone area as a geometry point. Also point out the existance of the OSM (Open Street Map) dataset in BigQuery.

#### Sample solution

Dataset location: `bigquery-public-data.new_york_taxi_trips.taxi_zone_geom`

Preview the data by demoing [BigQuery Geo Visualizer](https://bigquerygeoviz.appspot.com) and the following query:

```sql
SELECT * FROM `bigquery-public-data.new_york_taxi_trips.taxi_zone_geom` LIMIT 1000
```

The code for the view is here:

```sql
SELECT
  zone_id,
  zone_name,
  ST_CENTROID(zone_geom) AS CENTROID
FROM
  `bigquery-public-data.new_york_taxi_trips.taxi_zone_geom`
```

### Join the data

Now we'll enrich the taxi data with the location geometries. To do this join the `Demo.location_ids` and `Demo.nest_taxi_data` tables. You will need to unnest and re-nest the data. You can demonstrate nested select queries.

#### Sample solution

```sql
SELECT
  trip_id,
  MAX(passenger_count),
  MAX(rate_code),
  MAX(fare_amount),
  ARRAY_AGG(STRUCT(type,
      datetime,
      geom))
FROM (
  SELECT
    trip_id,
    passenger_count,
    rate_code,
    fare_amount,
    events.type AS type,
    events.event_datetime AS datetime,
    l.CENTROID AS geom
  FROM
    `Demo.nest_taxi_data`
  CROSS JOIN
    UNNEST(event) AS events
  JOIN
    `Demo.location_ids` AS l
  ON
    l.zone_id=events.location_id )
GROUP BY
  trip_id
having 
  limiter=2 #why this line? Is there something we can do better
```

### Save the result table

The dataset takes a while to create so demonstrate saving a cached table using `save results` into BigQuery table named `Demo.prepared_data`. Discuss using materialization as a technique to reduce ops costs.

### `WITH` syntax

Direct the students to join the data and build it into lines. The lines can the give you distance. Also, drop the dropoff `timestamp` and only store the `pickup` timestamp and calculate the duration (This demostrates date calculations and generating spatial structures from data). Run this through BigQueryGeoViz to start looking at clusters. Spend some time discussion WGS 84, SRS 4326 and some of the limitation in BigQuery's spatial system. Key point, it does not work on mars as I cannot define a custom SRS for a lot of the calcs.

### Sample Solution

```sql
WITH
  prep_data AS (
  SELECT
    trip_id,
    passenger_count,
    rate_code,
    fare_amount,
    events.datetime AS datetime,
    events.geom AS geom
  FROM
    `Demo.prepared_data`
  CROSS JOIN
    UNNEST(event) AS events)
SELECT
  trip_id,
  MAX(passenger_count) AS passenger_count,
  MAX(rate_code) AS rate_code,
  MIN(datetime) AS starttime,
  DATETIME_DIFF(MAX(datetime),
    MIN(datetime),
    second) AS duration,
  st_makeline(ARRAY_AGG(geom)) AS line
FROM
  prep_data
GROUP BY
  trip_id
```

## Unsupervised ML

### kmeans clustering

Using the original `Demo.taxi_lab` estimate where to put hubs for our taxis assuming we are trying to optimise the pickup location and had budget for 5 hubs.

#### Sample Solution

```sql
CREATE OR REPLACE MODEL
  Demo.taxi_hub OPTIONS(model_type='kmeans',
    num_clusters=5,
    standardize_features = TRUE) AS (
  SELECT
    st_x(ST_CENTROID(zone_geom)) AS longitude,
    st_y(ST_CENTROID(zone_geom)) AS latitude,
  FROM
    `Demo.taxi_lab`
  JOIN
    `bigquery-public-data.new_york_taxi_trips.taxi_zone_geom`
  ON
    zone_id=location_id
  WHERE
    type="Pickup")
```

### Where are the hubs?

Students should be able to join the centroids from the model and plot them. This allows them to visually confirm these are on land. Discuss the benefits of visual Exploratory Data Analysis. Visualise the query in BigQueryGeoViz.

#### Sample Solution

```sql
SELECT
  centroid_id,
  ST_GEOGPOINT(
  MAX(
  IF
    (feature="longitude",
      numerical_value,
      NULL)),
  MAX(
  IF
    (feature="latitude",
      numerical_value,
      NULL)) ) as geom
FROM
  ML.CENTROIDS(MODEL `Demo.taxi_hub`)
GROUP BY
  centroid_id
```

### Get the zone names

Lets get the zone names that the centroids are in. This introduces Spatial joins (join when this `point` is in that `polygon`). And visualise in BigQueryGeoViz.

#### Sample code point based

```sql
with centroids as (SELECT
  centroid_id,
  ST_GEOGPOINT(
  MAX(
  IF
    (feature="longitude",
      numerical_value,
      NULL)),
  MAX(
  IF
    (feature="latitude",
      numerical_value,
      NULL)) ) as hubs
FROM
  ML.CENTROIDS(MODEL `Demo.taxi_hub`)
GROUP BY
  centroid_id), zones as (  SELECT

  zone_name,
  zone_geom
FROM
  `bigquery-public-data.new_york_taxi_trips.taxi_zone_geom`) select zone_name from centroids join zones on ST_WITHIN(hubs,zone_geom)
```

#### Sample code zone polygon based

```sql
with centroids as (SELECT
  centroid_id,
  ST_GEOGPOINT(
  MAX(
  IF
    (feature="longitude",
      numerical_value,
      NULL)),
  MAX(
  IF
    (feature="latitude",
      numerical_value,
      NULL)) ) as hubs
FROM
  ML.CENTROIDS(MODEL `Demo.taxi_hub`)
GROUP BY
  centroid_id), zones as (  SELECT
  zone_name,
  zone_geom
FROM
  `bigquery-public-data.new_york_taxi_trips.taxi_zone_geom`) select zone_name,hubs from centroids join zones on ST_WITHIN(hubs,zone_geom)
```
 



