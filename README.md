# Add-on BOSH Release for [prometheus-boshrelease](https://github.com/cloudfoundry-community/prometheus-boshrelease)

Add-on release with custom resources: dashboards, alerts for Prometheus Boshrelease.
Please, read the specs of each job to know more.


## Usage

This is and add-on release, it will work only if it is deployed together with the 
*prometheus-boshrelease* on the nodes.

Considering v2 manifest style, add the new releases in the `releases` block:

```
releases:
  [...]
- name: springernature-custom-alerts-dashboards
  version: latest
```

then in your `instance_groups`, add:
 
```
instance_groups:
  [...]
  jobs:
  [...]
  - name: grafana
    release: prometheus
  - name: mysql_cluster_dashboards
    release: springernature-custom-alerts-dashboards
```

### Dashboards

* mysql_cluster_dashboards. Provides cluster groups of mysql nodes based on a tag
called `cluster`. In order to use it with prometheus, you have to add a label
to the metrics. It has to be done in job scrape configuration (assuming one 
prometheus job per MySQL cluster):
```
# With static IPs of the MySQL nodes, just add the label.
- job_name: mysql-dev
  static_configs:
  - targets:
    - 10.230.11.215:9104
    - 10.230.24.2:9104
    labels:
      cluster: dev
      
```
```
# With dynamic discovery of the MySQL nodes (using bosh_exporter).
# Have a look at the second relabel_config to add a label `test` to the metrics.
- job_name: mysql-test
  file_sd_configs:
  - files:
    - /var/vcap/store/bosh_exporter/bosh_target_groups.json
  relabel_configs:
  - source_labels: [__meta_bosh_job_process_name]
    regex: mysqld_exporter
    action: keep
  - source_labels: [__address__]
    target_label: cluster
    regex: "(.*)"
    replacement: "test"
  - source_labels: [__address__]
    regex: "(.*)"
    target_label: __address__
    replacement: "${1}:9104"
```


### Alerts

* TODO



# Creating a new final release

Run: `./bosh_final_release`


# Author

SpringerNature Platform Engineering, José Riguera López (jose.riguera@springer.com)

Copyright 2017 Springer Nature



# License

Apache 2.0 License

