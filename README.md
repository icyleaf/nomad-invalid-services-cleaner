# Nomad Invalid Services Cleaner

If you are using nomad to run your services, you can use this script to be done:

1. clean up invalid(zombie) services.
1. restart missing empty service(s) on running jobs.

## Usage

### Docker

```bash
docker run -d --name nomad-invalid-services-cleaner:0.1 \
  -e NOMAD_ENDPOINT=http://172.16.11.231 \
  -e NOMAD_VERSION=v1 \
  -e NOMAD_TOKEN=secret_token \
  -e NOMAD_RUNNER_INTERVAL=3600 \
  -e LOGGER_LEVEL=info \
  gchr.io/icyleaf/nomad-invalid-services-cleaner
```

### Nomad

#### Schedule run

```hcl
job "nomad-invalid-services-cleaner" {
  type        = "batch"

  periodic {
    prohibit_overlap  = true
    cron              = "0/10 * * * * *"
    time_zone         = "Asia/Shanghai"
  }

  group "services_cleaner" {
    task "cleaner" {
      driver = "docker"

      config {
        image = "ghcr.io/icyleaf/nomad-invalid-services-cleaner:0.1"
      }

      template {
        destination = "secrets/.env"
        env         = true
        data        = <<-EOF
        ONESHOT         = true

        NOMAD_ENDPOINT  = http://{{ env "attr.unique.network.ip-address" }}:4646

        {{- with nomadVar "nomad/jobs/nomad-invalid-services-cleaner" }}
        NOMAD_TOKEN = {{ .nomad_token }}
        {{- end}}
        EOF
      }

      resources {
        cpu     = 50
        memory  = 50
      }
    }
  }
}
```

#### Long loop run

```hcl
job "nomad-invalid-services-cleaner" {
  type        = "service"

  group "services_cleaner" {
    task "cleaner" {
      driver = "docker"

      config {
        image = "ghcr.io/icyleaf/nomad-invalid-services-cleaner:0.1"
      }

      template {
        destination = "secrets/.env"
        env         = true
        data        = <<-EOF
        NOMAD_ENDPOINT  = http://{{ env "attr.unique.network.ip-address" }}:4646

        {{- with nomadVar "nomad/jobs/nomad-invalid-services-cleaner" }}
        NOMAD_TOKEN = {{ .nomad_token }}
        {{- end}}
        EOF
      }

      resources {
        cpu     = 50
        memory  = 50
      }
    }
  }
}
```

## Output

### All good

```
I, [2023-07-31T11:50:41.151197 #1]  INFO -- : Starting nomad invalid services runner ...
I, [2023-07-31T11:50:41.176254 #1]  INFO -- : Found 57 services in namespace: default
I, [2023-07-31T11:50:41.357723 #1]  INFO -- : All services is good!
```

### Found issue

```
I, [2023-07-31T11:50:41.151197 #1]  INFO -- : Starting nomad invalid services runner ...
I, [2023-07-31T11:50:41.176254 #1]  INFO -- : Found 57 services in namespace: default
I, [2023-07-31T11:50:52.211327 #1]  INFO -- : Deleted invalid service sample-service (_nomad-task-4cb7a77c-d98e-8586-fef0-892000445f84-group-sample-service-web)
I, [2023-07-31T11:51:00.357723 #1]  INFO -- : Found 1 invalid services to clean up: sample-service
```

## Environments

- NOMAD_ENDPOINT: `http://127.0.0.1`
- NOMAD_VERSION: `v1` (default is `v1`)
- NOMAD_TOKEN: `inserct-token`
- NOMAD_API_TIMEOUT: `30` (default is `v1`)
- NOMAD_RUNNER_INTERVAL: `3600`
- LOGGER_LEVEL: `error/info/debug`
- NOMAD_IGNORE_RESTART_EMPTY_SERVICES: `true/false` (default is `false`)
