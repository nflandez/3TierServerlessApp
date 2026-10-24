# Serverless 3-Tier Task App (Terraform)

```
Browser
  |  HTTPS
[CloudFront] --> [S3 bucket, private]          Presentation tier
  |
  |  sign in (hosted UI, OAuth code + PKCE)
[Cognito user pool] --> access token (JWT)     Authentication
  |
  |  Authorization: Bearer <token>
[API Gateway HTTP API + JWT authorizer]        Application tier
  |
[Lambda (Python 3.12)]
  |
[DynamoDB table, on-demand]                    Data tier

CloudWatch: Lambda logs, API access logs, alarms, dashboard
```

## Modules

| Path | Creates |
|---|---|
| `modules/frontend` | Private S3 bucket, CloudFront distribution with Origin Access Control, site files |
| `modules/auth` | Cognito user pool, hosted UI domain, public app client |
| `modules/api` | Lambda function and least-privilege role, HTTP API with JWT authorizer, routes, throttling, access logs |
| `modules/data` | DynamoDB table keyed by user ID and task ID |
| `modules/monitoring` | Alarms (Lambda errors, API 5xx, 4xx spike), optional email alerts, CloudWatch dashboard |

## Run it from AWS CloudShell

```bash
export TF_DATA_DIR=/tmp/tfdata   # every new CloudShell session
cd serverless
terraform init
terraform validate
terraform plan
terraform apply                  # about 5 to 10 minutes, mostly CloudFront
terraform output
```

Open `site_url`, click **Sign in**, then **Sign up** to create an account.

## Tear down

```bash
export TF_DATA_DIR=/tmp/tfdata
terraform init
terraform destroy
```

Everything here is pay-per-use, so an idle stack costs close to nothing.
