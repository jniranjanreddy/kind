## deployinmg efk stack in Kind kubermnetes
```
kubectl create namespace logging

helm repo add elastic https://helm.elastic.co
helm install elasticsearch elastic/elasticsearch --set replicas=1 --set persistence.enabled=false -n logging

helm install kibana elastic/kibana -n logging


## get elasticsearch credentials
ES_PASSWORD=$(kubectl get secret --namespace=logging elasticsearch-master-credentials -o=jsonpath='{.data.password}' | base64 -d)
echo $ES_PASSWORD


## Install fluent-bit
NOTE: fluentbit-values.yaml will be updated with elasticsearch password

helm repo add fluent https://fluent.github.io/helm-charts
helm install fluent-bit fluent/fluent-bit -f fluentbit-values.yaml -n logging



cat fluentbit-values.yaml
env:
  - name: ES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: elasticsearch-master-credentials
        key: password

config:
  service: |
    [SERVICE]
        Flush        1
        Log_Level    info
        Daemon       Off
        Parsers_File parsers.conf

  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        Parser            docker
        Tag               kube.*
        Mem_Buf_Limit     5MB
        Skip_Long_Lines   On

  filters: |
    [FILTER]
        Name                kubernetes
        Match               kube.*
        Merge_Log           On
        Keep_Log            Off
        K8S-Logging.Parser  On
        K8S-Logging.Exclude On

  outputs: |
    [OUTPUT]
        Name                 es
        Match                kube.*
        Host                 elasticsearch-master.logging.svc.cluster.local
        Port                 9200
        HTTP_User            elastic
        HTTP_Passwd          Z6Wn372ergjGs1y0
        tls                  Off
        Logstash_Format      On
        Logstash_Prefix      logstash
        Retry_Limit          False

  customParsers: |
    [PARSER]
        Name        cri
        Format      regex
        Regex       ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<message>.*)$
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z
```
