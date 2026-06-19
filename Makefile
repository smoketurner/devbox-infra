ENV ?= dev
DIR = environments/$(ENV)

.PHONY: init fmt reconfigure validate plan apply refresh destroy

init:
	cd $(DIR) && AWS_PROFILE=dev-admin terraform init -upgrade

reconfigure:
	cd $(DIR) && AWS_PROFILE=dev-admin terraform init -reconfigure

fmt:
	AWS_PROFILE=dev-admin terraform fmt -recursive

validate: fmt
	cd $(DIR) && AWS_PROFILE=dev-admin terraform validate

plan: validate
	cd $(DIR) && AWS_PROFILE=dev-admin terraform plan

apply:
	cd $(DIR) && AWS_PROFILE=dev-admin terraform apply

refresh:
	cd $(DIR) && AWS_PROFILE=dev-admin terraform refresh

destroy:
	cd $(DIR) && AWS_PROFILE=dev-admin terraform destroy
