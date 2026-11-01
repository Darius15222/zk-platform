# floci accepts any credentials; GitHub token comes from the gh CLI login
export AWS_ACCESS_KEY_ID ?= test
export AWS_SECRET_ACCESS_KEY ?= test

WORKSPACE ?= ../..
GH = cd github && GITHUB_TOKEN=$$(gh auth token)
LOCAL = terraform -chdir=envs/local

.PHONY: state github-init github-plan github-apply secret-elastic show-password init plan up down

state: ## create the Terraform state bucket in floci (once)
	aws --endpoint-url http://localhost:4566 --region eu-central-1 s3 mb s3://zk-tfstate || true

github-init: state
	$(GH) terraform init -input=false

github-plan:
	$(GH) terraform plan -input=false

github-apply:
	$(GH) terraform apply -input=false

# R-02: random password, encrypted straight into git as SOPS ciphertext; plaintext never touches disk or the terminal
secret-elastic:
	@test ! -e secrets/elastic.enc.yaml || { echo "secrets/elastic.enc.yaml exists; delete it to rotate"; exit 1; }
	@printf 'zk_admin_password: %s\n' "$$(openssl rand -hex 20)" \
	  | sops --encrypt --filename-override secrets/elastic.enc.yaml --input-type yaml --output-type yaml /dev/stdin \
	  > secrets/elastic.enc.yaml
	@echo "wrote secrets/elastic.enc.yaml"

show-password: ## for humans only; the assistant is blocked from sops -d
	@sops -d --extract '["zk_admin_password"]' secrets/elastic.enc.yaml; echo

init: state
	$(LOCAL) init -input=false

plan:
	$(LOCAL) plan -input=false

up: ## start the cluster, then converge everything
	$(WORKSPACE)/local-stack/up.sh
	$(LOCAL) apply -input=false -auto-approve

down:
	$(WORKSPACE)/local-stack/down.sh
