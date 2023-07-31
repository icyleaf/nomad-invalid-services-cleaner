# Nomad Invalid Services Cleaner

If you are using nomad to run your services, you can use this script to clean up invalid(zombie) services.

## Usage

### Docker

```bash
docker run -d --name nomad-invalid-services-cleaner:main \
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
        image = "ghcr.io/icyleaf/nomad-invalid-services-cleaner:main"
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
        image = "ghcr.io/icyleaf/nomad-invalid-services-cleaner:main"
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
