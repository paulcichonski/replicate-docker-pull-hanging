This repo provides an infrastructure that reliably replicates
https://github.com/coreos/bugs/issues/2457. Or at least I think it is that
issue, I've only seen it present as stalled `docker pulls` when using non
ebs optimized images _and_ an s3 backed docker registry.

## How to Build

_The below was tested with [terraform v0.11.7](https://github.com/hashicorp/terraform/releases/tag/v0.11.7)_

**Building This Will Cost You Money!**

```
## initialize
terraform init

## export keypair to use
export export TF_VAR_ssh_key=<keypair>

## build
terraform apply

## destroy
terraform destroy
```

## Replicate Issue

### First: Push an Image with Large Layers

```
ssh core@<staging_server_ip>

## using this because it is an image with some large layers
docker pull paulcichonski/docker-logstash-kafka:latest

docker tag paulcichonski/docker-logstash-kafka:latest <registry_ip>:5000/docker-logstash-kafka:latest
docker push <registry_ip>:5000/docker-logstash-kafka:latest
```

### Second: Try to pull it

This will hang:
```
ssh core@<server_1745_6_0_broken_ip>

docker pull <registry_ip>:5000/docker-logstash-kafka:latest
```

This won't:
```
ssh core@<server_1745_5_0_working_ip>

docker pull <registry_ip>:5000/docker-logstash-kafka:latest
```
