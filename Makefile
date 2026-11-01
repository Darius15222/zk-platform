# floci accepts any credentials; GitHub token comes from the gh CLI login
export AWS_ACCESS_KEY_ID ?= test
export AWS_SECRET_ACCESS_KEY ?= test

GH = cd github && GITHUB_TOKEN=$$(gh auth token)

.PHONY: state github-init github-plan github-apply

state: ## create the Terraform state bucket in floci (once)
	aws --endpoint-url http://localhost:4566 --region eu-central-1 s3 mb s3://zk-tfstate || true

github-init: state
	$(GH) terraform init -input=false

github-plan:
	$(GH) terraform plan -input=false

github-apply:
	$(GH) terraform apply -input=false
