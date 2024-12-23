# Makefile

.PHONY: validate plan up down

# Set the directory containing Terraform files (e.g., main.tf).
TF_DIR ?= aws

validate:
	@echo "Validating Terraform in $(TF_DIR)/..."
	terraform -chdir=$(TF_DIR) validate

plan:
	@echo "Planning Terraform configuration in $(TF_DIR)/..."
	terraform -chdir=$(TF_DIR) plan -var="my_ip=$$(curl -s ifconfig.me)"

up:
	@echo "Initializing Terraform in $(TF_DIR)/..."
	terraform -chdir=$(TF_DIR) init
	@echo "Applying Terraform configuration in $(TF_DIR)/..."
	terraform -chdir=$(TF_DIR) apply -auto-approve -var="my_ip=$$(curl -s ifconfig.me)"
	terraform -chdir=$(TF_DIR) output -raw my_public_key > $(TF_DIR)/id_rsa.pub
	terraform -chdir=$(TF_DIR) output -raw my_private_key > $(TF_DIR)/id_rsa
	chmod 600 aws/id_rsa*

verify-vm:
	@( set -e; \
	   JUMPBOX_PUBLIC_IP="$$(terraform -chdir=$(TF_DIR) output -raw jumpbox_public_ip)"; \
	   SERVER_PUBLIC_IP="$$(terraform -chdir=$(TF_DIR) output -raw server_public_ip)"; \
	   NODE0_PUBLIC_IP="$$(terraform -chdir=$(TF_DIR) output -raw node0_public_ip)"; \
	   NODE1_PUBLIC_IP="$$(terraform -chdir=$(TF_DIR) output -raw node1_public_ip)"; \
	 \
	   ssh-keyscan -t ed25519 $$JUMPBOX_PUBLIC_IP >> $(TF_DIR)/known_hosts; \
	   ssh-keyscan -t ed25519 $$SERVER_PUBLIC_IP >> $(TF_DIR)/known_hosts; \
	   ssh-keyscan -t ed25519 $$NODE0_PUBLIC_IP >> $(TF_DIR)/known_hosts; \
	   ssh-keyscan -t ed25519 $$NODE1_PUBLIC_IP >> $(TF_DIR)/known_hosts; \
	 \
	   printf "jumpbox: "; ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=$(TF_DIR)/known_hosts -i aws/id_rsa root@$$JUMPBOX_PUBLIC_IP uname -mov; \
	   printf "server:  "; ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=$(TF_DIR)/known_hosts -i aws/id_rsa root@$$SERVER_PUBLIC_IP uname -mov; \
	   printf "node0:   "; ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=$(TF_DIR)/known_hosts -i aws/id_rsa root@$$NODE0_PUBLIC_IP uname -mov; \
	   printf "node1:   "; ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=$(TF_DIR)/known_hosts -i aws/id_rsa root@$$NODE1_PUBLIC_IP uname -mov; \
	)

down:
	@echo "Destroying Terraform-managed resources in $(TF_DIR)/..."
	terraform -chdir=$(TF_DIR) destroy -auto-approve -var="my_ip=$$(curl -s ifconfig.me)"
	rm -f $(TF_DIR)/id_rsa* $(TF_DIR)/known_hosts
